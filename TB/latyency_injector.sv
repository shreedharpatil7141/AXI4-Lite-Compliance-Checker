`ifndef AXI4L_SHIM_SV
`define AXI4L_SHIM_SV
// Latency injector + verification-only fault hooks.
// m = master side (shim acts as slave). d = DUT side (shim acts as master).
// Delay cfg: >=0 fixed, -1 random {0,1,2,5,10}.
// cfg_fault: 0 legal. 1 hide BVALID once, 2 flip BRESP once, 3 hide RVALID once,
//            4 flip RDATA once, 5 swallow B forever.
module axi4l_shim (axi4l_if m, axi4l_if d);
  int          cfg_aw = 0, cfg_w = 0, cfg_ar = 0, cfg_b = 0, cfg_r = 0;
  int unsigned cfg_seed = 1;
  int          cfg_fault = 0;

  int unsigned cnt_aw, cnt_w, cnt_ar, cnt_b, cnt_r;
  int unsigned dly_aw, dly_w, dly_ar, dly_b, dly_r;
  logic [15:0] lfsr;
  logic [15:0] seed16;
  bit          f_done;

  assign seed16 = (cfg_seed[15:0] == 16'h0) ? 16'hACE1 : cfg_seed[15:0];

  function automatic int unsigned pick(input int cfg, input logic [15:0] l);
    int unsigned r;
    if (cfg >= 0) return cfg;
    case (int'(l) % 5)
      0:       r = 0;
      1:       r = 1;
      2:       r = 2;
      3:       r = 5;
      default: r = 10;
    endcase
    return r;
  endfunction

  // ---------------- request channels: hold off VALID ----------------
  wire aw_go = m.AWVALID && (cnt_aw >= dly_aw);
  wire w_go  = m.WVALID  && (cnt_w  >= dly_w);
  wire ar_go = m.ARVALID && (cnt_ar >= dly_ar);

  assign d.AWVALID = aw_go;
  assign d.AWADDR  = m.AWADDR;
  assign m.AWREADY = aw_go && d.AWREADY;

  assign d.WVALID  = w_go;
  assign d.WDATA   = m.WDATA;
  assign d.WSTRB   = m.WSTRB;
  assign m.WREADY  = w_go && d.WREADY;

  assign d.ARVALID = ar_go;
  assign d.ARADDR  = m.ARADDR;
  assign m.ARREADY = ar_go && d.ARREADY;

  // ---------------- response channels: hold off VALID ----------------
  wire b_show = d.BVALID && (cnt_b >= dly_b);
  wire r_show = d.RVALID && (cnt_r >= dly_r);

  // fault conditions (all false when cfg_fault == 0)
  wire f_hide_b  = (cfg_fault == 1) && !f_done && b_show && (cnt_b == 1) && !m.BREADY;
  wire f_flip_b  = (cfg_fault == 2) && !f_done && b_show && (cnt_b == 1) && !m.BREADY;
  wire f_hide_r  = (cfg_fault == 3) && !f_done && r_show && (cnt_r == 1) && !m.RREADY;
  wire f_flip_r  = (cfg_fault == 4) && !f_done && r_show && (cnt_r == 1) && !m.RREADY;
  wire f_swall_b = (cfg_fault == 5);
  wire f_fire    = f_hide_b | f_flip_b | f_hide_r | f_flip_r;

  wire b_vis = b_show && !f_hide_b && !f_swall_b;
  wire r_vis = r_show && !f_hide_r;

  assign m.BVALID = b_vis;
  assign m.BRESP  = d.BRESP ^ {f_flip_b, 1'b0};
  assign d.BREADY = m.BREADY && b_vis;

  assign m.RVALID = r_vis;
  assign m.RDATA  = d.RDATA ^ {31'b0, f_flip_r};
  assign m.RRESP  = d.RRESP;
  assign d.RREADY = m.RREADY && r_vis;

  // ---------------- counters and delay selection ----------------
  always_ff @(posedge m.ACLK) begin
    if (!m.ARESETN) begin
      lfsr   <= seed16;
      f_done <= 1'b0;
      cnt_aw <= 0; cnt_w <= 0; cnt_ar <= 0; cnt_b <= 0; cnt_r <= 0;
      dly_aw <= pick(cfg_aw, seed16 ^ 16'h1111);
      dly_w  <= pick(cfg_w,  seed16 ^ 16'h2222);
      dly_ar <= pick(cfg_ar, seed16 ^ 16'h3333);
      dly_b  <= pick(cfg_b,  seed16 ^ 16'h4444);
      dly_r  <= pick(cfg_r,  seed16 ^ 16'h5555);
    end else begin
      lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
      if (f_fire) f_done <= 1'b1;

      if (aw_go && d.AWREADY) begin
        cnt_aw <= 0; dly_aw <= pick(cfg_aw, lfsr ^ 16'h1111);
      end else if (m.AWVALID) cnt_aw <= cnt_aw + 1;

      if (w_go && d.WREADY) begin
        cnt_w <= 0;  dly_w  <= pick(cfg_w,  lfsr ^ 16'h2222);
      end else if (m.WVALID) cnt_w <= cnt_w + 1;

      if (ar_go && d.ARREADY) begin
        cnt_ar <= 0; dly_ar <= pick(cfg_ar, lfsr ^ 16'h3333);
      end else if (m.ARVALID) cnt_ar <= cnt_ar + 1;

      if (b_vis && m.BREADY) begin
        cnt_b <= 0;  dly_b  <= pick(cfg_b,  lfsr ^ 16'h4444);
      end else if (d.BVALID) cnt_b <= cnt_b + 1;

      if (r_vis && m.RREADY) begin
        cnt_r <= 0;  dly_r  <= pick(cfg_r,  lfsr ^ 16'h5555);
      end else if (d.RVALID) cnt_r <= cnt_r + 1;
    end
  end
endmodule
`endif