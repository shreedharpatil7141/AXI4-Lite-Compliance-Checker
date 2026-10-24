`ifndef DUT_SEL_SV
`define DUT_SEL_SV
// Selects one DUT behind one AXI4-Lite slave port. sel is set by tb at time 0.
//   0 = RAM, 1 = GPIO, 2 = RAM mutant (verification only, +DUT=ram_mut)
// Master-driven VALID and READY signals reach ONLY the selected DUT. Unselected DUTs
// see them tied low, so they cannot accept requests or change state.
// iso_viol counts any response VALID from an unselected DUT (must stay 0).
module dut_sel (input logic ACLK, input logic ARESETN, axi4l_if.slave s);
  logic [1:0]  sel = 2'd0;
  logic        leak = 1'b0;   // verification-only: +ISOLEAK=1 disables gating to prove the isolation check can fail
  int unsigned iso_viol = 0;

  wire sr = (sel == 2'd0);
  wire sg = (sel == 2'd1);
  wire sm = (sel == 2'd2);
  wire er = sr | leak;   // enable for request delivery
  wire eg = sg | leak;
  wire em = sm | leak;

  axi4l_if #(32, 32) ri (ACLK, ARESETN);
  axi4l_if #(32, 32) gi (ACLK, ARESETN);
  axi4l_if #(32, 32) mi (ACLK, ARESETN);

  logic [31:0] g_out, g_dir;

  axi4_lite_ram     #(.ADDR_W(32), .DATA_W(32), .DEPTH(16)) u_ram  (.s(ri));
  axi4_lite_gpio    #(.ADDR_W(32), .DATA_W(32), .NWORDS(8)) u_gpio (
    .s(gi), .gpio_in(32'hA5C30F1E), .gpio_out(g_out), .gpio_dir(g_dir));
  axi4_lite_ram_mut #(.ADDR_W(32), .DATA_W(32), .DEPTH(16)) u_mut  (.s(mi));

  // payloads fan out (harmless without VALID)
  assign ri.AWADDR = s.AWADDR;  assign gi.AWADDR = s.AWADDR;  assign mi.AWADDR = s.AWADDR;
  assign ri.WDATA  = s.WDATA;   assign gi.WDATA  = s.WDATA;   assign mi.WDATA  = s.WDATA;
  assign ri.WSTRB  = s.WSTRB;   assign gi.WSTRB  = s.WSTRB;   assign mi.WSTRB  = s.WSTRB;
  assign ri.ARADDR = s.ARADDR;  assign gi.ARADDR = s.ARADDR;  assign mi.ARADDR = s.ARADDR;

  // VALID and READY gated by selection
  assign ri.AWVALID = s.AWVALID & er;  assign gi.AWVALID = s.AWVALID & eg;  assign mi.AWVALID = s.AWVALID & em;
  assign ri.WVALID  = s.WVALID  & er;  assign gi.WVALID  = s.WVALID  & eg;  assign mi.WVALID  = s.WVALID  & em;
  assign ri.BREADY  = s.BREADY  & er;  assign gi.BREADY  = s.BREADY  & eg;  assign mi.BREADY  = s.BREADY  & em;
  assign ri.ARVALID = s.ARVALID & er;  assign gi.ARVALID = s.ARVALID & eg;  assign mi.ARVALID = s.ARVALID & em;
  assign ri.RREADY  = s.RREADY  & er;  assign gi.RREADY  = s.RREADY  & eg;  assign mi.RREADY  = s.RREADY  & em;

  // slave-driven signals muxed back
  assign s.AWREADY = sg ? gi.AWREADY : sm ? mi.AWREADY : ri.AWREADY;
  assign s.WREADY  = sg ? gi.WREADY  : sm ? mi.WREADY  : ri.WREADY;
  assign s.BRESP   = sg ? gi.BRESP   : sm ? mi.BRESP   : ri.BRESP;
  assign s.BVALID  = sg ? gi.BVALID  : sm ? mi.BVALID  : ri.BVALID;
  assign s.ARREADY = sg ? gi.ARREADY : sm ? mi.ARREADY : ri.ARREADY;
  assign s.RDATA   = sg ? gi.RDATA   : sm ? mi.RDATA   : ri.RDATA;
  assign s.RRESP   = sg ? gi.RRESP   : sm ? mi.RRESP   : ri.RRESP;
  assign s.RVALID  = sg ? gi.RVALID  : sm ? mi.RVALID  : ri.RVALID;

  // isolation check: an unselected DUT must never raise a response VALID
  always @(posedge ACLK) begin
    if (ARESETN === 1'b1) begin
      if (!sr && (ri.BVALID === 1'b1 || ri.RVALID === 1'b1)) iso_viol++;
      if (!sg && (gi.BVALID === 1'b1 || gi.RVALID === 1'b1)) iso_viol++;
      if (!sm && (mi.BVALID === 1'b1 || mi.RVALID === 1'b1)) iso_viol++;
    end
  end
endmodule
`endif
