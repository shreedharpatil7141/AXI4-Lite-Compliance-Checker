`ifndef AXI_GPIO_MODEL_SV
`define AXI_GPIO_MODEL_SV
class gpio_model extends ref_model;
  localparam bit [31:0] IN_VAL = 32'hA5C30F1E;
  localparam bit [31:0] ID_VAL = 32'h600D0001;

  bit [31:0]   r_out, r_dir;
  int unsigned nwords;
  bit          ignore_strb;   // scoreboard sensitivity check only

  function new(int unsigned nwords);
    this.nwords = nwords;
    ignore_strb = 1'b0;
    r_out = 32'h0;
    r_dir = 32'h0;
  endfunction

  function void on_reset();
    r_out = 32'h0;
    r_dir = 32'h0;
  endfunction

  function bit in_range(bit [31:0] a);
    return ((a >> 2) < nwords);
  endfunction

  virtual function bit [1:0] do_write(bit [31:0] addr, bit [31:0] data, bit [3:0] strb);
    int unsigned wi;
    if (!in_range(addr)) return 2'b10;
    wi = addr >> 2;
    if (wi == 0) begin
      for (int b = 0; b < 4; b++)
        if (strb[b] || ignore_strb) r_out[8*b +: 8] = data[8*b +: 8];
    end else if (wi == 2) begin
      for (int b = 0; b < 4; b++)
        if (strb[b] || ignore_strb) r_dir[8*b +: 8] = data[8*b +: 8];
    end
    return 2'b00;
  endfunction

  virtual function void do_read(bit [31:0] addr, output bit [31:0] data, output bit [1:0] rsp);
    int unsigned wi;
    if (!in_range(addr)) begin
      data = 32'h0; rsp = 2'b10;
    end else begin
      wi = addr >> 2;
      rsp = 2'b00;
      case (wi)
        0:       data = r_out;
        1:       data = IN_VAL;
        2:       data = r_dir;
        3:       data = ID_VAL;
        default: data = 32'h0;
      endcase
    end
  endfunction
endclass
`endif