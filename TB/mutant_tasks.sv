// ===================== RTL mutant evaluation (verification only) =====================
  // Included inside module tb (like fault_tasks.sv). Used by +MUTSWEEP=1.
  //
  // FROZEN EXPECTATIONS. Written from assertions.sv (A01..A16), the S01..S10 procedural report
  // sites, and the mutation definitions in axi4_lite_ram_mutlib.sv, BEFORE any sweep was run.
  // Do not edit these tables to match a measurement; report mismatches as findings.
  //   exp detector / channel / category : the diagnosis the checker is expected to produce.
  //   channel is the DUT-port channel (the "D:" prefix is ignored: the expectation does not say
  //   which observation point must see it; MUTRES reports that separately as view=).
  //   allowed : detector IDs that are direct, by-construction consequences of the mutation
  //   (derived from the code path). Any other distinct detector ID counts as noise.
  //   Predicted cascades NOT in the allowed list (so a NOISY result is predicted, not a surprise):
  //     13, 14: the monitor keeps the unanswered request queued and pairs it with the next
  //             response, so later checks of the same test can mismatch (S04/S05/S06).
  //     1, 5  : when bready_dly/rready_dly == 1 the READY rises in the withdrawn cycle and the
  //             driver times out (S10 and follow-ons); the first detecting test avoids this.
  localparam int N_MUT = 20;
  localparam int CLK_NS = 10;   // matches "always #5 ACLK = ~ACLK"

  function automatic string mut_name(int id);
    case (id)
      0:  return "control";
      1:  return "bvalid_withdraw";
      2:  return "bresp_change_stall";
      3:  return "rdata_change_stall";
      4:  return "rresp_change_stall";
      5:  return "rvalid_withdraw";
      6:  return "strobe_ignored";
      7:  return "strobe_lane_swap";
      8:  return "decode_off_by_one";
      9:  return "write_alias_w0_w15";
      10: return "oor_write_okay";
      11: return "oor_read_okay";
      12: return "dup_b_pulse";
      13: return "drop_b";
      14: return "drop_r";
      15: return "rdata_bitflip_w3";
      16: return "reset_keeps_rvalid";
      17: return "second_aw_accepted";
      18: return "exokay_write";
      19: return "spurious_rvalid";
      20: return "early_b_before_w";
      default: return "unknown";
    endcase
  endfunction

  function automatic string mut_edet(int id);
    case (id)
      1: return "A07";  2: return "A08";  3: return "A10";  4: return "A10";  5: return "A09";
      6: return "S06";  7: return "S06";  8: return "S04";  9: return "S06";  10: return "S04";
      11: return "S05"; 12: return "A13"; 13: return "S09"; 14: return "S09"; 15: return "S06";
      16: return "A12"; 17: return "S06"; 18: return "A11"; 19: return "A14"; 20: return "A13";
      default: return "-";
    endcase
  endfunction

  function automatic string mut_ech(int id);
    case (id)
      1, 2, 8, 10, 12, 18, 20: return "B";
      3, 4, 5, 6, 7, 9, 11, 15, 17, 19: return "R";
      13, 14: return "REQ0";
      16: return "RST";
      default: return "-";
    endcase
  endfunction

  function automatic vcat_e mut_ecat(int id);
    case (id)
      1, 5:            return V_VALID_WITHDRAWAL;
      2, 3, 4:         return V_RESP_PAYLOAD_INSTAB;
      6, 7, 9, 15, 17: return V_DATA_MISMATCH;
      8, 10, 11:       return V_RESP_CODE_MISMATCH;
      12, 19, 20:      return V_UNEXPECTED_RESP;
      13, 14:          return V_MISSING_RESP;
      16:              return V_RESET_RECOVERY;
      18:              return V_ILLEGAL_RESP_ENC;
      default:         return V_VALID_WITHDRAWAL;
    endcase
  endfunction

  function automatic string mut_allow(int id);
    case (id)
      2:  return " S04 ";
      3:  return " S06 ";
      4:  return " S05 ";
      8:  return " S05 ";
      12: return " A07 ";
      13: return " S10 ";
      14: return " S10 ";
      16: return " A12b A14 S10 ";
      18: return " S04 ";
      19: return " A09 ";
      20: return " A07 ";
      default: return " ";
    endcase
  endfunction

  function automatic string chl(string ch);
    if (ch.len() >= 2 && ch.substr(0, 1) == "D:") return ch.substr(2, ch.len() - 1);
    return ch;
  endfunction

  function automatic bit has_tok(string lst, string d);
    string pat;
    pat = {" ", d, " "};
    for (int i = 0; i + pat.len() <= lst.len(); i++)
      if (lst.substr(i, i + pat.len() - 1) == pat) return 1'b1;
    return 1'b0;
  endfunction

  // ---- counters for MUTSUM ----
  int unsigned c_kill = 0, c_noisy = 0, c_mis = 0, c_miss = 0, c_nex = 0, c_inv = 0;
  bit          ctrl_ok = 1'b1;

  // Full re-initialization of the mutant, the reference model and the dedup state.
  task automatic mut_init(input int id);
    dut.mutid = id;
    dut.minit = 1'b1;
    do_reset();                         // minit is high for the whole reset
    dut.minit = 1'b0;
    if (rmh != null) foreach (rmh.mem[i]) rmh.mem[i] = 32'h0;
    viol_mon::reset_dedup();
  endtask

  // Directed exposure sequence used only by the validation phase: word 15 then word 0 (alias),
  // reads of both, and a write run for the "k-th since reset" mutants.
  task automatic run_expose();
    generator    gen;
    int unsigned base, d0, t0;
    gen = new(env.g2d, seed + 400, depth);
    neg_prep(0, 0, 0, 0);
    base = env.checked;
    d0   = env.drv.completed;
    t0   = env.drv.timeouts;
    gen.wr(32'h3C, 32'h13572468, 4'hF, 0, 0, 0);
    gen.wr(32'h00, 32'h0F0F0F0F, 4'hF, 0, 0, 0);
    gen.rd(32'h3C, 0, 0);
    gen.rd(32'h00, 0, 0);
    gen.wr(32'h08, 32'h2468ACE0, 4'hF, 0, 0, 3);
    gen.rd(32'h08, 0, 3);
    env.wait_done(base + gen.num_gen);
    repeat (5) @(posedge ACLK);
    env.scb.final_check(env.drv.completed - d0, env.drv.timeouts - t0,
                        env.mon.pend_wr(), env.mon.pend_rd(), env.mon.inc_wr());
  endtask

  // Validation phase: does the mutation fire (trig) and change DUT pins (pdiff) under an
  // exposure stimulus? Detection is NOT evaluated here: concurrent assertions of the two
  // protocol checkers are switched off for this phase only (to keep the log small) and are
  // switched on again before the evaluation phase. Records made here are ignored.
  task automatic mut_validate(input int id, output int unsigned vt, output int unsigned vp);
    mut_init(id);
    $assertoff(0, chk);
    $assertoff(0, dchk);
    run_test(lib.find("t_directed"));
    run_test(lib.find("t_boundary"));
    run_test(lib.find("t_strobe"));
    run_expose();
    run_test(lib.find("t_reset_live"));
    $asserton(0, chk);
    $asserton(0, dchk);
    vt = dut.m_trig;
    vp = dut.m_pdiff;
  endtask

  task automatic run_mutant(input int id);
    string       edet, ech, allow, got, view, cls, reason, sec_out, unexp_out, secs;
    string       lat_pin_s, lat_win_s;
    vcat_e       ecat;
    vrec_t       r;
    int unsigned base, nr, first_test, n_unexp, vt, vp, tr, pd;
    bit          det_ok, ch_ok, cat_ok, any_bus, any_dut, val_inv, ctl;
    time         t_start;
    longint      min_t;

    ctl   = (id == 0);
    edet  = mut_edet(id);  ech = mut_ech(id);  ecat = mut_ecat(id);  allow = mut_allow(id);
    vt = 0; vp = 0;
    if (!ctl && mut_val != 0) mut_validate(id, vt, vp);

    mut_init(id);
    base       = viol_mon::nrec();
    t_start    = $time;
    first_test = 0;
    foreach (lib.list[i]) begin
      run_test(lib.list[i]);
      if (first_test == 0 && viol_mon::nrec() > base) first_test = i + 1;
      if (first_test != 0 && mut_full == 0 && !ctl) break;
    end
    tr = dut.m_trig;
    pd = dut.m_pdiff;
    nr = viol_mon::nrec() - base;

    det_ok = 0; ch_ok = 0; cat_ok = 0; any_bus = 0; any_dut = 0;
    secs = " "; sec_out = ""; unexp_out = ""; n_unexp = 0; min_t = -1;
    got = "none";
    for (int i = 0; i < nr; i++) begin
      r = viol_mon::recs[base + i];
      if (i == 0) got = {r.det, "/", r.ch, "/", viol_mon::cname(r.cat)};
      if (min_t < 0 || longint'(r.t) < min_t) min_t = longint'(r.t);
      if (r.det == edet) begin
        det_ok = 1;
        if (chl(r.ch) == ech) begin
          ch_ok = 1;
          if (r.cat == ecat) begin
            cat_ok = 1;
            if (r.ch.len() >= 2 && r.ch.substr(0, 1) == "D:") any_dut = 1; else any_bus = 1;
          end
        end
      end else if (!has_tok(secs, r.det)) begin
        secs    = {secs, r.det, " "};
        sec_out = (sec_out == "") ? r.det : {sec_out, "+", r.det};
        if (!has_tok(allow, r.det)) begin
          n_unexp++;
          unexp_out = (unexp_out == "") ? r.det : {unexp_out, "+", r.det};
        end
      end
    end
    if (sec_out == "")   sec_out   = "-";
    if (unexp_out == "") unexp_out = "-";
    view = (any_bus && any_dut) ? "BOTH" : any_bus ? "BUS" : any_dut ? "DUT" : "NA";

    val_inv = (!ctl && mut_val != 0 && vt > 0 && vp == 0);
    reason  = "-";
    if (ctl) begin
      cls = (nr == 0 && tr == 0 && pd == 0) ? "CONTROL_OK" : "CONTROL_FAIL";
      if (cls == "CONTROL_FAIL") ctrl_ok = 1'b0;
    end else if (nr > 0 && tr == 0) begin
      cls = "INVALID_MUTANT"; reason = "reports_without_activation"; c_inv++;
    end else if (val_inv) begin
      cls = "INVALID_MUTANT"; reason = "activated_but_no_pin_difference_under_exposure"; c_inv++;
    end else if (nr == 0) begin
      if (tr == 0)      begin cls = "NOT_EXERCISED"; reason = "no_activation";     c_nex++; end
      else if (pd == 0) begin cls = "NOT_EXERCISED"; reason = "no_pin_difference"; c_nex++; end
      else              begin cls = "MISSED";                                      c_miss++; end
    end else if (!cat_ok) begin
      cls = "MISDIAGNOSED"; c_mis++;
    end else if (n_unexp > 0) begin
      cls = "NOISY"; c_noisy++;
    end else begin
      cls = "KILLED"; c_kill++;
    end

    if (nr > 0 && !ctl) begin
      lat_win_s = $sformatf("%0d", (min_t - longint'(t_start)) / CLK_NS);
      lat_pin_s = (dut.m_tdiff != 0) ? $sformatf("%0d", (min_t - longint'(dut.m_tdiff)) / CLK_NS) : "na";
    end else begin
      lat_win_s = "na"; lat_pin_s = "na";
    end

    $display("MUTRES,id=%0d,name=%s,exp=%s/%s/%s,got=%s,detected=%0d,det_ok=%0d,ch_ok=%0d,cat_ok=%0d,sec=%s,unexp_sec=%0d,unexp_ids=%s,trig=%0d,pdiff=%0d,val_trig=%0d,val_pdiff=%0d,nrec=%0d,tests_to_detect=%0d,lat_pin_cyc=%s,lat_win_cyc=%s,view=%s,class=%s,reason=%s",
             id, mut_name(id), edet, ech, viol_mon::cname(ecat), got, (nr > 0) ? 1 : 0,
             det_ok, ch_ok, cat_ok, sec_out, n_unexp, unexp_out, tr, pd, vt, vp, nr,
             first_test, lat_pin_s, lat_win_s, view, cls, reason);
  endtask

  function automatic string pct(int unsigned n, int unsigned d);
    if (d == 0) return "n/a";
    return $sformatf("%0d/%0d=%0.1f%%", n, d, 100.0 * real'(n) / real'(d));
  endfunction

  task automatic run_mutsweep();
    int unsigned den, lo, n_run;
    viol_mon::quiet = (mut_verbose == 0);
    rt_quiet        = (mut_verbose == 0);
    c_kill = 0; c_noisy = 0; c_mis = 0; c_miss = 0; c_nex = 0; c_inv = 0;
    run_mutant(0);                                    // control first, always full regress
    lo = (mut_first < 1) ? 1 : mut_first;
    n_run = 0;
    for (int id = lo; id <= mut_last && id <= N_MUT; id++) begin
      run_mutant(id);
      n_run++;
    end
    den = c_kill + c_noisy + c_mis + c_miss;
    $display("MUTSUM dut=rtlmut seed=%0d range=%0d..%0d mutants=%0d control=%s killed=%0d noisy=%0d misdiagnosed=%0d missed=%0d not_exercised=%0d invalid=%0d full=%0d val=%0d",
             seed, lo, mut_last, n_run, ctrl_ok ? "OK" : "FAIL",
             c_kill, c_noisy, c_mis, c_miss, c_nex, c_inv, mut_full, mut_val);
    $display("MUTRATE den=%0d (killed+noisy+misdiagnosed+missed; excludes not_exercised=%0d invalid=%0d and the control) detection_rate=%s expected_diag_rate=%s misdiag_rate=%s noise_rate=%s",
             den, c_nex, c_inv,
             pct(c_kill + c_noisy + c_mis, den), pct(c_kill + c_noisy, den),
             pct(c_mis, den), pct(c_noisy, den));
    viol_mon::quiet = 1'b0;
    rt_quiet        = 1'b0;
  endtask