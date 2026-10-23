`ifndef AXI4L_CHECKER_SV
`define AXI4L_CHECKER_SV
module axi4l_checker (axi4l_if vif);
  import tb_pkg::*;

  function automatic void rpt(vcat_e c, string ch, string m);
    void'(viol_mon::report(c, ch, $time, m, 1'b1));
  endfunction

  default clocking @(posedge vif.ACLK); endclocking
  default disable iff (!vif.ARESETN);

  a01: assert property ((vif.AWVALID && !vif.AWREADY) |=> vif.AWVALID)
       else rpt(V_VALID_WITHDRAWAL, "AW", "A01 AWVALID dropped before AWREADY");
  a03: assert property ((vif.WVALID && !vif.WREADY) |=> vif.WVALID)
       else rpt(V_VALID_WITHDRAWAL, "W", "A03 WVALID dropped before WREADY");
  a05: assert property ((vif.ARVALID && !vif.ARREADY) |=> vif.ARVALID)
       else rpt(V_VALID_WITHDRAWAL, "AR", "A05 ARVALID dropped before ARREADY");
  a07: assert property ((vif.BVALID && !vif.BREADY) |=> vif.BVALID)
       else rpt(V_VALID_WITHDRAWAL, "B", "A07 BVALID dropped before BREADY");
  a09: assert property ((vif.RVALID && !vif.RREADY) |=> vif.RVALID)
       else rpt(V_VALID_WITHDRAWAL, "R", "A09 RVALID dropped before RREADY");

  a02: assert property ((vif.AWVALID && !vif.AWREADY) |=> $stable(vif.AWADDR))
       else rpt(V_PAYLOAD_INSTAB, "AW", "A02 AWADDR changed while stalled");
  a04: assert property ((vif.WVALID && !vif.WREADY) |=> $stable({vif.WDATA, vif.WSTRB}))
       else rpt(V_PAYLOAD_INSTAB, "W", "A04 WDATA/WSTRB changed while stalled");
  a06: assert property ((vif.ARVALID && !vif.ARREADY) |=> $stable(vif.ARADDR))
       else rpt(V_PAYLOAD_INSTAB, "AR", "A06 ARADDR changed while stalled");
  a08: assert property ((vif.BVALID && !vif.BREADY) |=> $stable(vif.BRESP))
       else rpt(V_RESP_PAYLOAD_INSTAB, "B", "A08 BRESP changed while stalled");
  a10: assert property ((vif.RVALID && !vif.RREADY) |=> ($stable(vif.RDATA) && $stable(vif.RRESP)))
       else rpt(V_RESP_PAYLOAD_INSTAB, "R", "A10 RDATA/RRESP changed while stalled");

  a11b: assert property ((vif.BVALID && !$isunknown(vif.BRESP)) |-> (vif.BRESP != 2'b01))
        else rpt(V_ILLEGAL_RESP_ENC, "B", "A11 BRESP is EXOKAY");
  a11r: assert property ((vif.RVALID && !$isunknown(vif.RRESP)) |-> (vif.RRESP != 2'b01))
        else rpt(V_ILLEGAL_RESP_ENC, "R", "A11 RRESP is EXOKAY");

  a12: assert property (disable iff (1'b0)
         (!vif.ARESETN && !$past(vif.ARESETN)) |->
         (!vif.AWVALID && !vif.WVALID && !vif.ARVALID && !vif.BVALID && !vif.RVALID))
       else rpt(V_RESET_RECOVERY, "RST", "A12 VALID high during reset");
  a12b: assert property (disable iff (1'b0)
          (vif.ARESETN && !$past(vif.ARESETN)) |->
          (!vif.AWVALID && !vif.WVALID && !vif.ARVALID && !vif.BVALID && !vif.RVALID))
        else rpt(V_RESET_RECOVERY, "RST", "A12b VALID high on first cycle after reset");

  a15: assert property (!$isunknown({vif.AWVALID, vif.AWREADY, vif.WVALID, vif.WREADY,
                                     vif.BVALID, vif.BREADY, vif.ARVALID, vif.ARREADY,
                                     vif.RVALID, vif.RREADY}))
       else rpt(V_X_UNKNOWN, "CTRL", "A15 X/Z on control signal");
  a16_aw: assert property (vif.AWVALID |-> !$isunknown(vif.AWADDR))
          else rpt(V_X_UNKNOWN, "AW", "A16 X on AWADDR while AWVALID");
  a16_w:  assert property (vif.WVALID |-> !$isunknown({vif.WDATA, vif.WSTRB}))
          else rpt(V_X_UNKNOWN, "W", "A16 X on W payload while WVALID");
  a16_ar: assert property (vif.ARVALID |-> !$isunknown(vif.ARADDR))
          else rpt(V_X_UNKNOWN, "AR", "A16 X on ARADDR while ARVALID");
  a16_b:  assert property (vif.BVALID |-> !$isunknown(vif.BRESP))
          else rpt(V_X_UNKNOWN, "B", "A16 X on BRESP while BVALID");
  a16_r:  assert property (vif.RVALID |-> !$isunknown({vif.RDATA, vif.RRESP}))
          else rpt(V_X_UNKNOWN, "R", "A16 X on R payload while RVALID");

  longint aw_n = 0, w_n = 0, b_n = 0, ar_n = 0, r_n = 0;
  bit     bv_q = 0, bh_q = 0, rv_q = 0, rh_q = 0;
  bit     b_ok, r_ok;

  always @(posedge vif.ACLK) begin
    if (vif.ARESETN !== 1'b1) begin
      aw_n = 0; w_n = 0; b_n = 0; ar_n = 0; r_n = 0;
      bv_q = 0; bh_q = 0; rv_q = 0; rh_q = 0;
    end else begin
      b_ok = (aw_n > b_n) && (w_n > b_n);
      r_ok = (ar_n > r_n);
      if (vif.BVALID === 1'b1 && (!bv_q || bh_q) && !b_ok)
        rpt(V_UNEXPECTED_RESP, "B", "A13 BVALID without accepted AW and W");
      if (vif.RVALID === 1'b1 && (!rv_q || rh_q) && !r_ok)
        rpt(V_UNEXPECTED_RESP, "R", "A14 RVALID without accepted AR");

      if (vif.AWVALID === 1'b1 && vif.AWREADY === 1'b1) aw_n++;
      if (vif.WVALID  === 1'b1 && vif.WREADY  === 1'b1) w_n++;
      if (vif.ARVALID === 1'b1 && vif.ARREADY === 1'b1) ar_n++;
      if (vif.BVALID === 1'b1 && vif.BREADY === 1'b1 && b_ok) b_n++;
      if (vif.RVALID === 1'b1 && vif.RREADY === 1'b1 && r_ok) r_n++;

      bv_q = (vif.BVALID === 1'b1);
      bh_q = (vif.BVALID === 1'b1) && (vif.BREADY === 1'b1);
      rv_q = (vif.RVALID === 1'b1);
      rh_q = (vif.RVALID === 1'b1) && (vif.RREADY === 1'b1);
    end
  end
endmodule
`endif