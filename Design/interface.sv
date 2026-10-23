`ifndef AXI4L_IF_SV
`define AXI4L_IF_SV
interface axi4l_if #(parameter int ADDR_W = 32, parameter int DATA_W = 32)
                    (input logic ACLK, input logic ARESETN);
  localparam int STRB_W = DATA_W/8;

  // write address
  logic [ADDR_W-1:0] AWADDR;
  logic              AWVALID;
  logic              AWREADY;
  // write data
  logic [DATA_W-1:0] WDATA;
  logic [STRB_W-1:0] WSTRB;
  logic              WVALID;
  logic              WREADY;
  // write response
  logic [1:0]        BRESP;
  logic              BVALID;
  logic              BREADY;
  // read address
  logic [ADDR_W-1:0] ARADDR;
  logic              ARVALID;
  logic              ARREADY;
  // read data
  logic [DATA_W-1:0] RDATA;
  logic [1:0]        RRESP;
  logic              RVALID;
  logic              RREADY;

  modport master (
    input  ACLK, ARESETN,
    output AWADDR, AWVALID, WDATA, WSTRB, WVALID, BREADY, ARADDR, ARVALID, RREADY,
    input  AWREADY, WREADY, BRESP, BVALID, ARREADY, RDATA, RRESP, RVALID);

  modport slave (
    input  ACLK, ARESETN,
    input  AWADDR, AWVALID, WDATA, WSTRB, WVALID, BREADY, ARADDR, ARVALID, RREADY,
    output AWREADY, WREADY, BRESP, BVALID, ARREADY, RDATA, RRESP, RVALID);

  modport monitor (
    input ACLK, ARESETN,
    input AWADDR, AWVALID, AWREADY, WDATA, WSTRB, WVALID, WREADY,
          BRESP, BVALID, BREADY, ARADDR, ARVALID, ARREADY,
          RDATA, RRESP, RVALID, RREADY);
endinterface
`endif