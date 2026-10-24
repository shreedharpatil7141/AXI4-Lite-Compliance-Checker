`ifndef AXI_VIOL_MON_SV
`define AXI_VIOL_MON_SV
typedef enum int {
  V_VALID_WITHDRAWAL,
  V_PAYLOAD_INSTAB,
  V_UNEXPECTED_RESP,
  V_MISSING_RESP,
  V_RESP_TIMEOUT,
  V_RESP_PAYLOAD_INSTAB,
  V_ILLEGAL_RESP_ENC,
  V_ACCOUNTING,
  V_RESET_RECOVERY,
  V_DATA_MISMATCH,
  V_X_UNKNOWN,
  V_RESP_CODE_MISMATCH
} vcat_e;

localparam int NUM_VCAT = 12;

class viol_mon;
  static int unsigned cnt [NUM_VCAT];
  static int unsigned cnt_dut [NUM_VCAT];   // subset reported by the DUT-facing checker (channel prefix "D:")
  static string       ctx = "init";        // test / seed context printed on every VIOL line
  static int unsigned dup_cnt    = 0;
  static int unsigned exp_hits   = 0;
  static int unsigned unexp_hits = 0;
  static int unsigned unexp_base = 0;
  static bit          exp_en     = 1'b0;
  static vcat_e       exp_cat    = V_VALID_WITHDRAWAL;
  static string       exp_ch     = "";
  static time         window     = 200;

  static bit          seen  [string];
  static int unsigned pa_n  [string];
  static time         pa_t  [string];
  static int unsigned pp_n  [string];
  static time         pp_t  [string];

  static function string cname(vcat_e c);
    case (c)
      V_VALID_WITHDRAWAL:    return "VALID_WITHDRAWAL";
      V_PAYLOAD_INSTAB:      return "PAYLOAD_INSTABILITY";
      V_UNEXPECTED_RESP:     return "UNEXPECTED_RESPONSE";
      V_MISSING_RESP:        return "MISSING_RESPONSE";
      V_RESP_TIMEOUT:        return "RESPONSE_TIMEOUT";
      V_RESP_PAYLOAD_INSTAB: return "RESP_PAYLOAD_INSTABILITY";
      V_ILLEGAL_RESP_ENC:    return "ILLEGAL_RESP_ENCODING";
      V_ACCOUNTING:          return "ACCOUNTING_MISMATCH";
      V_RESET_RECOVERY:      return "RESET_RECOVERY";
      V_DATA_MISMATCH:       return "DATA_MISMATCH";
      V_X_UNKNOWN:           return "X_UNKNOWN";
      V_RESP_CODE_MISMATCH:  return "RESP_CODE_MISMATCH";
      default:               return "UNKNOWN";
    endcase
  endfunction

  static function string kind(vcat_e c);
    case (c)
      V_DATA_MISMATCH, V_RESP_CODE_MISMATCH: return "DATA";
      V_RESP_TIMEOUT, V_MISSING_RESP:  return "TIMEOUT";
      V_ACCOUNTING:                    return "ACCOUNTING";
      default:                         return "PROTOCOL";
    endcase
  endfunction

  static function time dtm(time a, time b);
    return (a > b) ? (a - b) : (b - a);
  endfunction

  static function void set_expect(vcat_e c, string ch);
    exp_en = 1'b1; exp_cat = c; exp_ch = ch;
    exp_hits = 0; unexp_base = unexp_hits;
    pa_n.delete(); pa_t.delete(); pp_n.delete(); pp_t.delete();
  endfunction

  static function void set_ctx(string s);
    ctx = s;
  endfunction

  static function void clear_expect();
    exp_en = 1'b0;
  endfunction

  static function int unsigned fault_unexpected();
    return unexp_hits - unexp_base;
  endfunction

  static function int unsigned total_dut();
    int unsigned s;
    s = 0;
    foreach (cnt_dut[i]) s += cnt_dut[i];
    return s;
  endfunction

  static function int unsigned total();
    int unsigned s;
    s = 0;
    foreach (cnt[i]) s += cnt[i];
    return s;
  endfunction

  static function bit report(vcat_e c, string ch, time t, string msg, bit from_chk);
    string k, k2, src;
    bit    is_exp;
    k  = $sformatf("%0d:%s:%0t", int'(c), ch, t);
    k2 = $sformatf("%0d:%s", int'(c), ch);
    if (seen.exists(k)) begin
      dup_cnt++;
      return 1'b0;
    end
    seen[k] = 1'b1;
    if (from_chk) src = "CHK"; else src = "PROC";

    if (c == V_UNEXPECTED_RESP) begin
      if (from_chk) begin
        if (pp_n.exists(k2) && pp_n[k2] > 0 && dtm(t, pp_t[k2]) <= window) begin
          pp_n[k2]--; dup_cnt++;
          return 1'b0;
        end
        pa_n[k2] = (pa_n.exists(k2) ? pa_n[k2] : 0) + 1;
        pa_t[k2] = t;
      end else begin
        if (pa_n.exists(k2) && pa_n[k2] > 0 && dtm(t, pa_t[k2]) <= window) begin
          pa_n[k2]--; dup_cnt++;
          return 1'b0;
        end
        pp_n[k2] = (pp_n.exists(k2) ? pp_n[k2] : 0) + 1;
        pp_t[k2] = t;
      end
    end

    cnt[int'(c)]++;
    if (ch.len() >= 2 && ch.substr(0, 1) == "D:") cnt_dut[int'(c)]++;
    is_exp = exp_en && (c == exp_cat) && (exp_ch == "" || exp_ch == ch);
    if (is_exp) exp_hits++; else unexp_hits++;
    $display("VIOL%s [%s/%s] t=%0t ch=%s src=%s ctx=%s %s",
             is_exp ? "(expected)" : "", kind(c), cname(c), t, ch,
             src, ctx, msg);
    return 1'b1;
  endfunction

  static function void summary();
    string s;
    s = "";
    for (int i = 0; i < NUM_VCAT; i++) begin
      vcat_e c;
      c = vcat_e'(i);
      s = {s, $sformatf(" %s=%0d", cname(c), cnt[i])};
    end
    $display("VSUM%s", s);
    $display("VSUM total=%0d expected=%0d unexpected=%0d dup_suppressed=%0d dut_facing=%0d",
             total(), exp_hits, unexp_hits, dup_cnt, total_dut());
  endfunction
endclass
`endif