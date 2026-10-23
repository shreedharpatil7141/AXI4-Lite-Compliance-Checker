`ifndef AXI_GENERATOR_SV
`define AXI_GENERATOR_SV
class generator;
  mailbox #(transaction) gen2drv;
  int unsigned seed;
  int unsigned depth;      // words
  int unsigned num_gen;
  bit [31:0]   last_addr;
  bit          have_last;

  function new(mailbox #(transaction) m, int unsigned seed, int unsigned depth);
    this.gen2drv   = m;
    this.seed      = seed;
    this.depth     = depth;
    this.num_gen   = 0;
    this.last_addr = 0;
    this.have_last = 0;
  endfunction

  function bit [1:0] exp_for(bit [31:0] a);
    return ((a >> 2) < depth) ? 2'b00 : 2'b10;
  endfunction

  task put(transaction t);
    t.id       = num_gen;
    t.exp_resp = exp_for(t.addr);
    num_gen++;
    gen2drv.put(t);
  endtask

  task wr(bit [31:0] a, bit [31:0] d, bit [3:0] s,
          int unsigned awd, int unsigned wd, int unsigned bp);
    transaction t = new();
    t.op = OP_WRITE; t.addr = a; t.data = d; t.strb = s;
    t.aw_dly = awd; t.w_dly = wd; t.bready_dly = bp;
    t.ar_dly = 0; t.rready_dly = 0; t.gap = 0;
    put(t);
  endtask

  task rd(bit [31:0] a, int unsigned ard, int unsigned rp);
    transaction t = new();
    t.op = OP_READ; t.addr = a; t.data = 0; t.strb = 0;
    t.ar_dly = ard; t.rready_dly = rp;
    t.aw_dly = 0; t.w_dly = 0; t.bready_dly = 0; t.gap = 0;
    put(t);
  endtask

  task directed_basic();
    wr(32'h00, 32'hDEADBEEF, 4'hF, 0, 0, 0);
    rd(32'h00, 0, 0);
    wr(32'h04, 32'h12345678, 4'hF, 6, 0, 0);   // W before AW
    rd(32'h04, 0, 0);
    wr(32'h08, 32'hCAFEF00D, 4'hF, 0, 6, 0);   // AW before W
    rd(32'h08, 0, 0);
    wr(32'h0C, 32'h0BADF00D, 4'hF, 0, 0, 5);   // B backpressure 5
    rd(32'h0C, 0, 7);                          // R backpressure 7
    wr(32'h10, 32'h89ABCDEF, 4'hF, 3, 3, 2);   // same-cycle AW/W
    rd(32'h10, 2, 3);
  endtask

  task directed_boundary();
    wr(32'h0,               32'hA5A5A5A5, 4'hF, 0, 0, 0);          // first word
    rd(32'h0,               0, 0);
    wr((depth - 1) * 4,     32'h5A5A5A5A, 4'hF, 0, 0, 0);          // last word
    rd((depth - 1) * 4,     0, 0);
    wr(depth * 4,           32'h00000001, 4'hF, 0, 0, 0);          // first OOR word
    rd(depth * 4,           0, 0);
    wr(32'h1000_0000,       32'h00000002, 4'hF, 0, 0, 0);          // far OOR
    rd(32'h1000_0000,       0, 0);
    rd((depth - 1) * 4,     0, 0);                                 // last word intact
  endtask

  task directed_strobe();
    wr(32'h14, 32'h11223344, 4'hF, 0, 0, 0);
    rd(32'h14, 0, 0);
    wr(32'h14, 32'hAABBCCDD, 4'b0001, 0, 0, 0); rd(32'h14, 0, 0);
    wr(32'h14, 32'hAABBCCDD, 4'b0010, 0, 0, 0); rd(32'h14, 0, 0);
    wr(32'h14, 32'hAABBCCDD, 4'b0100, 0, 0, 0); rd(32'h14, 0, 0);
    wr(32'h14, 32'hAABBCCDD, 4'b1000, 0, 0, 0); rd(32'h14, 0, 0);
    wr(32'h14, 32'hFFFFFFFF, 4'b0000, 0, 0, 0); rd(32'h14, 0, 0);
    wr(32'h14, 32'h55555555, 4'b0101, 0, 0, 0); rd(32'h14, 0, 0);
    wr(32'h14, 32'hAAAAAAAA, 4'b1010, 0, 0, 0); rd(32'h14, 0, 0);
  endtask

  task directed_raw_waw();
    wr(32'h18, 32'h00000001, 4'hF, 0, 0, 0);   // WAW
    wr(32'h18, 32'h00000002, 4'hF, 0, 0, 0);
    wr(32'h18, 32'h00000003, 4'hF, 0, 0, 0);
    rd(32'h18, 0, 0);                          // RAW, expect 3
    wr(32'h1C, 32'hFEEDFACE, 4'hF, 0, 0, 0);
    rd(32'h1C, 0, 0);
    rd(32'h1C, 0, 0);                          // repeated read
  endtask

  task rand_traffic(int unsigned n);
    repeat (n) begin
      transaction t = new();
      t.srandom(seed + num_gen);               // per-txn deterministic seed
      t.have_last = have_last;
      t.last_addr = last_addr;
      t.addr_lo   = 32'h0;
      t.addr_hi   = depth * 4 - 4;
      if (!t.randomize()) $fatal(1, "generator: randomize failed");
      last_addr = t.addr;
      have_last = 1'b1;
      put(t);
    end
  endtask

  task run_all(int unsigned n_rand);
    directed_basic();
    directed_boundary();
    directed_strobe();
    directed_raw_waw();
    rand_traffic(n_rand);
  endtask
endclass
`endif