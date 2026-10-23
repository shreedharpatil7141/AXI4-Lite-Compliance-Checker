`ifndef AXI4_LITE_GPIO_SV
`define AXI4_LITE_GPIO_SV
module axi4_lite_gpio #(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32,
  parameter int NWORDS = 8
)(
  axi4l_if.slave            s,
  input  logic [DATA_W-1:0] gpio_in,
  output logic [DATA_W-1:0] gpio_out,
  output logic [DATA_W-1:0] gpio_dir
);
  localparam int STRB_W  = DATA_W/8;
  localparam int BYTE_SH = $clog2(STRB_W);
  localparam logic [1:0] OKAY   = 2'b00;
  localparam logic [1:0] SLVERR = 2'b10;
  localparam logic [DATA_W-1:0] ID_VAL = 32'h600D0001;

  logic              aw_got, w_got;
  logic [ADDR_W-1:0] aw_addr;
  logic [DATA_W-1:0] w_data;
  logic [STRB_W-1:0] w_strb;
  logic              bvalid;
  logic [1:0]        bresp;
  logic              rvalid;
  logic [1:0]        rresp;
  logic [DATA_W-1:0] rdata;

  initial begin
    if ($bits(s.AWADDR) != ADDR_W || $bits(s.WDATA) != DATA_W)
      $fatal(1, "axi4_lite_gpio: interface width != module params");
  end

  function automatic bit in_range(input logic [ADDR_W-1:0] a);
    logic [ADDR_W-1:0] w;
    w = a >> BYTE_SH;
    return (w < NWORDS);
  endfunction

  function automatic int unsigned widx(input logic [ADDR_W-1:0] a);
    logic [ADDR_W-1:0] w;
    w = a >> BYTE_SH;
    return int'(w);
  endfunction

  function automatic logic [DATA_W-1:0] rd_mux(input logic [ADDR_W-1:0] a);
    case (widx(a))
      0:       return gpio_out;
      1:       return gpio_in;
      2:       return gpio_dir;
      3:       return ID_VAL;
      default: return '0;
    endcase
  endfunction

  assign s.AWREADY = !aw_got && !bvalid;
  assign s.WREADY  = !w_got  && !bvalid;
  assign s.BVALID  = bvalid;
  assign s.BRESP   = bresp;
  assign s.ARREADY = !rvalid;
  assign s.RVALID  = rvalid;
  assign s.RDATA   = rdata;
  assign s.RRESP   = rresp;

  always_ff @(posedge s.ACLK) begin
    if (!s.ARESETN) begin
      aw_got <= 1'b0;
      w_got  <= 1'b0;
      aw_addr <= '0;
      w_data  <= '0;
      w_strb  <= '0;
      bvalid <= 1'b0;
      bresp  <= OKAY;
      rvalid <= 1'b0;
      rresp  <= OKAY;
      rdata  <= '0;
      gpio_out <= '0;
      gpio_dir <= '0;
    end else begin
      // ---- write path ----
      if (s.AWVALID && s.AWREADY) begin
        aw_got  <= 1'b1;
        aw_addr <= s.AWADDR;
      end
      if (s.WVALID && s.WREADY) begin
        w_got  <= 1'b1;
        w_data <= s.WDATA;
        w_strb <= s.WSTRB;
      end
      if (aw_got && w_got && !bvalid) begin
        if (in_range(aw_addr)) begin
          case (widx(aw_addr))
            0: begin
                 for (int b = 0; b < STRB_W; b++)
                   if (w_strb[b]) gpio_out[8*b +: 8] <= w_data[8*b +: 8];
               end
            2: begin
                 for (int b = 0; b < STRB_W; b++)
                   if (w_strb[b]) gpio_dir[8*b +: 8] <= w_data[8*b +: 8];
               end
            default: ;
          endcase
          bresp <= OKAY;
        end else begin
          bresp <= SLVERR;
        end
        bvalid <= 1'b1;
        aw_got <= 1'b0;
        w_got  <= 1'b0;
      end
      if (bvalid && s.BREADY) bvalid <= 1'b0;

      // ---- read path ----
      if (s.ARVALID && s.ARREADY) begin
        rvalid <= 1'b1;
        if (in_range(s.ARADDR)) begin
          rdata <= rd_mux(s.ARADDR);
          rresp <= OKAY;
        end else begin
          rdata <= '0;
          rresp <= SLVERR;
        end
      end
      if (rvalid && s.RREADY) rvalid <= 1'b0;
    end
  end
endmodule
`endif