package tb_pkg;
  `include "transaction.sv"
  `include "violation_monitor.sv"
  `include "monitor.sv"
  `include "coverage.sv"
  `include "scoreboard.sv"
  `include "gpio_model.sv"
  `include "generator.sv"
  `include "driver.sv"
  `include "environment.sv"
  `include "test.sv"
endpackage

`include "assertions.sv"
`include "latency_injector.sv"

module tb;
  import tb_pkg::*;

  localparam int AW = 32, DW = 32;
  localparam int WR_BASE_L1 = 2;   // RAM and GPIO baseline, measured at zero delay
  localparam int RD_BASE_L1 = 1;
  localparam int LAT_LIMIT  = 100; // L1 above this = timeout (late response)

  logic ACLK = 0, ARESETN = 0, FRST = 0;
  always #5 ACLK = ~ACLK;

  axi4l_if #(AW, DW) bus  (ACLK, ARESETN);   // master side: driver, monitor, checker
  axi4l_if #(AW, DW) dbus (ACLK, ARESETN);   // DUT side
  axi4l_if #(AW, DW) fbus (ACLK, FRST);      // fault-injection bus, no DUT

  dut_sel    dut    (.ACLK(ACLK), .ARESETN(ARESETN), .s(dbus));
  axi4l_shim u_shim (.m(bus), .d(dbus));

  axi4l_checker chk  (.vif(bus));
  axi4l_checker fchk (.vif(fbus));
  axi4l_checker #(.PT("D:")) dchk (.vif(dbus));   // DUT-facing compliance check

  environment env;
  test_lib    lib;
  ram_model   rmh;
  gpio_model  gmh;

  mailbox #(obs_txn) m2d = new();   // DUT-facing monitor output
  monitor     dmon;                 // monitor on dbus (DUT-facing)
  lat_probe   dprobe;               // DUT-side latency statistics

  int unsigned seed  = 1;
  int unsigned mut   = 0;
  int unsigned fault = 0;
  int unsigned negm  = 0;
  int unsigned maskm = 0;
  int unsigned injout = 0;   // +INJOUT=1: inject an unexpected violation between tests (final-status proof)
  int unsigned isoleak = 0;  // +ISOLEAK=1: disable DUT isolation (isolation-check proof)
  int unsigned n_ovr = 0;
  int unsigned depth = 16;
  bit [63:0]   prior = 64'h0;
  string       tname = "regress";
  string       dutname = "ram";

  int unsigned tests_run  = 0;
  int unsigned tests_pass = 0;
  int unsigned tests_fail = 0;
  int unsigned neg_run = 0, neg_det = 0, neg_mis = 0;
  int unsigned mask_run = 0, mask_ok = 0;
  int unsigned sum_test_unexp = 0;   // unexpected violations inside test windows
  int unsigned inj_mis = 0;          // injected-latency cross-check mismatches (informational)

  `include "fault_tasks.sv"

  task automatic do_reset();
    ARESETN <= 1'b0;
    repeat (3) @(posedge ACLK);
    if (gmh != null) gmh.on_reset();
    ARESETN <= 1'b1;
    repeat (2) @(posedge ACLK);
  endtask

  // L1 check: fixed cfg -> min==max==base+cfg ; random (-1) -> base..base+10
  function automatic bit lat_chk(int k, int cfg, int base);
    if (env.scb.lcnt[k] == 0) return 1'b0;
    if (cfg >= 0)
      return (env.scb.lmin[k][0] == (base + cfg)) && (env.scb.lmax[k][0] == (base + cfg));
    return (env.scb.lmin[k][0] >= base) && (env.scb.lmax[k][0] <= (base + 10));
  endfunction

  // Injected latency cross-check: master-side L1 minus DUT-side L1 must equal the configured delay.
  // Informational: reported, not part of PASS.
  function automatic string inj_str(int k, int cfg);
    longint dmin, dmax;
    if (cfg < 0) return "rand";
    if (env.scb.lcnt[k] == 0 || dprobe.lcnt[k] == 0) return "n/a";
    dmin = env.scb.lmin[k][0] - dprobe.lmin[k][0];
    dmax = env.scb.lmax[k][0] - dprobe.lmax[k][0];
    if (dmin == cfg && dmax == cfg) return "ok";
    inj_mis++;
    return $sformatf("MISMATCH(%0d,%0d)", dmin, dmax);
  endfunction

  // ======================= legal test =======================
  task automatic run_test(test_cfg c);
    generator    gen;
    int unsigned base, v0, u0, d0, t0, g0, cyc0, aw0, ar0, nb0, nr0, ab0;
    int unsigned acc, done, nviol, nunexp, mism, tos, abt;
    bit          ok, lat_ok, live;

    if (n_ovr > 0 && c.n_rand > 0) c.n_rand = n_ovr;

    viol_mon::set_ctx($sformatf("%s,seed=%0d", c.name, c.seed));

    u_shim.cfg_aw    = c.cfg_aw;
    u_shim.cfg_w     = c.cfg_w;
    u_shim.cfg_ar    = c.cfg_ar;
    u_shim.cfg_b     = c.cfg_b;
    u_shim.cfg_r     = c.cfg_r;
    u_shim.cfg_seed  = c.seed;
    u_shim.cfg_fault = 0;

    do_reset();                 // also re-picks shim delays with new cfg
    env.scb.clear_stats();
    dprobe.clear();
    env.sig = 0;

    base = env.checked;
    v0   = viol_mon::total();
    u0   = viol_mon::unexp_hits;
    d0   = env.drv.completed;
    t0   = env.drv.timeouts;
    ab0  = env.drv.aborted;
    cyc0 = env.mon.cycle;
    aw0  = env.mon.n_aw;
    ar0  = env.mon.n_ar;
    nb0  = env.mon.n_b;
    nr0  = env.mon.n_r;
    g0   = env.goals_hit();
    live = 1'b0;

    gen = new(env.g2d, c.seed, depth);
    if (c.dir[0]) gen.directed_basic();
    if (c.dir[1]) gen.directed_boundary();
    if (c.dir[2]) gen.directed_strobe();
    if (c.dir[3]) gen.directed_raw_waw();

    if (c.mid_reset) begin
      env.wait_done(base + gen.num_gen);
      repeat (3) @(posedge ACLK);
      do_reset();               // DUT reset while bus idle
    end

    if (c.live_reset) begin
      env.wait_done(base + gen.num_gen);
      gen.rd(32'h08, 0, 10);    // read response held 10 cycles by driver
      wait (env.mon.r_seen);    // RVALID up, RREADY low
      repeat (2) @(posedge ACLK);
      live = env.mon.r_seen;    // response really in flight at reset
      do_reset();               // reset under live traffic
      env.wait_done(base + gen.num_gen);
      gen.rd(32'h00, 0, 0);     // recovery: reads must work after reset
      gen.rd(32'h08, 0, 0);
      gen.rd(32'h0C, 0, 0);
    end

    if (c.n_rand > 0) gen.rand_traffic(c.n_rand);

    env.wait_done(base + gen.num_gen);
    repeat (5) @(posedge ACLK);

    env.scb.final_check(env.drv.completed - d0, env.drv.timeouts - t0,
                        env.mon.pend_wr(), env.mon.pend_rd(), env.mon.inc_wr());
    env.scb.limit_check(LAT_LIMIT);

    acc    = (env.mon.n_aw - aw0) + (env.mon.n_ar - ar0);
    done   = (env.mon.n_b - nb0) + (env.mon.n_r - nr0);
    nviol  = viol_mon::total() - v0;
    nunexp = viol_mon::unexp_hits - u0;
    sum_test_unexp += nunexp;
    mism   = env.scb.n_data_mis + env.scb.n_resp_mis;
    tos    = env.drv.timeouts - t0;
    abt    = env.drv.aborted - ab0;
    lat_ok = lat_chk(0, c.cfg_b, WR_BASE_L1) && lat_chk(1, c.cfg_r, RD_BASE_L1);
    ok     = (nunexp == 0) && (env.scb.errors() == 0) && lat_ok && (tos == 0)
             && (((env.drv.completed - d0) + abt) == gen.num_gen)
             && (c.live_reset ? (abt == 1 && live) : (abt == 0));

    tests_run++;
    if (ok) tests_pass++; else tests_fail++;

    // name,seed,gen,accepted,completed,wrL1,wrL3,rdL1,rdL3,timeouts,mismatch,viol,goals_new,goals_cum,cycles,abort,status
    $display("RESULT,%s,%0d,%0d,%0d,%0d,%s,%s,%s,%s,%0d,%0d,%0d,%0d,%0d/%0d,%0d,%0d,%s",
             c.name, c.seed, gen.num_gen, acc, done,
             env.scb.lat_str(0,0), env.scb.lat_str(0,2),
             env.scb.lat_str(1,0), env.scb.lat_str(1,2),
             tos, mism, nviol,
             env.goals_hit() - g0, env.goals_hit(), env.cov.tot,
             env.mon.cycle - cyc0, abt, ok ? "PASS" : "FAIL");
    // DUT-side (dbus) L1 and injected-delay cross-check
    $display("DLAT,%s,dut_wrL1=%s,dut_rdL1=%s,inj_wr=%s,inj_rd=%s",
             c.name, dprobe.str(0,0), dprobe.str(1,0),
             inj_str(0, c.cfg_b), inj_str(1, c.cfg_r));
    viol_mon::set_ctx("between_tests");
  endtask

  task automatic run_closure();
    test_cfg     c;
    string       todo [$];
    bit          seen_t [string];
    string       tn;
    c = lib.find("t_directed");
    run_test(c);
    for (int it = 0; it < 4; it++) begin
      if (env.mon.n_reset > 0) env.cov.hit("RST_OBSERVED");
      todo.delete();
      seen_t.delete();
      foreach (env.cov.gname[i]) begin
        if (!env.cov.ghit[i]) begin
          tn = lib.gap_test(env.cov.gname[i]);
          if (!seen_t.exists(tn)) begin
            seen_t[tn] = 1'b1;
            todo.push_back(tn);
          end
        end
      end
      $display("CLOSURE iter=%0d goals_hit=%0d/%0d picked=%0d",
               it, env.goals_hit(), env.cov.tot, todo.size());
      if (todo.size() == 0) break;
      foreach (todo[j]) begin
        $display("CLOSURE run %s", todo[j]);
        c = lib.find(todo[j]);
        run_test(c);
      end
    end
  endtask

  // ======================= negative tests =======================
  task automatic set_ign(bit v);
    if (rmh != null) rmh.ignore_strb = v;
    if (gmh != null) gmh.ignore_strb = v;
  endtask

  task automatic neg_prep(int cb, int cr, int caw, int flt);
    u_shim.cfg_aw    = caw;
    u_shim.cfg_w     = 0;
    u_shim.cfg_ar    = 0;
    u_shim.cfg_b     = cb;
    u_shim.cfg_r     = cr;
    u_shim.cfg_seed  = seed;
    u_shim.cfg_fault = flt;
    do_reset();                 // clears shim fault state
    env.scb.clear_stats();
    env.drv.timeout_cycles = 200;
    env.drv.flt_aw_chg     = 0;
    env.scb.skip_rd        = 0;
  endtask

  task automatic run_neg(input int n);
    generator    gen;
    int unsigned base, d0, t0, bef [NUM_VCAT];
    int unsigned phits, ahits, uhits, dd;
    vcat_e       prim;
    bit [15:0]   allow;
    string       nm, ubreak;
    bit          ok;

    allow = 16'h0;
    prim  = V_VALID_WITHDRAWAL;
    nm    = "none";
    viol_mon::set_ctx($sformatf("neg%0d,seed=%0d", n, seed));
    gen   = new(env.g2d, seed + 200 + n, depth);

    case (n)
      1: begin nm = "n_valid_withdraw_b"; prim = V_VALID_WITHDRAWAL;
               neg_prep(0, 0, 0, 1); end
      2: begin nm = "n_valid_withdraw_r"; prim = V_VALID_WITHDRAWAL;
               neg_prep(0, 0, 0, 3); end
      3: begin nm = "n_payload_change";   prim = V_PAYLOAD_INSTAB;
               neg_prep(0, 0, 4, 0); env.drv.flt_aw_chg = 1; end
      4: begin nm = "n_resp_unstable_b";  prim = V_RESP_PAYLOAD_INSTAB;
               neg_prep(0, 0, 0, 2); end
      5: begin nm = "n_resp_unstable_r";  prim = V_RESP_PAYLOAD_INSTAB;
               neg_prep(0, 0, 0, 4); end
      6: begin nm = "n_missing_resp";     prim = V_MISSING_RESP;
               allow[int'(V_RESP_TIMEOUT)] = 1'b1;
               neg_prep(0, 0, 0, 5); end
      7: begin nm = "n_resp_timeout";     prim = V_RESP_TIMEOUT;
               neg_prep(150, 0, 0, 0); env.drv.timeout_cycles = 400; end
      8: begin nm = "n_accounting";       prim = V_ACCOUNTING;
               neg_prep(0, 0, 0, 0); env.scb.skip_rd = 1; end
      default: begin nm = "n_data_mismatch"; prim = V_DATA_MISMATCH;
               neg_prep(0, 0, 0, 0); set_ign(1'b1); end
    endcase

    base = env.checked;
    d0   = env.drv.completed;
    t0   = env.drv.timeouts;
    for (int i = 0; i < NUM_VCAT; i++) bef[i] = viol_mon::cnt[i];

    case (n)
      1: gen.wr(32'h10, 32'hA1A1A1A1, 4'hF, 0, 0, 5);
      2: begin gen.wr(32'h10, 32'hB2B2B2B2, 4'hF, 0, 0, 0); gen.rd(32'h10, 0, 5); end
      3: gen.wr(32'h10, 32'hC3C3C3C3, 4'hF, 0, 0, 0);
      4: gen.wr(32'h10, 32'hD4D4D4D4, 4'hF, 0, 0, 5);
      5: begin gen.wr(32'h10, 32'hE5E5E5E5, 4'hF, 0, 0, 0); gen.rd(32'h10, 0, 5); end
      6: gen.wr(32'h10, 32'hF6F6F6F6, 4'hF, 0, 0, 0);
      7: gen.wr(32'h10, 32'h0A0B0C0D, 4'hF, 0, 0, 0);
      8: begin gen.wr(32'h10, 32'h01020304, 4'hF, 0, 0, 0);
               gen.rd(32'h10, 0, 0); gen.rd(32'h10, 0, 0); end
      default: begin gen.wr(32'h00, 32'h11223344, 4'hF, 0, 0, 0);
                     gen.wr(32'h00, 32'hAABBCCDD, 4'b0101, 0, 0, 0);
                     gen.rd(32'h00, 0, 0); end
    endcase

    env.wait_done(base + gen.num_gen);
    repeat (5) @(posedge ACLK);

    env.scb.final_check(env.drv.completed - d0, env.drv.timeouts - t0,
                        env.mon.pend_wr(), env.mon.pend_rd(), env.mon.inc_wr());
    env.scb.limit_check(LAT_LIMIT);

    set_ign(1'b0);
    env.drv.timeout_cycles = 200;
    env.drv.flt_aw_chg     = 0;
    env.scb.skip_rd        = 0;
    u_shim.cfg_fault       = 0;

    phits = 0; ahits = 0; uhits = 0; ubreak = "";
    for (int i = 0; i < NUM_VCAT; i++) begin
     dd = viol_mon::cnt[i] - bef[i];
      if (i == int'(prim))  phits += dd;
      else if (allow[i])    ahits += dd;
      else if (dd > 0) begin
        uhits += dd;
        ubreak = {ubreak, $sformatf(" %s=%0d", viol_mon::cname(vcat_e'(i)), dd)};
      end
    end
    ok = (phits >= 1) && (uhits == 0);
    neg_run++;
    if (ok) neg_det++; else neg_mis++;
    $display("NEGRES,%s,exp=%s,hits=%0d,allowed_conseq=%0d,unexpected=%0d,%s%s",
             nm, viol_mon::cname(prim), phits, ahits, uhits,
             ok ? "DETECTED" : "MISSED", (uhits > 0) ? {" unexpected:", ubreak} : "");
  endtask

  // ======================= masking test =======================
  // Needs +DUT=ram_mut (RAM mutant that withdraws BVALID once while BREADY is low).
  // With B-response hold-off in the shim the glitch is hidden from the master-facing bus,
  // but the DUT-facing checker still sees it. b_delay=0 is the control (visible at both).
  task automatic run_mask(input int cb);
    generator    gen;
    int unsigned base, d0, t0, bef [NUM_VCAT], bef_d [NUM_VCAT];
    int unsigned vw_all, vw_dut, vw_bus, other;
    int          vi;
    string       verdict;
    bit          ok;

    vi = int'(V_VALID_WITHDRAWAL);
    viol_mon::set_ctx($sformatf("mask_b%0d,seed=%0d", cb, seed));
    gen = new(env.g2d, seed + 300 + cb, depth);
    neg_prep(cb, 0, 0, 0);

    base = env.checked;
    d0   = env.drv.completed;
    t0   = env.drv.timeouts;
    for (int i = 0; i < NUM_VCAT; i++) begin
      bef[i]   = viol_mon::cnt[i];
      bef_d[i] = viol_mon::cnt_dut[i];
    end

    gen.wr(32'h10, 32'hC0DEC0DE, 4'hF, 0, 0, 3);   // BREADY held low 3 cycles after BVALID seen
    gen.rd(32'h10, 0, 0);
    env.wait_done(base + gen.num_gen);
    repeat (5) @(posedge ACLK);

    env.scb.final_check(env.drv.completed - d0, env.drv.timeouts - t0,
                        env.mon.pend_wr(), env.mon.pend_rd(), env.mon.inc_wr());

    vw_all = viol_mon::cnt[vi] - bef[vi];
    vw_dut = viol_mon::cnt_dut[vi] - bef_d[vi];
    vw_bus = vw_all - vw_dut;
    other  = 0;
    for (int i = 0; i < NUM_VCAT; i++)
      if (i != vi) other += viol_mon::cnt[i] - bef[i];

    if (cb == 0) begin
      ok = (vw_bus >= 1) && (vw_dut >= 1) && (other == 0);
      verdict = "VISIBLE_AT_BOTH(control)";
    end else begin
      ok = (vw_bus == 0) && (vw_dut >= 1) && (other == 0);
      verdict = "MASKED_AT_BUS_CAUGHT_AT_DUT";
    end
    mask_run++;
    if (ok) mask_ok++;
    $display("MASKRES,b_delay=%0d,withdrawal_at_bus=%0d,withdrawal_at_dut=%0d,other_hits=%0d,%s,%s",
             cb, vw_bus, vw_dut, other, verdict, ok ? "PASS" : "FAIL");
    viol_mon::set_ctx("between_tests");
  endtask

  // ======================= main =======================
  initial begin
    int unsigned lo, hi, det, mis;
    bit          ok;
    test_cfg     c;
    ref_model    rm;
    if (!$value$plusargs("SEED=%d",  seed))    seed    = 1;
    if (!$value$plusargs("MUT=%d",   mut))     mut     = 0;
    if (!$value$plusargs("FAULT=%d", fault))   fault   = 0;
    if (!$value$plusargs("NEG=%d",   negm))    negm    = 0;
    if (!$value$plusargs("MASK=%d",  maskm))   maskm   = 0;
    if (!$value$plusargs("INJOUT=%d", injout))  injout  = 0;
    if (!$value$plusargs("ISOLEAK=%d", isoleak)) isoleak = 0;
    if (!$value$plusargs("N=%d",     n_ovr))   n_ovr   = 0;
    if (!$value$plusargs("PRIOR=%h", prior))   prior   = 64'h0;
    if (!$value$plusargs("TEST=%s",  tname))   tname   = "regress";
    if (!$value$plusargs("DUT=%s",   dutname)) dutname = "ram";

    dut.leak = (isoleak != 0);
    if (maskm != 0) dutname = "ram_mut";   // masking test always uses the mutant

    if (dutname == "gpio") begin
      depth = 8;
      dut.sel = 1'b1;
      gmh = new(depth);
      gmh.ignore_strb = (mut == 1);
      rm = gmh;
    end else if (dutname == "ram_mut") begin
      depth = 16;
      dut.sel = 2'd2;
      rmh = new(depth);
      rmh.ignore_strb = (mut == 1);
      rm = rmh;
    end else begin
      depth = 16;
      dut.sel = 2'd0;
      rmh = new(depth);
      rmh.ignore_strb = (mut == 1);
      rm = rmh;
    end

    env = new(bus, depth, WR_BASE_L1, RD_BASE_L1, rm);
    lib = new(seed);
    env.start();
    dmon   = new(dbus, m2d);
    dprobe = new(m2d);
    fork
      dmon.run();
      dprobe.run();
    join_none

    $display("MANIFEST,dut=%s,test=%s,seed=%0d,mut=%0d,fault=%0d,neg=%0d,mask=%0d,injout=%0d,isoleak=%0d,n_ovr=%0d,prior=%h,lat_limit=%0d,wr_base=%0d,rd_base=%0d,depth=%0d",
             dutname, tname, seed, mut, fault, negm, maskm, injout, isoleak, n_ovr, prior, LAT_LIMIT, WR_BASE_L1, RD_BASE_L1, depth);

    viol_mon::set_ctx("startup");
    do_reset();
    viol_mon::set_ctx("between_tests");

    if (fault != 0) begin
      lo = (fault == 100) ? 1 : fault;
      hi = (fault == 100) ? 18 : fault;
      det = 0; mis = 0;
      for (int n = lo; n <= hi; n++) begin
        viol_mon::set_ctx($sformatf("fault%0d", n));
        run_fault(n);
        ok = (viol_mon::exp_hits >= 1) && (viol_mon::fault_unexpected() == 0);
        if (ok) det++; else mis++;
        $display("FAULT %0d exp=%s/%s hits=%0d unexpected=%0d %s",
                 n, viol_mon::cname(fault_cat(n)), fault_ch(n),
                 viol_mon::exp_hits, viol_mon::fault_unexpected(),
                 ok ? "DETECTED" : "MISSED");
      end
      viol_mon::clear_expect();
      env.cov.neg_report();
      $display("FAULTSUM run=%0d detected=%0d missed=%0d %s",
               hi - lo + 1, det, mis, (mis == 0) ? "PASS" : "FAIL");
      $finish;
    end else if (negm != 0) begin
      lo = (negm == 100) ? 1 : negm;
      hi = (negm == 100) ? 9 : negm;
      for (int n = lo; n <= hi; n++) run_neg(n);
      env.cov.neg_report();
      $display("NEGSUM dut=%s run=%0d detected=%0d missed=%0d %s",
               dutname, neg_run, neg_det, neg_mis, (neg_mis == 0) ? "PASS" : "FAIL");
      $finish;
    end else if (maskm != 0) begin
      mask_run = 0; mask_ok = 0;
      run_mask(0);
      run_mask(5);
      viol_mon::summary();
      $display("MASKSUM runs=%0d ok=%0d %s", mask_run, mask_ok, (mask_ok == mask_run) ? "PASS" : "FAIL");
      $finish;
    end else begin
      $display("HDR,test,seed,gen,accepted,completed,wrL1_min/avg/max,wrL3_min/avg/max,rdL1_min/avg/max,rdL3_min/avg/max,timeouts,mismatch,viol,goals_new,goals_cum,cycles,abort,status");
      if (tname == "regress") begin
        foreach (lib.list[i]) run_test(lib.list[i]);
      end else if (tname == "closure") begin
        run_closure();
      end else begin
        c = lib.find(tname);
        if (c == null) begin
          $display("STAGE9 ERROR unknown test %s", tname);
          $finish;
        end
        run_test(c);
      end

      if (injout != 0) begin
        // deliberate violation OUTSIDE any test window, never declared expected
        viol_mon::set_ctx("between_tests(injected)");
        fb_reset();
        fb_req_stall(0, 0, 1);
        repeat (3) @(posedge ACLK);
      end

      if (env.mon.n_reset > 0) env.cov.hit("RST_OBSERVED");
      viol_mon::summary();
      env.cov.report(prior, env.mon.n_reset);
      $display("REGRESS dut=%s tests=%0d pass=%0d fail=%0d goals_hit=%0d/%0d",
               dutname, tests_run, tests_pass, tests_fail, env.goals_hit(), env.cov.tot);
      $display("GLOBAL unexpected_total=%0d in_tests=%0d outside_tests=%0d iso_viol=%0d dut_facing=%0d inj_mismatch=%0d",
               viol_mon::unexp_hits, sum_test_unexp, viol_mon::unexp_hits - sum_test_unexp,
               dut.iso_viol, viol_mon::total_dut(), inj_mis);
      $display("STAGE9 mode=%s dut=%s seed=%0d mut=%0d cycles=%0d %s",
               tname, dutname, seed, mut, env.mon.cycle,
               (tests_fail == 0 && viol_mon::unexp_hits == 0 && dut.iso_viol == 0) ? "PASS" : "FAIL");
      $finish;
    end
  end

  initial begin
    #30000000;
    $display("STAGE9 WATCHDOG FAIL checked=%0d", env.checked);
    $finish;
  end

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb);
  end
endmodule