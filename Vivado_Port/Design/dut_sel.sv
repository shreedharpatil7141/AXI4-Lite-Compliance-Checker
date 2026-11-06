`ifndef DUT_SEL_SV
`define DUT_SEL_SV
// Selects one DUT behind one AXI4-Lite slave port. sel is set by tb at time 0.
//   0 = RAM, 1 = GPIO, 2 = RAM mutant (verification only, +DUT=ram_mut)
//   3 = RTL mutant library (verification only, +DUT=rtlmut, mutant chosen by mutid; 0 = control)
// Master-driven VALID and READY signals reach ONLY the selected DUT. Unselected DUTs
// see them tied low, so they cannot accept requests or change state.
// Cumulative isolation metrics cover each unselected DUT's B/R response pin:
// starts count a low-to-high violation transition, channel cycles count every
// active pin sample, and clock cycles count once if any pin violates that edge.
// With leak enabled, latency/backpressure can keep several unselected responses active.
module dut_sel (input logic ACLK, input logic ARESETN, axi4l_if.slave s);
  logic [1:0]  sel = 2'd0;
  logic        leak = 1'b0;   // verification-only: +ISOLEAK=1 disables gating to prove the isolation check can fail
  int unsigned iso_viol_channel_cycles = 0;
  int unsigned iso_viol_clock_cycles = 0;
  int unsigned iso_viol_events = 0;
  logic [7:0] iso_prev = '0; // B/R VALID state for RAM, GPIO, RAM mutant, RTL mutant
  int unsigned mutid = 0;      // mutant library selector (tb sets it; 0 = unmodified control)
  logic        minit = 1'b0;   // mutant library full re-initialization strobe (tb)
  int unsigned m_trig, m_pdiff;
  time         m_ttrig, m_tdiff;

  wire sr = (sel == 2'd0);
  wire sg = (sel == 2'd1);
  wire sm = (sel == 2'd2);
  wire er = sr | leak;   // enable for request delivery
  wire eg = sg | leak;
  wire em = sm | leak;
  wire sx = (sel == 2'd3);
  wire ex = sx | leak;

  axi4l_if #(32, 32) ri (ACLK, ARESETN);
  axi4l_if #(32, 32) gi (ACLK, ARESETN);
  axi4l_if #(32, 32) mi (ACLK, ARESETN);
  axi4l_if #(32, 32) xi (ACLK, ARESETN);

  logic [31:0] g_out, g_dir;

  axi4_lite_ram     #(.ADDR_W(32), .DATA_W(32), .DEPTH(16)) u_ram  (.s(ri));
  axi4_lite_gpio    #(.ADDR_W(32), .DATA_W(32), .NWORDS(8)) u_gpio (
    .s(gi), .gpio_in(32'hA5C30F1E), .gpio_out(g_out), .gpio_dir(g_dir));
  axi4_lite_ram_mut #(.ADDR_W(32), .DATA_W(32), .DEPTH(16)) u_mut  (.s(mi));
  axi4_lite_ram_mutlib #(.ADDR_W(32), .DATA_W(32), .DEPTH(16)) u_lib (
    .s(xi), .mutid(mutid), .minit(minit),
    .trig(m_trig), .pdiff(m_pdiff), .t_trig(m_ttrig), .t_diff(m_tdiff));

  // payloads fan out (harmless without VALID)
  assign ri.AWADDR = s.AWADDR;  assign gi.AWADDR = s.AWADDR;  assign mi.AWADDR = s.AWADDR;  assign xi.AWADDR = s.AWADDR;
  assign ri.WDATA  = s.WDATA;   assign gi.WDATA  = s.WDATA;   assign mi.WDATA  = s.WDATA;   assign xi.WDATA  = s.WDATA;
  assign ri.WSTRB  = s.WSTRB;   assign gi.WSTRB  = s.WSTRB;   assign mi.WSTRB  = s.WSTRB;   assign xi.WSTRB  = s.WSTRB;
  assign ri.ARADDR = s.ARADDR;  assign gi.ARADDR = s.ARADDR;  assign mi.ARADDR = s.ARADDR;  assign xi.ARADDR = s.ARADDR;

  // VALID and READY gated by selection
  assign ri.AWVALID = s.AWVALID & er;  assign gi.AWVALID = s.AWVALID & eg;  assign mi.AWVALID = s.AWVALID & em;  assign xi.AWVALID = s.AWVALID & ex;
  assign ri.WVALID  = s.WVALID  & er;  assign gi.WVALID  = s.WVALID  & eg;  assign mi.WVALID  = s.WVALID  & em;  assign xi.WVALID = s.WVALID & ex;
  assign ri.BREADY  = s.BREADY  & er;  assign gi.BREADY  = s.BREADY  & eg;  assign mi.BREADY  = s.BREADY  & em;  assign xi.BREADY = s.BREADY & ex;
  assign ri.ARVALID = s.ARVALID & er;  assign gi.ARVALID = s.ARVALID & eg;  assign mi.ARVALID = s.ARVALID & em;  assign xi.ARVALID = s.ARVALID & ex;
  assign ri.RREADY  = s.RREADY  & er;  assign gi.RREADY  = s.RREADY  & eg;  assign mi.RREADY  = s.RREADY  & em;  assign xi.RREADY = s.RREADY & ex;

  // slave-driven signals muxed back
  assign s.AWREADY = sx ? xi.AWREADY : sg ? gi.AWREADY : sm ? mi.AWREADY : ri.AWREADY;
  assign s.WREADY  = sx ? xi.WREADY : sg ? gi.WREADY  : sm ? mi.WREADY  : ri.WREADY;
  assign s.BRESP   = sx ? xi.BRESP : sg ? gi.BRESP   : sm ? mi.BRESP   : ri.BRESP;
  assign s.BVALID  = sx ? xi.BVALID : sg ? gi.BVALID  : sm ? mi.BVALID  : ri.BVALID;
  assign s.ARREADY = sx ? xi.ARREADY : sg ? gi.ARREADY : sm ? mi.ARREADY : ri.ARREADY;
  assign s.RDATA   = sx ? xi.RDATA : sg ? gi.RDATA   : sm ? mi.RDATA   : ri.RDATA;
  assign s.RRESP   = sx ? xi.RRESP : sg ? gi.RRESP   : sm ? mi.RRESP   : ri.RRESP;
  assign s.RVALID  = sx ? xi.RVALID : sg ? gi.RVALID  : sm ? mi.RVALID  : ri.RVALID;

  // isolation check: an unselected DUT must never raise a response VALID
  always @(posedge ACLK) begin
    if (ARESETN === 1'b1) begin
      bit any_iso_violation;
      any_iso_violation = 1'b0;
      if (!sr && ri.BVALID === 1'b1) begin iso_viol_channel_cycles++; any_iso_violation = 1'b1; if (!iso_prev[0]) iso_viol_events++; end
      if (!sr && ri.RVALID === 1'b1) begin iso_viol_channel_cycles++; any_iso_violation = 1'b1; if (!iso_prev[1]) iso_viol_events++; end
      if (!sg && gi.BVALID === 1'b1) begin iso_viol_channel_cycles++; any_iso_violation = 1'b1; if (!iso_prev[2]) iso_viol_events++; end
      if (!sg && gi.RVALID === 1'b1) begin iso_viol_channel_cycles++; any_iso_violation = 1'b1; if (!iso_prev[3]) iso_viol_events++; end
      if (!sm && mi.BVALID === 1'b1) begin iso_viol_channel_cycles++; any_iso_violation = 1'b1; if (!iso_prev[4]) iso_viol_events++; end
      if (!sm && mi.RVALID === 1'b1) begin iso_viol_channel_cycles++; any_iso_violation = 1'b1; if (!iso_prev[5]) iso_viol_events++; end
      if (!sx && xi.BVALID === 1'b1) begin iso_viol_channel_cycles++; any_iso_violation = 1'b1; if (!iso_prev[6]) iso_viol_events++; end
      if (!sx && xi.RVALID === 1'b1) begin iso_viol_channel_cycles++; any_iso_violation = 1'b1; if (!iso_prev[7]) iso_viol_events++; end
      if (any_iso_violation) iso_viol_clock_cycles++;
      iso_prev <= {!sx && xi.RVALID === 1'b1, !sx && xi.BVALID === 1'b1,
                   !sm && mi.RVALID === 1'b1, !sm && mi.BVALID === 1'b1,
                   !sg && gi.RVALID === 1'b1, !sg && gi.BVALID === 1'b1,
                   !sr && ri.RVALID === 1'b1, !sr && ri.BVALID === 1'b1};
    end else begin
      iso_prev <= '0;
    end
  end
endmodule
`endif
