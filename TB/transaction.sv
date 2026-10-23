`ifndef AXI_TRANSACTION_SV
`define AXI_TRANSACTION_SV
typedef enum bit {OP_READ = 1'b0, OP_WRITE = 1'b1} op_e;

class transaction;
  // stimulus (rand)
  rand op_e         op;
  rand bit [31:0]   addr;
  rand bit [31:0]   data;
  rand bit [3:0]    strb;
  rand int unsigned aw_dly;      // cycles before AWVALID
  rand int unsigned w_dly;       // cycles before WVALID
  rand int unsigned ar_dly;      // cycles before ARVALID
  rand int unsigned bready_dly;  // cycles BREADY held low after BVALID seen
  rand int unsigned rready_dly;  // cycles RREADY held low after RVALID seen
  rand int unsigned gap;         // idle cycles after txn
  rand bit          rep;         // reuse last address

  // generator knobs (not rand)
  bit [31:0] addr_lo   = 32'h0;
  bit [31:0] addr_hi   = 32'h3C;
  bit [31:0] last_addr = 32'h0;
  bit        have_last = 1'b0;

  // testbench-internal metadata. NOT on bus.
  int unsigned id;
  bit [1:0]    exp_resp;

  // driver results
  bit          done;
  bit          timed_out;
  bit [1:0]    rsp;
  bit [31:0]   rdata;

  constraint c_addr { addr inside {[addr_lo:addr_hi]}; addr[1:0] == 2'b00; }
  constraint c_rep  { rep dist {1'b0 := 6, 1'b1 := 4};
                      if (rep && have_last) addr == last_addr; }
  constraint c_op   { op dist {OP_WRITE := 5, OP_READ := 5}; }
  constraint c_strb { strb dist {4'hF := 40, 4'h0 := 5, [4'h1:4'hE] := 55}; }
  constraint c_dly  { aw_dly     inside {0,1,2,3,5,8};
                      w_dly      inside {0,1,2,3,5,8};
                      ar_dly     inside {0,1,2,3};
                      bready_dly inside {0,0,1,2,5,10};
                      rready_dly inside {0,0,1,2,5,10};
                      gap        inside {0,0,1,2,3}; }

  function string convert2string();
    return $sformatf("id=%0d %s addr=%h data=%h strb=%b exp=%0b | aw=%0d w=%0d ar=%0d bp_b=%0d bp_r=%0d | done=%0b to=%0b rsp=%0b rdata=%h",
                     id, (op == OP_WRITE) ? "WR" : "RD", addr, data, strb, exp_resp,
                     aw_dly, w_dly, ar_dly, bready_dly, rready_dly,
                     done, timed_out, rsp, rdata);
  endfunction
endclass
`endif