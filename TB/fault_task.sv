  // ================= fault driver (fbus only) =================
  initial begin
    fbus.AWADDR = '0; fbus.AWVALID = 0; fbus.AWREADY = 0;
    fbus.WDATA  = '0; fbus.WSTRB   = '0; fbus.WVALID = 0; fbus.WREADY = 0;
    fbus.BRESP  = 0;  fbus.BVALID  = 0;  fbus.BREADY = 0;
    fbus.ARADDR = '0; fbus.ARVALID = 0; fbus.ARREADY = 0;
    fbus.RDATA  = '0; fbus.RRESP   = 0;  fbus.RVALID = 0; fbus.RREADY = 0;
  end

  task automatic fb_clear();
    fbus.AWADDR <= '0; fbus.AWVALID <= 0; fbus.AWREADY <= 0;
    fbus.WDATA  <= '0; fbus.WSTRB   <= '0; fbus.WVALID <= 0; fbus.WREADY <= 0;
    fbus.BRESP  <= 0;  fbus.BVALID  <= 0;  fbus.BREADY <= 0;
    fbus.ARADDR <= '0; fbus.ARVALID <= 0; fbus.ARREADY <= 0;
    fbus.RDATA  <= '0; fbus.RRESP   <= 0;  fbus.RVALID <= 0; fbus.RREADY <= 0;
  endtask

  task automatic fb_reset();
    @(posedge ACLK); fb_clear(); FRST <= 1'b0;
    repeat (3) @(posedge ACLK);
    FRST <= 1'b1;
    repeat (2) @(posedge ACLK);
  endtask

  task automatic fb_aw_w();
    @(posedge ACLK);
    fbus.AWADDR <= '0; fbus.AWVALID <= 1; fbus.AWREADY <= 1;
    fbus.WDATA  <= '0; fbus.WSTRB <= 4'hF; fbus.WVALID <= 1; fbus.WREADY <= 1;
    @(posedge ACLK);
    fbus.AWVALID <= 0; fbus.AWREADY <= 0; fbus.WVALID <= 0; fbus.WREADY <= 0;
  endtask

  task automatic fb_ar();
    @(posedge ACLK);
    fbus.ARADDR <= '0; fbus.ARVALID <= 1; fbus.ARREADY <= 1;
    @(posedge ACLK);
    fbus.ARVALID <= 0; fbus.ARREADY <= 0;
  endtask

  task automatic fb_req_stall(input int ch, input bit chg, input bit drop);
    @(posedge ACLK);
    case (ch)
      0: begin fbus.AWADDR <= 32'h10; fbus.AWVALID <= 1'b1; fbus.AWREADY <= 1'b0; end
      1: begin fbus.WDATA <= 32'h1; fbus.WSTRB <= 4'hF; fbus.WVALID <= 1'b1; fbus.WREADY <= 1'b0; end
      default: begin fbus.ARADDR <= 32'h10; fbus.ARVALID <= 1'b1; fbus.ARREADY <= 1'b0; end
    endcase
    @(posedge ACLK);
    case (ch)
      0: begin if (chg) fbus.AWADDR <= 32'h20; if (drop) fbus.AWVALID <= 1'b0; end
      1: begin if (chg) fbus.WSTRB  <= 4'h3;   if (drop) fbus.WVALID  <= 1'b0; end
      default: begin if (chg) fbus.ARADDR <= 32'h20; if (drop) fbus.ARVALID <= 1'b0; end
    endcase
    @(posedge ACLK);
    fbus.AWREADY <= 1'b1; fbus.WREADY <= 1'b1; fbus.ARREADY <= 1'b1;
    @(posedge ACLK);
  endtask

  task automatic fb_resp_stall(input bit isB, input bit chg, input bit drop);
    if (isB) fb_aw_w(); else fb_ar();
    @(posedge ACLK);
    if (isB) begin fbus.BRESP <= 2'b00; fbus.BVALID <= 1'b1; fbus.BREADY <= 1'b0; end
    else     begin fbus.RDATA <= 32'hAA; fbus.RRESP <= 2'b00; fbus.RVALID <= 1'b1; fbus.RREADY <= 1'b0; end
    @(posedge ACLK);
    if (isB) begin if (chg) fbus.BRESP <= 2'b10; if (drop) fbus.BVALID <= 1'b0; end
    else     begin if (chg) fbus.RDATA <= 32'hBB; if (drop) fbus.RVALID <= 1'b0; end
    @(posedge ACLK);
    fbus.BREADY <= 1'b1; fbus.RREADY <= 1'b1;
    @(posedge ACLK);
    fbus.BVALID <= 1'b0; fbus.RVALID <= 1'b0;
    fbus.BREADY <= 1'b0; fbus.RREADY <= 1'b0;
    @(posedge ACLK);
  endtask

  task automatic fb_bad_enc(input bit isB);
    if (isB) fb_aw_w(); else fb_ar();
    @(posedge ACLK);
    if (isB) begin fbus.BRESP <= 2'b01; fbus.BVALID <= 1'b1; fbus.BREADY <= 1'b1; end
    else     begin fbus.RDATA <= 32'h1; fbus.RRESP <= 2'b01; fbus.RVALID <= 1'b1; fbus.RREADY <= 1'b1; end
    @(posedge ACLK);
    fbus.BVALID <= 1'b0; fbus.RVALID <= 1'b0;
    @(posedge ACLK);
  endtask

  task automatic fb_unexp(input bit isB);
    @(posedge ACLK);
    if (isB) begin fbus.BRESP <= 2'b00; fbus.BVALID <= 1'b1; fbus.BREADY <= 1'b1; end
    else     begin fbus.RDATA <= 32'h1; fbus.RRESP <= 2'b00; fbus.RVALID <= 1'b1; fbus.RREADY <= 1'b1; end
    @(posedge ACLK);
    fbus.BVALID <= 1'b0; fbus.RVALID <= 1'b0;
    @(posedge ACLK);
  endtask

  function automatic vcat_e fault_cat(int n);
    case (n)
      1, 3, 5, 7, 9:  return V_VALID_WITHDRAWAL;
      2, 4, 6:        return V_PAYLOAD_INSTAB;
      8, 10:          return V_RESP_PAYLOAD_INSTAB;
      11, 12:         return V_ILLEGAL_RESP_ENC;
      13, 14:         return V_UNEXPECTED_RESP;
      15, 18:         return V_X_UNKNOWN;
      default:        return V_RESET_RECOVERY;
    endcase
  endfunction

  function automatic string fault_ch(int n);
    case (n)
      1, 2, 18: return "AW";
      3, 4:    return "W";
      5, 6:    return "AR";
      7, 8:    return "B";
      9, 10:   return "R";
      11:      return "B";
      12:      return "R";
      13:      return "B";
      14:      return "R";
      15:      return "CTRL";
      default: return "RST";
    endcase
  endfunction

  task automatic run_fault(input int n);
    fb_reset();
    viol_mon::set_expect(fault_cat(n), fault_ch(n));
    case (n)
      1:  fb_req_stall(0, 0, 1);
      2:  fb_req_stall(0, 1, 0);
      3:  fb_req_stall(1, 0, 1);
      4:  fb_req_stall(1, 1, 0);
      5:  fb_req_stall(2, 0, 1);
      6:  fb_req_stall(2, 1, 0);
      7:  fb_resp_stall(1, 0, 1);
      8:  fb_resp_stall(1, 1, 0);
      9:  fb_resp_stall(0, 0, 1);
      10: fb_resp_stall(0, 1, 0);
      11: fb_bad_enc(1);
      12: fb_bad_enc(0);
      13: fb_unexp(1);
      14: fb_unexp(0);
      15: begin @(posedge ACLK); fbus.BREADY <= 1'bx; @(posedge ACLK); fbus.BREADY <= 1'b0; end
      16: begin @(posedge ACLK); FRST <= 1'b0; fbus.AWVALID <= 1'b1; repeat (3) @(posedge ACLK); end
      17: begin
            @(posedge ACLK); FRST <= 1'b0;
            repeat (3) @(posedge ACLK);
            FRST <= 1'b1; fbus.AWVALID <= 1'b1; fbus.AWREADY <= 1'b1; fbus.AWADDR <= '0;
            @(posedge ACLK);
          end
      18: begin
            @(posedge ACLK);
            fbus.AWADDR <= 32'hx; fbus.AWVALID <= 1'b1; fbus.AWREADY <= 1'b1;
            @(posedge ACLK);
            fbus.AWVALID <= 1'b0; fbus.AWREADY <= 1'b0;
          end
      default: ;
    endcase
    repeat (3) @(posedge ACLK);
    fb_clear();
    repeat (2) @(posedge ACLK);
  endtask