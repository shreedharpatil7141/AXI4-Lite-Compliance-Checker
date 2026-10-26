`ifndef AXI_MONITOR_SV
`define AXI_MONITOR_SV
typedef enum bit [1:0] {OBS_RESPONSE, OBS_AW_ACCEPT, OBS_W_ACCEPT, OBS_AR_ACCEPT} obs_kind_e;

class obs_txn;
  obs_kind_e kind;
  op_e       op;
  bit [31:0] addr;
  bit [31:0] data;        // write data, or read data
  bit [3:0]  strb;
  bit [1:0]  rsp;
  bit        unexpected;  // response with no accepted request
  longint    c_aw;        // cycle of AW handshake (writes)
  longint    c_w;         // cycle of W handshake (writes)
  longint    c_req;       // cycle of last request handshake
  longint    c_vld;       // cycle of first response VALID
  longint    c_rsp;       // cycle of response handshake
  time       t_rsp;
  int unsigned req_stall_cycles; // master-visible VALID && !READY samples
  int unsigned aw_stall_cycles, w_stall_cycles, ar_stall_cycles;

  function string convert2string();
    return $sformatf("%s addr=%h data=%h strb=%b rsp=%0b unexp=%0b req=%0d vld=%0d rsp_c=%0d",
                     (op == OP_WRITE) ? "WR" : "RD", addr, data, strb, rsp, unexpected,
                     c_req, c_vld, c_rsp);
  endfunction
endclass

class monitor;
  virtual axi4l_if   vif;
  mailbox #(obs_txn) mon2scb;
  mailbox #(obs_txn) mon2cov;   // optional, null = off
  longint            cycle;

  bit [31:0] aw_q[$];  longint aw_c[$];
  int unsigned aw_stall_q[$];
  bit [31:0] w_d[$];   bit [3:0] w_s[$];  longint w_c[$];
  int unsigned w_stall_q[$];
  bit [31:0] ar_q[$];  longint ar_c[$];
  int unsigned ar_stall_q[$];
  int unsigned aw_stall_active, w_stall_active, ar_stall_active;

  bit     b_seen, r_seen;
  longint b_vld_c, r_vld_c;

  int unsigned n_aw, n_w, n_b, n_ar, n_r, n_unexp, n_reset;

  function new(virtual axi4l_if vif, mailbox #(obs_txn) m);
    this.vif     = vif;
    this.mon2scb = m;
    this.mon2cov = null;
    cycle = 0;
    n_aw = 0; n_w = 0; n_b = 0; n_ar = 0; n_r = 0; n_unexp = 0; n_reset = 0;
    b_seen = 0; r_seen = 0; b_vld_c = 0; r_vld_c = 0;
    aw_stall_active = 0; w_stall_active = 0; ar_stall_active = 0;
  endfunction

  // complete writes (AW and W both accepted) still waiting for a response
  function int unsigned pend_wr();
    return (aw_q.size() < w_d.size()) ? aw_q.size() : w_d.size();
  endfunction

  // write requests with only one of AW/W accepted (incomplete request)
  function int unsigned inc_wr();
    return (aw_q.size() > w_d.size()) ? (aw_q.size() - w_d.size())
                                      : (w_d.size() - aw_q.size());
  endfunction

  function int unsigned pend_rd();
    return ar_q.size();
  endfunction

  function void flush();
    aw_q.delete(); aw_c.delete(); aw_stall_q.delete();
    w_d.delete();  w_s.delete(); w_c.delete(); w_stall_q.delete();
    ar_q.delete(); ar_c.delete(); ar_stall_q.delete();
    aw_stall_active = 0; w_stall_active = 0; ar_stall_active = 0;
    b_seen = 0; r_seen = 0;
  endfunction

  task run();
    obs_txn o;
    bit     was_up = 1'b0;
    forever begin
      @(posedge vif.ACLK);      // pre-edge values: DUT and driver use NBA
      cycle++;
      if (vif.ARESETN !== 1'b1) begin
        if (was_up) n_reset++;
        was_up = 1'b0;
        flush();
      end else begin
        was_up = 1'b1;

        // request channels
        if (vif.AWVALID === 1'b1) begin
          if (vif.AWREADY === 1'b0) aw_stall_active++;
          else if (vif.AWREADY === 1'b1) begin
            aw_q.push_back(vif.AWADDR); aw_c.push_back(cycle); n_aw++;
            aw_stall_q.push_back(aw_stall_active);
            if (mon2cov != null) begin
              o = new(); o.kind = OBS_AW_ACCEPT; o.req_stall_cycles = aw_stall_active;
              mon2cov.put(o);
            end
            aw_stall_active = 0;
          end
        end else if (vif.AWVALID === 1'b0) aw_stall_active = 0;

        if (vif.WVALID === 1'b1) begin
          if (vif.WREADY === 1'b0) w_stall_active++;
          else if (vif.WREADY === 1'b1) begin
            w_d.push_back(vif.WDATA); w_s.push_back(vif.WSTRB); w_c.push_back(cycle); n_w++;
            w_stall_q.push_back(w_stall_active);
            if (mon2cov != null) begin
              o = new(); o.kind = OBS_W_ACCEPT; o.req_stall_cycles = w_stall_active;
              mon2cov.put(o);
            end
            w_stall_active = 0;
          end
        end else if (vif.WVALID === 1'b0) w_stall_active = 0;

        if (vif.ARVALID === 1'b1) begin
          if (vif.ARREADY === 1'b0) ar_stall_active++;
          else if (vif.ARREADY === 1'b1) begin
            ar_q.push_back(vif.ARADDR); ar_c.push_back(cycle); n_ar++;
            ar_stall_q.push_back(ar_stall_active);
            if (mon2cov != null) begin
              o = new(); o.kind = OBS_AR_ACCEPT; o.req_stall_cycles = ar_stall_active;
              mon2cov.put(o);
            end
            ar_stall_active = 0;
          end
        end else if (vif.ARVALID === 1'b0) ar_stall_active = 0;

        // first response VALID
        if (vif.BVALID === 1'b1 && !b_seen) begin b_seen = 1'b1; b_vld_c = cycle; end
        else if (vif.BVALID === 1'b0) b_seen = 1'b0;
        if (vif.RVALID === 1'b1 && !r_seen) begin r_seen = 1'b1; r_vld_c = cycle; end
        else if (vif.RVALID === 1'b0) r_seen = 1'b0;

        // write response handshake
        if (vif.BVALID === 1'b1 && vif.BREADY === 1'b1) begin
          longint ca, cw;
          o = new();
          o.kind = OBS_RESPONSE; o.op = OP_WRITE; o.rsp = vif.BRESP; o.c_vld = b_vld_c; o.c_rsp = cycle; o.t_rsp = $time;
          if (aw_q.size() > 0 && w_d.size() > 0) begin
            o.addr = aw_q.pop_front();  ca = aw_c.pop_front();
            o.data = w_d.pop_front();   o.strb = w_s.pop_front();  cw = w_c.pop_front();
            o.aw_stall_cycles = aw_stall_q.pop_front();
            o.w_stall_cycles = w_stall_q.pop_front();
            o.c_aw = ca; o.c_w = cw;
            o.c_req = (ca > cw) ? ca : cw;
          end else begin
            o.unexpected = 1'b1; n_unexp++;
          end
          b_seen = 1'b0; n_b++;
          mon2scb.put(o);
          if (mon2cov != null) mon2cov.put(o);
        end

        // read response handshake
        if (vif.RVALID === 1'b1 && vif.RREADY === 1'b1) begin
          o = new();
          o.kind = OBS_RESPONSE; o.op = OP_READ; o.rsp = vif.RRESP; o.data = vif.RDATA;
          o.c_vld = r_vld_c; o.c_rsp = cycle; o.t_rsp = $time;
          if (ar_q.size() > 0) begin
            o.addr  = ar_q.pop_front();
            o.c_req = ar_c.pop_front();
            o.ar_stall_cycles = ar_stall_q.pop_front();
          end else begin
            o.unexpected = 1'b1; n_unexp++;
          end
          r_seen = 1'b0; n_r++;
          mon2scb.put(o);
          if (mon2cov != null) mon2cov.put(o);
        end
      end
    end
  endtask
endclass
`endif
