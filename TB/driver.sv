`ifndef AXI_DRIVER_SV
`define AXI_DRIVER_SV
class driver;
  virtual axi4l_if       vif;
  mailbox #(transaction) gen2drv;
  mailbox #(transaction) drv2done;
  int unsigned           timeout_cycles = 200;
  int unsigned           sent, completed, timeouts, finished, aborted;
  int unsigned           flt_aw_chg;       // verification fault: change AWADDR once while stalled
  bit                    aw_ok, w_ok;
  bit                    rst_seen, abort_flag;

  function new(virtual axi4l_if vif,
               mailbox #(transaction) g2d,
               mailbox #(transaction) done);
    this.vif      = vif;
    this.gen2drv  = g2d;
    this.drv2done = done;
    sent = 0; completed = 0; timeouts = 0; finished = 0; aborted = 0;
    flt_aw_chg = 0;
    rst_seen = 0; abort_flag = 0;
  endfunction

  function void reset_bus();
    vif.AWADDR  <= '0; vif.AWVALID <= 1'b0;
    vif.WDATA   <= '0; vif.WSTRB   <= '0; vif.WVALID <= 1'b0;
    vif.BREADY  <= 1'b0;
    vif.ARADDR  <= '0; vif.ARVALID <= 1'b0;
    vif.RREADY  <= 1'b0;
  endfunction

  task dly(int unsigned n);
    repeat (n) begin
      @(posedge vif.ACLK);
      if (vif.ARESETN !== 1'b1) rst_seen = 1'b1;
    end
  endtask

  task drive_aw(transaction t);
    int unsigned n = 0;
    aw_ok = 1'b0;
    repeat (t.aw_dly) @(posedge vif.ACLK);
    vif.AWADDR  <= t.addr;
    vif.AWVALID <= 1'b1;
    do begin
      @(posedge vif.ACLK);
      n++;
       if (flt_aw_chg > 0 && n == 2 && !vif.AWREADY) begin
        vif.AWADDR <= t.addr ^ 32'h4;
        flt_aw_chg--;
      end
      if (vif.AWREADY) aw_ok = 1'b1;
    end while (!aw_ok && n < timeout_cycles);
    vif.AWVALID <= 1'b0;
  endtask

  task drive_w(transaction t);
    int unsigned n = 0;
    w_ok = 1'b0;
    repeat (t.w_dly) @(posedge vif.ACLK);
    vif.WDATA  <= t.data;
    vif.WSTRB  <= t.strb;
    vif.WVALID <= 1'b1;
    do begin
      @(posedge vif.ACLK);
      n++;
      if (vif.WREADY) w_ok = 1'b1;
    end while (!w_ok && n < timeout_cycles);
    vif.WVALID <= 1'b0;
  endtask

  task wait_b(transaction t);
    int unsigned n = 0;
    bit got = 1'b0;
    vif.BREADY <= 1'b0;
    while (!got && n < timeout_cycles) begin
      @(posedge vif.ACLK);
      n++;
      if (vif.ARESETN !== 1'b1) rst_seen = 1'b1;
      if (vif.BVALID) got = 1'b1;
    end
    if (!got) begin
      if (rst_seen) abort_flag = 1'b1; else t.timed_out = 1'b1;
      return;
    end
    dly(t.bready_dly);
    vif.BREADY <= 1'b1;
    @(posedge vif.ACLK);
    t.rsp = vif.BRESP;
    if (!vif.BVALID) begin
      if (rst_seen) abort_flag = 1'b1; else t.timed_out = 1'b1;
    end
    vif.BREADY <= 1'b0;
  endtask

  task wait_r(transaction t);
    int unsigned n = 0;
    bit got = 1'b0;
    vif.RREADY <= 1'b0;
    while (!got && n < timeout_cycles) begin
      @(posedge vif.ACLK);
      n++;
      if (vif.ARESETN !== 1'b1) rst_seen = 1'b1;
      if (vif.RVALID) got = 1'b1;
    end
    if (!got) begin
      if (rst_seen) abort_flag = 1'b1; else t.timed_out = 1'b1;
      return;
    end
    dly(t.rready_dly);
    vif.RREADY <= 1'b1;
    @(posedge vif.ACLK);
    t.rsp   = vif.RRESP;
    t.rdata = vif.RDATA;
    if (rst_seen)
      abort_flag = 1'b1;
    else if (!vif.RVALID)
      t.timed_out = 1'b1;
    vif.RREADY <= 1'b0;
  endtask

  task drive_write(transaction t);
    fork
      drive_aw(t);
      drive_w(t);
    join
    if (!aw_ok || !w_ok) t.timed_out = 1'b1;
    else                 wait_b(t);
  endtask

  task drive_read(transaction t);
    int unsigned n = 0;
    bit ok = 1'b0;
    repeat (t.ar_dly) @(posedge vif.ACLK);
    vif.ARADDR  <= t.addr;
    vif.ARVALID <= 1'b1;
    do begin
      @(posedge vif.ACLK);
      n++;
      if (vif.ARREADY) ok = 1'b1;
    end while (!ok && n < timeout_cycles);
    vif.ARVALID <= 1'b0;
    if (!ok) t.timed_out = 1'b1;
    else     wait_r(t);
  endtask

  // Directed capacity probe used by mutant 17. Keep all pin changes in the
  // driver and sample READY on clock edges, like ordinary transactions.
  task probe_second_aw(input bit [31:0] a1, input bit [31:0] a2,
                       input bit [31:0] data1, input bit [31:0] data2,
                       output bit probe_ok, output bit accepted_while_pending,
                       output string failure);
    int unsigned n;
    bit accepted;
    begin : probe_body
    probe_ok = 1'b0;
    accepted_while_pending = 1'b0;
    failure = "";
    vif.BREADY <= 1'b0; vif.WVALID <= 1'b0;
    vif.AWADDR <= a1; vif.AWVALID <= 1'b1;
    accepted = 1'b0;
    for (n = 0; n < timeout_cycles && !accepted; n++) begin
      @(posedge vif.ACLK);
      if (vif.AWREADY === 1'b1) accepted = 1'b1;
    end
    if (!accepted) begin failure = "AW1 timeout"; disable probe_body; end
    vif.AWVALID <= 1'b0;

    // Keep the first write incomplete while presenting the second address.
    vif.AWADDR <= a2; vif.AWVALID <= 1'b1;
    for (n = 0; n < 3; n++) begin
      @(posedge vif.ACLK);
      if (vif.AWVALID && vif.AWREADY) begin
        accepted_while_pending = 1'b1;
        vif.AWVALID <= 1'b0;
      end
    end

    vif.WDATA <= data1; vif.WSTRB <= 4'hF; vif.WVALID <= 1'b1;
    accepted = 1'b0;
    for (n = 0; n < timeout_cycles && !accepted; n++) begin
      @(posedge vif.ACLK);
      if (vif.WREADY === 1'b1) accepted = 1'b1;
    end
    if (!accepted) begin failure = "W1 timeout"; disable probe_body; end
    vif.WVALID <= 1'b0;
    accepted = 1'b0;
    for (n = 0; n < timeout_cycles && !accepted; n++) begin
      @(posedge vif.ACLK);
      if (vif.BVALID === 1'b1) accepted = 1'b1;
    end
    if (!accepted) begin failure = "B1 timeout"; disable probe_body; end
    vif.BREADY <= 1'b1;
    @(posedge vif.ACLK);
    if (vif.BVALID !== 1'b1) begin failure = "B1 handshake lost"; disable probe_body; end
    vif.BREADY <= 1'b0;

    if (!accepted_while_pending) begin
      // Golden single-entry DUT releases AWREADY only after the first B
      // handshake. The held second AW completes as a normal second write.
      accepted = 1'b0;
      for (n = 0; n < timeout_cycles && !accepted; n++) begin
        @(posedge vif.ACLK);
        if (vif.AWREADY === 1'b1) accepted = 1'b1;
      end
      if (!accepted) begin failure = "AW2 completion timeout"; disable probe_body; end
      vif.AWVALID <= 1'b0;
      vif.WDATA <= data2; vif.WSTRB <= 4'hF; vif.WVALID <= 1'b1;
      accepted = 1'b0;
      for (n = 0; n < timeout_cycles && !accepted; n++) begin
        @(posedge vif.ACLK);
        if (vif.WREADY === 1'b1) accepted = 1'b1;
      end
      if (!accepted) begin failure = "W2 timeout"; disable probe_body; end
      vif.WVALID <= 1'b0;
      accepted = 1'b0;
      for (n = 0; n < timeout_cycles && !accepted; n++) begin
        @(posedge vif.ACLK);
        if (vif.BVALID === 1'b1) accepted = 1'b1;
      end
      if (!accepted) begin failure = "B2 timeout"; disable probe_body; end
      vif.BREADY <= 1'b1; @(posedge vif.ACLK);
      if (vif.BVALID !== 1'b1) begin failure = "B2 handshake lost"; disable probe_body; end
      vif.BREADY <= 1'b0;
    end else begin
      // Mutant already consumed AW2. A second W is harmlessly accepted as a
      // partial request, then the test resets to flush the DUT and monitor.
      vif.WDATA <= data2; vif.WSTRB <= 4'hF; vif.WVALID <= 1'b1;
      accepted = 1'b0;
      for (n = 0; n < timeout_cycles && !accepted; n++) begin
        @(posedge vif.ACLK);
        if (vif.WREADY === 1'b1) accepted = 1'b1;
      end
      if (!accepted) begin failure = "W2 partial timeout"; disable probe_body; end
      vif.WVALID <= 1'b0;
    end
    probe_ok = 1'b1;
    end
    vif.AWVALID <= 1'b0; vif.WVALID <= 1'b0; vif.BREADY <= 1'b0;
  endtask

  task run();
    transaction t;
    @(posedge vif.ACLK);   // align to clock edge before first drive. KEEP.
    forever begin
      gen2drv.get(t);
      sent++;
      abort_flag = 1'b0;
      rst_seen   = 1'b0;
      if (t.op == OP_WRITE) drive_write(t);
      else                  drive_read(t);
      if (abort_flag) begin
        aborted++;
      end else if (t.timed_out) begin
        timeouts++;
        $display("DRV TIMEOUT t=%0t aw_ok=%0b w_ok=%0b AWV=%b AWR=%b WV=%b WR=%b BV=%b BR=%b ARESETN=%b | %s",
                 $time, aw_ok, w_ok, vif.AWVALID, vif.AWREADY, vif.WVALID, vif.WREADY,
                 vif.BVALID, vif.BREADY, vif.ARESETN, t.convert2string());
      end else begin
        t.done = 1'b1;
        completed++;
      end
      finished++;
      drv2done.put(t);
      repeat (t.gap) @(posedge vif.ACLK);
    end
  endtask
endclass
`endif