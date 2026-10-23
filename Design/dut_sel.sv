`ifndef DUT_SEL_SV
`define DUT_SEL_SV
// Selects RAM or GPIO behind one AXI4-Lite slave port. sel set by tb at time 0.
module dut_sel (input logic ACLK, input logic ARESETN, axi4l_if.slave s);
  logic sel = 1'b0;   // 0 = RAM, 1 = GPIO

  axi4l_if #(32, 32) ri (ACLK, ARESETN);
  axi4l_if #(32, 32) gi (ACLK, ARESETN);

  logic [31:0] g_out, g_dir;

  axi4_lite_ram  #(.ADDR_W(32), .DATA_W(32), .DEPTH(16)) u_ram (.s(ri));
  axi4_lite_gpio #(.ADDR_W(32), .DATA_W(32), .NWORDS(8)) u_gpio (
    .s(gi), .gpio_in(32'hA5C30F1E), .gpio_out(g_out), .gpio_dir(g_dir));

  // master-driven signals fan out to both
  assign ri.AWADDR = s.AWADDR;  assign gi.AWADDR = s.AWADDR;
  assign ri.AWVALID = s.AWVALID; assign gi.AWVALID = s.AWVALID;
  assign ri.WDATA  = s.WDATA;   assign gi.WDATA  = s.WDATA;
  assign ri.WSTRB  = s.WSTRB;   assign gi.WSTRB  = s.WSTRB;
  assign ri.WVALID = s.WVALID;  assign gi.WVALID = s.WVALID;
  assign ri.BREADY = s.BREADY;  assign gi.BREADY = s.BREADY;
  assign ri.ARADDR = s.ARADDR;  assign gi.ARADDR = s.ARADDR;
  assign ri.ARVALID = s.ARVALID; assign gi.ARVALID = s.ARVALID;
  assign ri.RREADY = s.RREADY;  assign gi.RREADY = s.RREADY;

  // slave-driven signals muxed back
  assign s.AWREADY = sel ? gi.AWREADY : ri.AWREADY;
  assign s.WREADY  = sel ? gi.WREADY  : ri.WREADY;
  assign s.BRESP   = sel ? gi.BRESP   : ri.BRESP;
  assign s.BVALID  = sel ? gi.BVALID  : ri.BVALID;
  assign s.ARREADY = sel ? gi.ARREADY : ri.ARREADY;
  assign s.RDATA   = sel ? gi.RDATA   : ri.RDATA;
  assign s.RRESP   = sel ? gi.RRESP   : ri.RRESP;
  assign s.RVALID  = sel ? gi.RVALID  : ri.RVALID;
endmodule
`endif