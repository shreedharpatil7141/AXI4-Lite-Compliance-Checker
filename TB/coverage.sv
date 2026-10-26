`ifndef AXI_COVERAGE_SV
`define AXI_COVERAGE_SV
class cov_collector;
  mailbox #(obs_txn) mon2cov;
  int unsigned       depth;
  int                wr_base, rd_base;

  // goal tracker
  string       gname [$];
  string       gtest [$];
  bit          ghit  [$];
  int unsigned run_hit, cum_hit, tot;

  // history
  bit          wrote [bit [31:0]];
  bit          have_prev;
  bit [31:0]   prev_addr;

  // sampled values for covergroups
  int v_strb, v_rsp, v_rgn, v_lat, v_bp, v_ord, v_raw, v_rep, v_cat;
  int v_aww_skew_class;
  int v_req_stall_cycles;
  int unsigned aww_skew_samples;
  int unsigned aww_skew_bin_hits [0:6];
  int unsigned req_stall_samples [0:2];
  int unsigned req_stall_bin_hits [0:2][0:4];
  int unsigned req_stall_unbinned [0:2];
  int unsigned last_aw_stall_cycles, last_w_stall_cycles, last_ar_stall_cycles;
  longint last_aw_cycle, last_w_cycle, last_aww_separation;

  covergroup cg_reqstall_aw;
    option.per_instance = 1;
    cp_stall: coverpoint v_req_stall_cycles {
      bins zero = {0}; bins one = {1}; bins two_three = {[2:3]};
      bins four_ten = {[4:10]}; bins eleven_plus = {[11:200]};
    }
  endgroup
  covergroup cg_reqstall_w;
    option.per_instance = 1;
    cp_stall: coverpoint v_req_stall_cycles {
      bins zero = {0}; bins one = {1}; bins two_three = {[2:3]};
      bins four_ten = {[4:10]}; bins eleven_plus = {[11:200]};
    }
  endgroup
  covergroup cg_reqstall_ar;
    option.per_instance = 1;
    cp_stall: coverpoint v_req_stall_cycles {
      bins zero = {0}; bins one = {1}; bins two_three = {[2:3]};
      bins four_ten = {[4:10]}; bins eleven_plus = {[11:200]};
    }
  endgroup

  covergroup cg_wr;
    option.per_instance = 1;
    cp_strb: coverpoint v_strb {
      bins none   = {0};
      bins full   = {15};
      bins single = {1, 2, 4, 8};
      bins multi  = {3, 5, 6, 7, 9, 10, 11, 12, 13, 14};
    }
    cp_rsp: coverpoint v_rsp { bins okay = {0}; bins slverr = {2}; }
    cp_rgn: coverpoint v_rgn {
      bins first = {0}; bins low = {1}; bins mid = {2};
      bins high = {3};  bins last = {4}; bins oor = {5};
    }
    cp_lat: coverpoint v_lat {
      bins d0 = {0}; bins d1 = {1}; bins d2 = {2}; bins d3_5 = {[3:5]}; bins d6_10 = {[6:10]};
    }
    cp_bp: coverpoint v_bp {
      bins b0 = {0}; bins b1 = {1}; bins b2 = {2}; bins b3_5 = {[3:5]}; bins b6_10 = {[6:10]};
    }
    cp_ord: coverpoint v_ord { bins aw_first = {0}; bins w_first = {1}; bins same = {2}; }
    cp_rep: coverpoint v_rep { bins no = {0}; bins yes = {1}; }
    x_bp_lat: cross cp_bp, cp_lat;
  endgroup

  // One completed write contributes exactly one direction-and-separation bin.
  // The class is derived from sampled handshake cycles, not driver settings.
  covergroup cg_aww_skew;
    option.per_instance = 1;
    cp_aww_skew: coverpoint v_aww_skew_class {
      bins same_cycle       = {0};
      bins aw_first_1       = {1};
      bins aw_first_2_3     = {2};
      bins aw_first_4_plus  = {3};
      bins w_first_1        = {4};
      bins w_first_2_3      = {5};
      bins w_first_4_plus   = {6};
    }
  endgroup

  covergroup cg_rd;
    option.per_instance = 1;
    cp_rsp: coverpoint v_rsp { bins okay = {0}; bins slverr = {2}; }
    cp_rgn: coverpoint v_rgn {
      bins first = {0}; bins low = {1}; bins mid = {2};
      bins high = {3};  bins last = {4}; bins oor = {5};
    }
    cp_lat: coverpoint v_lat {
      bins d0 = {0}; bins d1 = {1}; bins d2 = {2}; bins d3_5 = {[3:5]}; bins d6_10 = {[6:10]};
    }
    cp_bp: coverpoint v_bp {
      bins b0 = {0}; bins b1 = {1}; bins b2 = {2}; bins b3_5 = {[3:5]}; bins b6_10 = {[6:10]};
    }
    cp_raw: coverpoint v_raw { bins no = {0}; bins yes = {1}; }
    cp_rep: coverpoint v_rep { bins no = {0}; bins yes = {1}; }
    x_bp_lat: cross cp_bp, cp_lat;
  endgroup

  covergroup cg_neg;
    option.per_instance = 1;
    cp_cat: coverpoint v_cat { bins cat[] = {[0:NUM_VCAT-1]}; }
  endgroup

  function new(mailbox #(obs_txn) m, int unsigned depth, int wr_base, int rd_base);
    this.mon2cov = m;
    this.depth   = depth;
    this.wr_base = wr_base;
    this.rd_base = rd_base;
    have_prev = 1'b0; prev_addr = 0;
    run_hit = 0; cum_hit = 0; tot = 0;
    cg_wr  = new();
    cg_aww_skew = new();
    cg_rd  = new();
    cg_neg = new();
    cg_reqstall_aw = new(); cg_reqstall_w = new(); cg_reqstall_ar = new();
    aww_skew_samples = 0;
    for (int i = 0; i < 7; i++) aww_skew_bin_hits[i] = 0;
    for (int ch = 0; ch < 3; ch++) begin
      req_stall_samples[ch] = 0;
      req_stall_unbinned[ch] = 0;
      for (int b = 0; b < 5; b++) req_stall_bin_hits[ch][b] = 0;
    end
    last_aw_stall_cycles = 0; last_w_stall_cycles = 0; last_ar_stall_cycles = 0;
    last_aw_cycle = 0; last_w_cycle = 0; last_aww_separation = 0;
    define_goals();
  endfunction

  // Return classes 0..6 and a nonnegative separation. Compare before
  // subtracting so the direction calculation cannot underflow.
  function automatic int classify_aww_skew(input longint c_aw, input longint c_w,
                                            output longint separation);
    if (c_aw == c_w) begin
      separation = 0;
      return 0;
    end
    if (c_aw < c_w) begin
      separation = c_w - c_aw;
      if (separation == 1) return 1;
      if (separation <= 3) return 2;
      return 3;
    end
    separation = c_aw - c_w;
    if (separation == 1) return 4;
    if (separation <= 3) return 5;
    return 6;
  endfunction

  function string aww_skew_name(int class_id);
    case (class_id)
      0: return "same_cycle";
      1: return "aw_first_1";
      2: return "aw_first_2_3";
      3: return "aw_first_4_plus";
      4: return "w_first_1";
      5: return "w_first_2_3";
      6: return "w_first_4_plus";
      default: return "INVALID";
    endcase
  endfunction

  function void report_aww_skew();
    int unsigned bins_hit;
    bins_hit = 0;
    for (int i = 0; i < 7; i++)
      if (aww_skew_bin_hits[i] != 0) bins_hit++;
    $display("COV_AWW_SKEW native=%0.2f samples=%0d bins_hit=%0d/7",
             cg_aww_skew.get_inst_coverage(), aww_skew_samples, bins_hit);
    for (int i = 0; i < 7; i++)
      $display("COV_AWW_SKEW_BIN name=%s hits=%0d status=%s",
               aww_skew_name(i), aww_skew_bin_hits[i],
               (aww_skew_bin_hits[i] != 0) ? "HIT" : "UNCOVERED");
  endfunction

  function void add(string n, string t);
    gname.push_back(n); gtest.push_back(t); ghit.push_back(1'b0);
  endfunction

  function void hit(string n);
    foreach (gname[i]) if (gname[i] == n) ghit[i] = 1'b1;
  endfunction

  function string bin5(int v);
    if (v < 0)   return "NEG";
    if (v == 0)  return "D0";
    if (v == 1)  return "D1";
    if (v == 2)  return "D2";
    if (v <= 5)  return "D3_5";
    if (v <= 10) return "D6_10";
    return "OVER";
  endfunction

  function string rgn_name(int r);
    case (r)
      0: return "FIRST";
      1: return "LOW";
      2: return "MID";
      3: return "HIGH";
      4: return "LAST";
      default: return "OOR";
    endcase
  endfunction

  function void define_goals();
    string p, rg [6], lt [5], lts [5], bp [5];
    rg[0] = "FIRST"; rg[1] = "LOW"; rg[2] = "MID"; rg[3] = "HIGH"; rg[4] = "LAST"; rg[5] = "OOR";
    lt[0] = "D0"; lt[1] = "D1"; lt[2] = "D2"; lt[3] = "D3_5"; lt[4] = "D6_10";
    lts[0] = "+LAT=0"; lts[1] = "+LAT=1"; lts[2] = "+LAT=2"; lts[3] = "+LAT=5"; lts[4] = "+LAT=10";
    bp[0] = "+N=200"; bp[1] = "+N=200"; bp[2] = "+N=200"; bp[3] = "+N=200 +SEED=99"; bp[4] = "+N=400 +SEED=3";

    add("OP_WR", "default traffic");
    add("OP_RD", "default traffic");
    foreach (rg[i]) add({"WR_RGN_", rg[i]}, "directed_boundary, +N=200");
    foreach (rg[i]) add({"RD_RGN_", rg[i]}, "directed_boundary, +N=200");
    add("WR_RSP_OKAY",   "default traffic");
    add("WR_RSP_SLVERR", "directed_boundary writes OOR");
    add("RD_RSP_OKAY",   "default traffic");
    add("RD_RSP_SLVERR", "directed_boundary reads OOR");
    add("WR_STRB_NONE",   "directed_strobe, +N=200");
    add("WR_STRB_FULL",   "default traffic");
    add("WR_STRB_SINGLE", "directed_strobe");
    add("WR_STRB_MULTI",  "directed_strobe, +N=200");
    foreach (lt[i]) add({"WR_LAT_", lt[i]}, lts[i]);
    foreach (lt[i]) add({"RD_LAT_", lt[i]}, lts[i]);
    foreach (lt[i]) add({"WR_BP_",  lt[i]}, bp[i]);
    foreach (lt[i]) add({"RD_BP_",  lt[i]}, bp[i]);
    add("WR_ORD_AWFIRST", "directed_basic (w_dly > aw_dly case)");
    add("WR_ORD_WFIRST",  "directed_basic (aw_dly > w_dly case)");
    add("WR_ORD_SAME",    "directed_basic (same-cycle case)");
    add("RD_RAW",         "directed_raw_waw");
    add("WR_WAW",         "directed_raw_waw");
    add("ANY_REPEAT_ADDR","directed_raw_waw, +N=200");
    add("RST_OBSERVED",   "needs reset test: t_reset_recovery (Stage 9)");
    tot = gname.size();
  endfunction

  task run();
    obs_txn o;
    forever begin
      mon2cov.get(o);
      if (o.kind != OBS_RESPONSE) sample_reqstall(o);
      else if (!o.unexpected) sample(o);
    end
  endtask

  function automatic int req_stall_bin(input int unsigned cycles);
    if (cycles == 0) return 0;
    if (cycles == 1) return 1;
    if (cycles <= 3) return 2;
    if (cycles <= 10) return 3;
    if (cycles <= 200) return 4;
    return -1;
  endfunction

  function void sample_reqstall(obs_txn o);
    int ch, b;
    ch = -1;
    case (o.kind)
      OBS_AW_ACCEPT: begin
        ch = 0; v_req_stall_cycles = int'(o.req_stall_cycles);
        last_aw_stall_cycles = o.req_stall_cycles; cg_reqstall_aw.sample();
      end
      OBS_W_ACCEPT: begin
        ch = 1; v_req_stall_cycles = int'(o.req_stall_cycles);
        last_w_stall_cycles = o.req_stall_cycles; cg_reqstall_w.sample();
      end
      OBS_AR_ACCEPT: begin
        ch = 2; v_req_stall_cycles = int'(o.req_stall_cycles);
        last_ar_stall_cycles = o.req_stall_cycles; cg_reqstall_ar.sample();
      end
      default: return;
    endcase
    req_stall_samples[ch]++;
    b = req_stall_bin(o.req_stall_cycles);
    if (b >= 0) req_stall_bin_hits[ch][b]++;
    else req_stall_unbinned[ch]++;
  endfunction

  function string req_stall_name(int b);
    case (b)
      0: return "zero";
      1: return "one";
      2: return "two_three";
      3: return "four_ten";
      default: return "eleven_plus";
    endcase
  endfunction

  function void report_req_stall();
    real covpct [0:2];
    covpct[0] = cg_reqstall_aw.get_inst_coverage();
    covpct[1] = cg_reqstall_w.get_inst_coverage();
    covpct[2] = cg_reqstall_ar.get_inst_coverage();
    $display("COV_REQSTALL boundary=master_visible AW=%0.2f samples=%0d W=%0.2f samples=%0d AR=%0.2f samples=%0d",
             covpct[0], req_stall_samples[0], covpct[1], req_stall_samples[1],
             covpct[2], req_stall_samples[2]);
    for (int ch = 0; ch < 3; ch++) begin
      for (int b = 0; b < 5; b++)
        $display("COV_REQSTALL_BIN channel=%s name=%s hits=%0d status=%s",
                 (ch == 0) ? "AW" : ((ch == 1) ? "W" : "AR"), req_stall_name(b),
                 req_stall_bin_hits[ch][b],
                 (req_stall_bin_hits[ch][b] != 0) ? "HIT" : "UNCOVERED");
      if (req_stall_unbinned[ch] != 0)
        $display("COV_REQSTALL_UNBINNED channel=%s accepted=%0d (outside 0..200)",
                 (ch == 0) ? "AW" : ((ch == 1) ? "W" : "AR"), req_stall_unbinned[ch]);
    end
  endfunction

  function void sample(obs_txn o);
    int unsigned wi;
    int          rgn;
    string       p;
    wi = o.addr >> 2;
    if      (wi >= depth)          rgn = 5;
    else if (wi == 0)              rgn = 0;
    else if (wi == depth - 1)      rgn = 4;
    else if (wi < depth / 3)       rgn = 1;
    else if (wi < (2 * depth) / 3) rgn = 2;
    else                           rgn = 3;

    v_rgn = rgn;
    v_rsp = int'(o.rsp);
    v_bp  = int'(o.c_rsp - o.c_vld) - 1;
    v_rep = (have_prev && (o.addr == prev_addr)) ? 1 : 0;

    p = (o.op == OP_WRITE) ? "WR_" : "RD_";
    hit({p, "RGN_", rgn_name(rgn)});
    if      (o.rsp == 2'b00) hit({p, "RSP_OKAY"});
    else if (o.rsp == 2'b10) hit({p, "RSP_SLVERR"});
    hit({p, "BP_", bin5(v_bp)});

    if (o.op == OP_WRITE) begin
      hit("OP_WR");
      v_lat  = int'(o.c_vld - o.c_req) - wr_base;
      hit({"WR_LAT_", bin5(v_lat)});
      v_strb = int'(o.strb);
      if      (o.strb == 4'h0) hit("WR_STRB_NONE");
      else if (o.strb == 4'hF) hit("WR_STRB_FULL");
      else if (o.strb == 4'h1 || o.strb == 4'h2 || o.strb == 4'h4 || o.strb == 4'h8)
                               hit("WR_STRB_SINGLE");
      else                     hit("WR_STRB_MULTI");
      if      (o.c_aw < o.c_w) begin v_ord = 0; hit("WR_ORD_AWFIRST"); end
      else if (o.c_aw > o.c_w) begin v_ord = 1; hit("WR_ORD_WFIRST");  end
      else                     begin v_ord = 2; hit("WR_ORD_SAME");    end
      if (wrote.exists(o.addr)) hit("WR_WAW");
      if (o.rsp == 2'b00) wrote[o.addr] = 1'b1;
      cg_wr.sample();
      v_aww_skew_class = classify_aww_skew(o.c_aw, o.c_w, last_aww_separation);
      last_aw_cycle = o.c_aw;
      last_w_cycle = o.c_w;
      cg_aww_skew.sample();
      aww_skew_samples++;
      aww_skew_bin_hits[v_aww_skew_class]++;
    end else begin
      hit("OP_RD");
      v_lat = int'(o.c_vld - o.c_req) - rd_base;
      hit({"RD_LAT_", bin5(v_lat)});
      v_raw = wrote.exists(o.addr) ? 1 : 0;
      if (v_raw) hit("RD_RAW");
      cg_rd.sample();
    end
    if (v_rep) hit("ANY_REPEAT_ADDR");
    have_prev = 1'b1;
    prev_addr = o.addr;
  endfunction

  // legal-run report. prior = mask printed by an earlier run (+PRIOR=<hex>)
  function void report(bit [63:0] prior, int unsigned reset_n);
    bit [63:0] m;
    if (reset_n > 0) hit("RST_OBSERVED");
    run_hit = 0; cum_hit = 0; m = 64'h0;
    foreach (ghit[i]) begin
      if (ghit[i]) run_hit++;
      if (ghit[i] || prior[i]) begin cum_hit++; m[i] = 1'b1; end
    end
    $display("COV goals total=%0d | this run hit=%0d (%0.1f%%) | cumulative hit=%0d (%0.1f%%) remaining=%0d",
             tot, run_hit, 100.0 * run_hit / tot, cum_hit, 100.0 * cum_hit / tot, tot - cum_hit);
    $display("COV native cg_wr=%0.2f cg_rd=%0.2f (this run only, incl. crosses)",
             cg_wr.get_inst_coverage(), cg_rd.get_inst_coverage());
    report_aww_skew();
    report_req_stall();
    foreach (gname[i])
      if (!(ghit[i] || prior[i]))
        $display("COVGAP %s -> try: %s", gname[i], gtest[i]);
    $display("COVMASK=%h", m);
  endfunction

  // negative coverage: violation categories seen. Separate from legal goals.
  function void neg_report();
    int    n;
    string miss;
    n = 0; miss = "";
    for (int i = 0; i < NUM_VCAT; i++) begin
      if (viol_mon::cnt[i] > 0) begin
        n++; v_cat = i; cg_neg.sample();
      end else begin
        miss = {miss, " ", viol_mon::cname(vcat_e'(i))};
      end
    end
    $display("NEGCOV categories hit=%0d/%0d native=%0.2f", n, NUM_VCAT, cg_neg.get_inst_coverage());
    $display("NEGGAP uncovered:%s", miss);
  endfunction
endclass
`endif
