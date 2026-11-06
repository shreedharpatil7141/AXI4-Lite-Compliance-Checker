`ifndef AXI4_LITE_RAM_MUTLIB_SV
`define AXI4_LITE_RAM_MUTLIB_SV
// Verification-only RTL mutant library. Same architecture as axi4_lite_ram (16 words, one
// outstanding write and read, byte strobes, SLVERR out of range, memory not cleared by reset),
// plus one mutation selected by mutid. mutid 0 is the unmodified control.
//
// Instrumentation (verification only, no effect on the DUT-visible behavior):
//   trig  : number of times the intended mutated behavior actually occurred (activation).
//   pdiff : number of clock cycles where any DUT output pin differs from a golden shadow FSM
//           fed with the same input pins (observable behavioral difference).
//   t_trig, t_diff : $time of the first activation / first pin difference.
//   minit : full re-initialization (memory, FSMs, counters). Used between mutants.
//
// Mutants (frozen expectations are in mutant_tasks.sv):
//   1  BVALID withdrawn for one cycle while BREADY low (second VALID cycle)
//   2  BRESP bit1 flips from the second BVALID cycle
//   3  RDATA bit0 flips from the second RVALID cycle
//   4  RRESP bit1 flips from the second RVALID cycle
//   5  RVALID withdrawn for one cycle while RREADY low (second VALID cycle)
//   6  write strobes ignored (all bytes written)
//   7  write strobe bits reversed (byte-lane swap)
//   8  decode off by one: word index DEPTH treated as in range (writes dropped, reads return 0, OKAY)
//   9  write to word 0 also writes word DEPTH-1
//   10 out-of-range write returns OKAY
//   11 out-of-range read returns OKAY
//   12 one-cycle spurious BVALID pulse after the B handshake of the first write since reset
//   13 B response dropped for the third write since reset
//   14 R response dropped for the third read since reset
//   15 read of word 3 returns bit 31 flipped
//   16 reset does not clear RVALID/RRESP/RDATA
//   17 AWREADY ignores aw_got (second AW would overwrite a pending address)
//   18 EXOKAY (01) on the first write response since reset
//   19 one-cycle spurious RVALID pulse after the R handshake of the first read since reset
//   20 one-cycle early BVALID pulse when AW is accepted before W (first occurrence since reset)
module axi4_lite_ram_mutlib #(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32,
  parameter int DEPTH  = 16
)(
  axi4l_if.slave      s,
  input  int unsigned mutid,
  input  logic        minit,
  output int unsigned trig,
  output int unsigned pdiff,
  output time         t_trig,
  output time         t_diff
);
  localparam int STRB_W  = DATA_W/8;
  localparam int BYTE_SH = $clog2(STRB_W);
  localparam logic [1:0] OKAY   = 2'b00;
  localparam logic [1:0] EXOKAY = 2'b01;
  localparam logic [1:0] SLVERR = 2'b10;

  initial begin
    if ($bits(s.AWADDR) != ADDR_W || $bits(s.WDATA) != DATA_W)
      $fatal(1, "axi4_lite_ram_mutlib: interface width != module params");
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

  // ------------------------------------------------------------------ mutated machine
  logic [DATA_W-1:0] mem [DEPTH] = '{default: '0};
  logic              aw_got, w_got;
  logic [ADDR_W-1:0] aw_addr;
  logic [DATA_W-1:0] w_data;
  logic [STRB_W-1:0] w_strb;
  logic              bvalid, rvalid;
  logic [1:0]        bresp, rresp;
  logic [DATA_W-1:0] rdata;
  logic              glitch_b, glitch_r, pulse_b, pulse_r;
  logic              early_done;
  int unsigned       bv_age, rv_age, wr_n, rd_n;
  logic              mem_diff_q;

  wire              m_awready = (mutid == 17) ? !bvalid : (!aw_got && !bvalid);
  wire              m_wready  = !w_got && !bvalid;
  wire              m_bvalid  = (bvalid & ~glitch_b) | pulse_b;
  wire [1:0]        m_bresp   = bresp ^ ((mutid == 2 && bvalid && bv_age >= 1) ? 2'b10 : 2'b00);
  wire              m_arready = !rvalid;
  wire              m_rvalid  = (rvalid & ~glitch_r) | pulse_r;
  wire [DATA_W-1:0] m_rdata   = rdata ^ ((mutid == 3 && rvalid && rv_age >= 1) ? DATA_W'(1) : '0);
  wire [1:0]        m_rresp   = rresp ^ ((mutid == 4 && rvalid && rv_age >= 1) ? 2'b10 : 2'b00);

  assign s.AWREADY = m_awready;
  assign s.WREADY  = m_wready;
  assign s.BVALID  = m_bvalid;
  assign s.BRESP   = m_bresp;
  assign s.ARREADY = m_arready;
  assign s.RVALID  = m_rvalid;
  assign s.RDATA   = m_rdata;
  assign s.RRESP   = m_rresp;

  // ------------------------------------------------------------------ golden shadow
  logic [DATA_W-1:0] g_mem [DEPTH] = '{default: '0};
  logic              g_aw_got, g_w_got;
  logic [ADDR_W-1:0] g_aw_addr;
  logic [DATA_W-1:0] g_w_data;
  logic [STRB_W-1:0] g_w_strb;
  logic              g_bvalid, g_rvalid;
  logic [1:0]        g_bresp, g_rresp;
  logic [DATA_W-1:0] g_rdata;

  wire g_awready = !g_aw_got && !g_bvalid;
  wire g_wready  = !g_w_got  && !g_bvalid;
  wire g_arready = !g_rvalid;

  always_ff @(posedge s.ACLK) begin : gold_fsm
    int unsigned gwi;
    if (minit) begin
      g_aw_got <= 1'b0; g_w_got <= 1'b0; g_aw_addr <= '0; g_w_data <= '0; g_w_strb <= '0;
      g_bvalid <= 1'b0; g_bresp <= OKAY; g_rvalid <= 1'b0; g_rresp <= OKAY; g_rdata <= '0;
      for (int i = 0; i < DEPTH; i++) g_mem[i] <= '0;
    end else if (!s.ARESETN) begin
      g_aw_got <= 1'b0; g_w_got <= 1'b0; g_aw_addr <= '0; g_w_data <= '0; g_w_strb <= '0;
      g_bvalid <= 1'b0; g_bresp <= OKAY; g_rvalid <= 1'b0; g_rresp <= OKAY; g_rdata <= '0;
    end else begin
      if (s.AWVALID && g_awready) begin g_aw_got <= 1'b1; g_aw_addr <= s.AWADDR; end
      if (s.WVALID  && g_wready)  begin g_w_got <= 1'b1; g_w_data <= s.WDATA; g_w_strb <= s.WSTRB; end
      if (g_aw_got && g_w_got && !g_bvalid) begin
        if (in_range(g_aw_addr)) begin
          gwi = widx(g_aw_addr);
          for (int b = 0; b < STRB_W; b++)
            if (g_w_strb[b]) g_mem[gwi][8*b +: 8] <= g_w_data[8*b +: 8];
          g_bresp <= OKAY;
        end else begin
          g_bresp <= SLVERR;
        end
        g_bvalid <= 1'b1;
        g_aw_got <= 1'b0;
        g_w_got  <= 1'b0;
      end
      if (g_bvalid && s.BREADY) g_bvalid <= 1'b0;
      if (s.ARVALID && g_arready) begin
        g_rvalid <= 1'b1;
        if (in_range(s.ARADDR)) begin
          g_rdata <= g_mem[widx(s.ARADDR)];
          g_rresp <= OKAY;
        end else begin
          g_rdata <= '0;
          g_rresp <= SLVERR;
        end
      end
      if (g_rvalid && s.RREADY) g_rvalid <= 1'b0;
    end
  end

  // ------------------------------------------------------------------ observable difference
  logic mem_diff;
  always_comb begin
    mem_diff = 1'b0;
    for (int i = 0; i < DEPTH; i++)
      if (mem[i] !== g_mem[i]) mem_diff = 1'b1;
  end

  wire any_diff = (m_awready !== g_awready) || (m_wready !== g_wready) || (m_arready !== g_arready) ||
                  (m_bvalid !== g_bvalid) || (m_rvalid !== g_rvalid) ||
                  ((m_bvalid || g_bvalid) && (m_bresp !== g_bresp)) ||
                  ((m_rvalid || g_rvalid) && ((m_rdata !== g_rdata) || (m_rresp !== g_rresp)));

  always_ff @(posedge s.ACLK) begin : diff_cnt
    if (minit) begin
      pdiff  <= 0;
      t_diff <= 0;
    end else if (any_diff) begin
      pdiff <= pdiff + 1;
      if (pdiff == 0) t_diff <= $time;
    end
  end

  // ------------------------------------------------------------------ mutated FSM
  always_ff @(posedge s.ACLK) begin : mut_fsm
    int unsigned       ev;
    int unsigned       wi;
    bit                okr;
    logic [STRB_W-1:0] st;
    ev = 0;
    if (minit) begin
      aw_got <= 1'b0; w_got <= 1'b0; aw_addr <= '0; w_data <= '0; w_strb <= '0;
      bvalid <= 1'b0; bresp <= OKAY; rvalid <= 1'b0; rresp <= OKAY; rdata <= '0;
      glitch_b <= 1'b0; glitch_r <= 1'b0; pulse_b <= 1'b0; pulse_r <= 1'b0; early_done <= 1'b0;
      bv_age <= 0; rv_age <= 0; wr_n <= 0; rd_n <= 0; mem_diff_q <= 1'b0;
      for (int i = 0; i < DEPTH; i++) mem[i] <= '0;
      trig   <= 0;
      t_trig <= 0;
    end else begin
      glitch_b <= 1'b0; glitch_r <= 1'b0; pulse_b <= 1'b0; pulse_r <= 1'b0;

      if (!s.ARESETN) begin
        aw_got <= 1'b0; w_got <= 1'b0; aw_addr <= '0; w_data <= '0; w_strb <= '0;
        bvalid <= 1'b0; bresp <= OKAY;
        if (mutid == 16 && rvalid === 1'b1) begin
          ev++;                                   // M16 activation: state kept through reset
        end else begin
          rvalid <= 1'b0; rresp <= OKAY; rdata <= '0;
        end
        bv_age <= 0; rv_age <= 0; wr_n <= 0; rd_n <= 0; early_done <= 1'b0;
      end else begin
        if (bvalid) bv_age <= bv_age + 1; else bv_age <= 0;
        if (rvalid) rv_age <= rv_age + 1; else rv_age <= 0;

        // ---- write address / data accept ----
        if (s.AWVALID && m_awready) begin
          if (aw_got) ev++;                       // M17 activation: AW accepted while one is pending
          aw_got  <= 1'b1;
          aw_addr <= s.AWADDR;
        end
        if (s.WVALID && m_wready) begin
          w_got  <= 1'b1;
          w_data <= s.WDATA;
          w_strb <= s.WSTRB;
        end

        // ---- write execute ----
        if (aw_got && w_got && !bvalid) begin
          wi  = widx(aw_addr);
          okr = in_range(aw_addr);
          if (mutid == 8 && wi == DEPTH) begin okr = 1'b1; ev++; end
          if (mutid == 10 && !in_range(aw_addr)) ev++;
          st = w_strb;
          if (mutid == 6) st = '1;
          if (mutid == 7)
            for (int b = 0; b < STRB_W; b++) st[b] = w_strb[STRB_W-1-b];
          if (okr && wi < DEPTH) begin
            for (int b = 0; b < STRB_W; b++)
              if (st[b]) mem[wi][8*b +: 8] <= w_data[8*b +: 8];
            if (mutid == 9 && wi == 0)
              for (int b = 0; b < STRB_W; b++)
                if (st[b]) mem[DEPTH-1][8*b +: 8] <= w_data[8*b +: 8];
          end
          if (okr) begin
            if (mutid == 18 && wr_n == 0) begin bresp <= EXOKAY; ev++; end
            else                          bresp <= OKAY;
          end else begin
            bresp <= (mutid == 10) ? OKAY : SLVERR;
          end
          if (mutid == 13 && wr_n == 2) ev++;     // M13: response dropped
          else                          bvalid <= 1'b1;
          aw_got <= 1'b0;
          w_got  <= 1'b0;
          wr_n   <= wr_n + 1;
        end

        // M20: early BVALID pulse while AW accepted and W not yet accepted
        if (mutid == 20 && aw_got && !w_got && !bvalid && !early_done) begin
          pulse_b    <= 1'b1;
          early_done <= 1'b1;
          ev++;
        end

        // ---- B handshake ----
        if (bvalid && !glitch_b && s.BREADY) begin
          bvalid <= 1'b0;
          if (mutid == 12 && wr_n == 1) begin pulse_b <= 1'b1; ev++; end
        end

        // M1: BVALID withdrawn once while stalled
        if (mutid == 1 && bvalid && bv_age == 1 && !s.BREADY) begin
          glitch_b <= 1'b1;
          ev++;
        end
        // M2 / M3 / M4 activation (payload flips are in the output wires)
        if (mutid == 2 && bvalid && bv_age == 1) ev++;
        if (mutid == 3 && rvalid && rv_age == 1) ev++;
        if (mutid == 4 && rvalid && rv_age == 1) ev++;

        // ---- read accept ----
        if (s.ARVALID && m_arready) begin
          wi  = widx(s.ARADDR);
          okr = in_range(s.ARADDR);
          if (mutid == 8 && wi == DEPTH) begin okr = 1'b1; ev++; end
          if (mutid == 11 && !in_range(s.ARADDR)) ev++;
          if (okr) begin
            rdata <= (wi < DEPTH) ? mem[wi] : '0;
            rresp <= OKAY;
          end else begin
            rdata <= '0;
            rresp <= (mutid == 11) ? OKAY : SLVERR;
          end
          if (mutid == 15 && wi == 3) begin
            rdata <= mem[3] ^ {1'b1, {(DATA_W-1){1'b0}}};
            ev++;
          end
          if (mutid == 14 && rd_n == 2) ev++;     // M14: response dropped
          else                          rvalid <= 1'b1;
          rd_n <= rd_n + 1;
        end

        // ---- R handshake ----
        if (rvalid && !glitch_r && s.RREADY) begin
          rvalid <= 1'b0;
          if (mutid == 19 && rd_n == 1) begin pulse_r <= 1'b1; ev++; end
        end

        // M5: RVALID withdrawn once while stalled
        if (mutid == 5 && rvalid && rv_age == 1 && !s.RREADY) begin
          glitch_r <= 1'b1;
          ev++;
        end
      end

      // storage mutants: activation = stored state starts to differ from the golden shadow
      if ((mutid == 6 || mutid == 7 || mutid == 9) && mem_diff && !mem_diff_q) ev++;
      mem_diff_q <= mem_diff;

      if (ev != 0) begin
        trig <= trig + ev;
        if (trig == 0) t_trig <= $time;
      end
    end
  end
endmodule
`endif