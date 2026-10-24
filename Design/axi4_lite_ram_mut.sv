`ifndef AXI4_LITE_RAM_MUT_SV
`define AXI4_LITE_RAM_MUT_SV
// VERIFICATION-ONLY MUTANT of axi4_lite_ram. Selected with +DUT=ram_mut. Never used in legal regress.
// Mutation M1: after BVALID rises, if BREADY is still low one cycle later, BVALID is
// dropped for one cycle and then re-asserted (illegal VALID withdrawal).
module axi4_lite_ram_mut #(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32,
  parameter int DEPTH  = 256        // words
)(
  axi4l_if.slave s
);
  localparam int STRB_W  = DATA_W/8;
  localparam int BYTE_SH = $clog2(STRB_W);
  localparam logic [1:0] OKAY  = 2'b00;
  localparam logic [1:0] SLVERR = 2'b10;

  // sim-only init to zero, not cleared by reset
  logic [DATA_W-1:0] mem [DEPTH] = '{default: '0};

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
      $fatal(1, "axi4_lite_ram_mut: interface width != module params");
  end

  function automatic bit in_range(input logic [ADDR_W-1:0] a);
    logic [ADDR_W-1:0] w;
    w = a >> BYTE_SH;
    return (w < DEPTH);
  endfunction

  function automatic int unsigned widx(input logic [ADDR_W-1:0] a);
    logic [ADDR_W-1:0] w;
    w = a >> BYTE_SH;
    return int'(w);
  endfunction

  // one outstanding write, one outstanding read
  assign s.AWREADY = !aw_got && !bvalid;
  assign s.WREADY  = !w_got  && !bvalid;
  logic        glitch, gl_done;
  int unsigned bv_age;
  assign s.BVALID  = bvalid & ~glitch;
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
      glitch <= 1'b0;
      gl_done <= 1'b0;
      bv_age <= 0;
      bresp  <= OKAY;
      rvalid <= 1'b0;
      rresp  <= OKAY;
      rdata  <= '0;
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
          for (int b = 0; b < STRB_W; b++)
            if (w_strb[b]) mem[widx(aw_addr)][8*b +: 8] <= w_data[8*b +: 8];
          bresp <= OKAY;
        end else begin
          bresp <= SLVERR;
        end
        bvalid <= 1'b1;
        aw_got <= 1'b0;
        w_got  <= 1'b0;
      end
      if (s.BVALID && s.BREADY) bvalid <= 1'b0;

      // mutation M1
      glitch <= 1'b0;
      if (bvalid) bv_age <= bv_age + 1; else bv_age <= 0;
      if (bvalid && !gl_done && bv_age == 1 && !s.BREADY) begin
        glitch  <= 1'b1;
        gl_done <= 1'b1;
      end
      if (!bvalid) gl_done <= 1'b0;

      // ---- read path ----
      if (s.ARVALID && s.ARREADY) begin
        rvalid <= 1'b1;
        if (in_range(s.ARADDR)) begin
          rdata <= mem[widx(s.ARADDR)];
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