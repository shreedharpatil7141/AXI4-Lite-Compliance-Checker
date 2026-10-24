`ifndef AXI_SCOREBOARD_SV
`define AXI_SCOREBOARD_SV
class ref_model;
  virtual function bit [1:0] do_write(bit [31:0] addr, bit [31:0] data, bit [3:0] strb);
    return 2'b00;
  endfunction
  virtual function void do_read(bit [31:0] addr, output bit [31:0] data, output bit [1:0] rsp);
    data = 32'h0; rsp = 2'b00;
  endfunction
endclass

class ram_model extends ref_model;
  bit [31:0]   mem [];
  int unsigned depth;
  bit          ignore_strb;

  function new(int unsigned depth);
    this.depth = depth;
    ignore_strb = 1'b0;
    mem = new[depth];
    foreach (mem[i]) mem[i] = 32'h0;
  endfunction

  function bit in_range(bit [31:0] a);
    return ((a >> 2) < depth);
  endfunction

  virtual function bit [1:0] do_write(bit [31:0] addr, bit [31:0] data, bit [3:0] strb);
    int unsigned wi;
    if (!in_range(addr)) return 2'b10;
    wi = addr >> 2;
    for (int b = 0; b < 4; b++)
      if (strb[b] || ignore_strb) mem[wi][8*b +: 8] = data[8*b +: 8];
    return 2'b00;
  endfunction

  virtual function void do_read(bit [31:0] addr, output bit [31:0] data, output bit [1:0] rsp);
    int unsigned wi;
    if (!in_range(addr)) begin
      data = 32'h0; rsp = 2'b10;
    end else begin
      wi = addr >> 2;
      data = mem[wi]; rsp = 2'b00;
    end
  endfunction
endclass

class scoreboard;
  mailbox #(obs_txn) mon2scb;
  ref_model          rm;

  int unsigned n_wr, n_rd, n_unexp, n_data_mis, n_resp_mis, n_acct, n_pend, n_order, n_drv_to;

  longint      lmin [2][3];
  longint      lmax [2][3];
  longint      lsum [2][3];
  longint      lcnt [2];

  function new(mailbox #(obs_txn) m, ref_model rm);
    this.mon2scb = m;
    this.rm      = rm;
    n_wr = 0; n_rd = 0; n_unexp = 0; n_data_mis = 0; n_resp_mis = 0;
    n_acct = 0; n_pend = 0; n_order = 0; n_drv_to = 0;
    for (int k = 0; k < 2; k++) begin
      lcnt[k] = 0;
      for (int m2 = 0; m2 < 3; m2++) begin
        lmin[k][m2] = 1000000; lmax[k][m2] = 0; lsum[k][m2] = 0;
      end
    end
  endfunction

  function void rec_lat(int k, obs_txn o);
    longint d [3];
    d[0] = o.c_vld - o.c_req;
    d[1] = o.c_rsp - o.c_vld;
    d[2] = o.c_rsp - o.c_req;
    if (d[0] < 0 || d[1] < 0) begin
      n_order++;
      void'(viol_mon::report(V_ACCOUNTING, (k == 0) ? "B" : "R", $time,
            {"latency order: ", o.convert2string()}, 1'b0));
      return;
    end
    lcnt[k]++;
    for (int m2 = 0; m2 < 3; m2++) begin
      if (d[m2] < lmin[k][m2]) lmin[k][m2] = d[m2];
      if (d[m2] > lmax[k][m2]) lmax[k][m2] = d[m2];
      lsum[k][m2] += d[m2];
    end
  endfunction

  function void check_write(obs_txn o);
    bit [1:0] er;
    er = rm.do_write(o.addr, o.data, o.strb);
    n_wr++;
    if (o.rsp !== er) begin
      n_resp_mis++;
      void'(viol_mon::report(V_RESP_CODE_MISMATCH, "B", o.t_rsp,
            $sformatf("addr=%h resp exp=%0b got=%0b", o.addr, er, o.rsp), 1'b0));
    end
    rec_lat(0, o);
  endfunction

  function void check_read(obs_txn o);
    bit [31:0] ed;
    bit [1:0]  er;
    rm.do_read(o.addr, ed, er);
    n_rd++;
    if (o.rsp !== er) begin
      n_resp_mis++;
      void'(viol_mon::report(V_RESP_CODE_MISMATCH, "R", o.t_rsp,
            $sformatf("addr=%h resp exp=%0b got=%0b", o.addr, er, o.rsp), 1'b0));
    end
    if (o.data !== ed) begin
      n_data_mis++;
      void'(viol_mon::report(V_DATA_MISMATCH, "R", o.t_rsp,
            $sformatf("addr=%h data exp=%h got=%h", o.addr, ed, o.data), 1'b0));
    end
    rec_lat(1, o);
  endfunction

  task run();
    obs_txn o;
    forever begin
      mon2scb.get(o);
      if (o.unexpected) begin
        n_unexp++;
        void'(viol_mon::report(V_UNEXPECTED_RESP, (o.op == OP_WRITE) ? "B" : "R", o.t_rsp,
              o.convert2string(), 1'b0));
      end else if (o.op == OP_WRITE) check_write(o);
      else                           check_read(o);
    end
  endtask

  // pend_w : complete writes (AW and W accepted) without response
  // pend_r : accepted reads without response
  // inc_w  : write requests with only one of AW/W accepted (reported as accounting, not missing response)
  function void final_check(int unsigned drv_done, int unsigned drv_to,
                            int unsigned pend_w, int unsigned pend_r,
                            int unsigned inc_w = 0);
    n_drv_to = drv_to;
    if (inc_w != 0) begin
      n_acct++;
      void'(viol_mon::report(V_ACCOUNTING, "AW/W", $time,
            $sformatf("incomplete write request: only one of AW/W accepted (items=%0d)", inc_w), 1'b0));
    end
    if ((n_wr + n_rd) != drv_done) begin
      n_acct++;
      void'(viol_mon::report(V_ACCOUNTING, "-", $time,
            $sformatf("monitor_completed=%0d driver_completed=%0d", n_wr + n_rd, drv_done), 1'b0));
    end
    n_pend += pend_w + pend_r;
    for (int i = 0; i < (pend_w + pend_r); i++)
      void'(viol_mon::report(V_MISSING_RESP, $sformatf("REQ%0d", i), $time,
            $sformatf("accepted request without response (wr_txn=%0d rd_txn=%0d)", pend_w, pend_r), 1'b0));
    for (int i = 0; i < drv_to; i++)
      void'(viol_mon::report(V_RESP_TIMEOUT, $sformatf("DRV%0d", i), $time,
            "driver bounded wait expired", 1'b0));
  endfunction

  function int unsigned errors();
    return n_unexp + n_data_mis + n_resp_mis + n_acct + n_pend + n_order + n_drv_to;
  endfunction

  function string lat_str(int k, int m);
    if (lcnt[k] == 0) return "n/a";
    return $sformatf("%0d/%0.2f/%0d", lmin[k][m], real'(lsum[k][m]) / real'(lcnt[k]), lmax[k][m]);
  endfunction

  function void report();
    $display("SCB wr=%0d rd=%0d unexp=%0d data_mis=%0d resp_mis=%0d acct=%0d pend=%0d order=%0d drv_to=%0d",
             n_wr, n_rd, n_unexp, n_data_mis, n_resp_mis, n_acct, n_pend, n_order, n_drv_to);
    $display("LAT write min/avg/max  L1=%s  L2=%s  L3=%s", lat_str(0,0), lat_str(0,1), lat_str(0,2));
    $display("LAT read  min/avg/max  L1=%s  L2=%s  L3=%s", lat_str(1,0), lat_str(1,1), lat_str(1,2));
  endfunction
endclass
`endif