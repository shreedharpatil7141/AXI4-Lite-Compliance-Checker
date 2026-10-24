`ifndef AXI_ENV_SV
`define AXI_ENV_SV
// scoreboard with per-test stat reset, accounting-fault hook, late-response check
class scoreboard2 extends scoreboard;
  int unsigned skip_rd;   // verification fault: skip checking next N reads

  function new(mailbox #(obs_txn) m, ref_model rm);
    super.new(m, rm);
    skip_rd = 0;
  endfunction

  function void clear_stats();
    n_wr = 0; n_rd = 0; n_unexp = 0; n_data_mis = 0; n_resp_mis = 0;
    n_acct = 0; n_pend = 0; n_order = 0; n_drv_to = 0;
    for (int k = 0; k < 2; k++) begin
      lcnt[k] = 0;
      for (int j = 0; j < 3; j++) begin
        lmin[k][j] = 1000000; lmax[k][j] = 0; lsum[k][j] = 0;
      end
    end
  endfunction

  // hides base run() when called through a scoreboard2 handle
  task run();
    obs_txn o;
    forever begin
      mon2scb.get(o);
      if (o.unexpected) begin
        n_unexp++;
        void'(viol_mon::report(V_UNEXPECTED_RESP, (o.op == OP_WRITE) ? "B" : "R", o.t_rsp,
              o.convert2string(), 1'b0));
      end else if (o.op == OP_WRITE) begin
        check_write(o);
      end else if (skip_rd > 0) begin
        skip_rd--;
      end else begin
        check_read(o);
      end
    end
  endtask

  // timeout = response arrived but accept-to-VALID (L1) above limit
  function void limit_check(int lim);
    for (int k = 0; k < 2; k++)
      if (lcnt[k] > 0 && lmax[k][0] > lim)
        void'(viol_mon::report(V_RESP_TIMEOUT, (k == 0) ? "B" : "R", $time,
              $sformatf("L1 max=%0d exceeds limit %0d", lmax[k][0], lim), 1'b0));
  endfunction
endclass

// DUT-side latency probe: reads obs_txn from a monitor attached to dbus (DUT-facing bus).
// [0]=write [1]=read ; metric [0]=L1 [1]=L2 [2]=L3. Same definitions as scoreboard.
class lat_probe;
  mailbox #(obs_txn) mb;
  longint lmin [2][3];
  longint lmax [2][3];
  longint lsum [2][3];
  longint lcnt [2];

  function new(mailbox #(obs_txn) m);
    mb = m;
    clear();
  endfunction

  function void clear();
    for (int k = 0; k < 2; k++) begin
      lcnt[k] = 0;
      for (int j = 0; j < 3; j++) begin
        lmin[k][j] = 1000000; lmax[k][j] = 0; lsum[k][j] = 0;
      end
    end
  endfunction

  task run();
    obs_txn o;
    longint d [3];
    int     k;
    forever begin
      mb.get(o);
      if (!o.unexpected) begin
        k = (o.op == OP_WRITE) ? 0 : 1;
        d[0] = o.c_vld - o.c_req;
        d[1] = o.c_rsp - o.c_vld;
        d[2] = o.c_rsp - o.c_req;
        if (d[0] >= 0 && d[1] >= 0) begin
          lcnt[k]++;
          for (int j = 0; j < 3; j++) begin
            if (d[j] < lmin[k][j]) lmin[k][j] = d[j];
            if (d[j] > lmax[k][j]) lmax[k][j] = d[j];
            lsum[k][j] += d[j];
          end
        end
      end
    end
  endtask

  function string str(int k, int m);
    if (lcnt[k] == 0) return "n/a";
    return $sformatf("%0d/%0.2f/%0d", lmin[k][m], real'(lsum[k][m]) / real'(lcnt[k]), lmax[k][m]);
  endfunction
endclass

class environment;
  mailbox #(transaction) g2d;
  mailbox #(transaction) d2c;
  mailbox #(obs_txn)     m2s;
  mailbox #(obs_txn)     m2c;

  driver        drv;
  monitor       mon;
  scoreboard2   scb;
  ref_model     rmod;
  cov_collector cov;

  int unsigned checked;
  bit [31:0]   sig;

  function new(virtual axi4l_if vif, int unsigned depth,
               int wr_base, int rd_base, ref_model rm);
    g2d = new();
    d2c = new();
    m2s = new();
    m2c = new();
    drv  = new(vif, g2d, d2c);
    rmod = rm;
    mon  = new(vif, m2s);
    mon.mon2cov = m2c;
    scb  = new(m2s, rmod);
    cov  = new(m2c, depth, wr_base, rd_base);
    checked = 0;
    sig = 0;
  endfunction

  task drain_loop();
    transaction t;
    forever begin
      d2c.get(t);
      checked++;
      sig = {sig[30:0], sig[31]} ^ t.addr ^ t.data ^ {28'b0, t.strb} ^ t.id;
    end
  endtask

  task start();
    drv.reset_bus();
    fork
      mon.run();
      scb.run();
      cov.run();
      drv.run();
      drain_loop();
    join_none
  endtask

  task wait_done(int unsigned target);
    wait (checked >= target);
  endtask

  function int unsigned goals_hit();
    int unsigned n;
    n = 0;
    foreach (cov.ghit[i]) if (cov.ghit[i]) n++;
    return n;
  endfunction
endclass
`endif