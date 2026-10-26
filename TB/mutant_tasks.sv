// ===================== RTL mutant evaluation (verification only) =====================
  // Included inside module tb (like fault_tasks.sv). Used by +MUTSWEEP=1.
  //
  // FROZEN EXPECTATIONS. Written from assertions.sv (A01..A16), the S01..S10 procedural report
  // sites, and the mutation definitions in axi4_lite_ram_mutlib.sv, BEFORE any sweep was run.
  // Do not edit these tables to match a measurement; report mismatches as findings.
  //   exp detector / channel / category : the diagnosis the checker is expected to produce.
  //   channel is the DUT-port channel (the "D:" prefix is ignored: the expectation does not say
  //   which observation point must see it; MUTRES reports that separately as view=).
  //   allowed : detector/channel/category tuples that are direct, by-construction
  //   consequences of the mutation (derived from the code path). Other retained
  //   secondary records count as noise.
  //   Generic follow-on traffic after mutants 13/14 can pair later responses with
  //   unanswered requests and cause S04/S05/S06 cascades. Their scored stimuli below
  //   stop at the dropped response so those cascades are not part of the diagnosis.
  //   Mutant 19 can produce A10 one cycle after its spurious RVALID/A14 event if a new
  //   AR is accepted during the pulse and changes the read payload.
  //   Generic tests with a one-cycle BREADY/RREADY delay can time out at the withdrawal
  //   pulse and then create follow-on traffic diagnostics; mutant 1 uses an isolated
  //   five-cycle BREADY stall so the response recovers before the handshake.
  localparam int N_MUT = 20;
  localparam int CLK_NS = 10;   // matches "always #5 ACLK = ~ACLK"

  function automatic string mut_name(int id);
    case (id)
      0:  return "control";
      1:  return "bvalid_withdraw";
      2:  return "bresp_change_stall";
      3:  return "rdata_change_stall";
      4:  return "rresp_change_stall";
      5:  return "rvalid_withdraw";
      6:  return "strobe_ignored";
      7:  return "strobe_lane_swap";
      8:  return "decode_off_by_one";
      9:  return "write_alias_w0_w15";
      10: return "oor_write_okay";
      11: return "oor_read_okay";
      12: return "dup_b_pulse";
      13: return "drop_b";
      14: return "drop_r";
      15: return "rdata_bitflip_w3";
      16: return "reset_keeps_rvalid";
      17: return "second_aw_accepted";
      18: return "exokay_write";
      19: return "spurious_rvalid";
      20: return "early_b_before_w";
      default: return "unknown";
    endcase
  endfunction

  function automatic string mut_edet(int id);
    case (id)
      1: return "A07";  2: return "A08";  3: return "A10";  4: return "A10";  5: return "A09";
      6: return "S06";  7: return "S06";  8: return "S04";  9: return "S06";  10: return "S04";
      11: return "S05"; 12: return "A13"; 13: return "S09"; 14: return "S09"; 15: return "S06";
      16: return "A12"; 17: return "S06"; 18: return "A11"; 19: return "A14"; 20: return "A13";
      default: return "-";
    endcase
  endfunction

  function automatic string mut_ech(int id);
    case (id)
      1, 2, 8, 10, 12, 18, 20: return "B";
      3, 4, 5, 6, 7, 9, 11, 15, 17, 19: return "R";
      13, 14: return "REQ0";
      16: return "RST";
      default: return "-";
    endcase
  endfunction

  function automatic vcat_e mut_ecat(int id);
    case (id)
      1, 5:            return V_VALID_WITHDRAWAL;
      2, 3, 4:         return V_RESP_PAYLOAD_INSTAB;
      6, 7, 9, 15, 17: return V_DATA_MISMATCH;
      8, 10, 11:       return V_RESP_CODE_MISMATCH;
      12, 19, 20:      return V_UNEXPECTED_RESP;
      13, 14:          return V_MISSING_RESP;
      16:              return V_RESET_RECOVERY;
      18:              return V_ILLEGAL_RESP_ENC;
      default:         return V_VALID_WITHDRAWAL;
    endcase
  endfunction

  function automatic string chl(string ch);
    if (ch.len() >= 2 && ch.substr(0, 1) == "D:") return ch.substr(2, ch.len() - 1);
    return ch;
  endfunction

  // Allow only the detector/channel/category tuples documented as direct
  // consequences of each mutation. A detector ID alone is not an allowance.
  function automatic bit mut_allow_record(int id, vrec_t r);
    string ch;
    ch = chl(r.ch);
    case (id)
      2:  return r.det == "S04" && ch == "B" && r.cat == V_RESP_CODE_MISMATCH;
      3:  return r.det == "S06" && ch == "R" && r.cat == V_DATA_MISMATCH;
      4:  return r.det == "S05" && ch == "R" && r.cat == V_RESP_CODE_MISMATCH;
      8:  return r.det == "S05" && ch == "R" && r.cat == V_RESP_CODE_MISMATCH;
      12, 20: return r.det == "A07" && ch == "B" && r.cat == V_VALID_WITHDRAWAL;
      13, 14: return r.det == "S10" && r.cat == V_RESP_TIMEOUT &&
                    r.ch.len() >= 3 && r.ch.substr(0, 2) == "DRV";
      16: return ((r.det == "A12b" && ch == "RST" && r.cat == V_RESET_RECOVERY) ||
                  (r.det == "A14" && ch == "R" && r.cat == V_UNEXPECTED_RESP) ||
                  (r.det == "S10" && r.cat == V_RESP_TIMEOUT &&
                   r.ch.len() >= 3 && r.ch.substr(0, 2) == "DRV"));
      18: return r.det == "S04" && ch == "B" && r.cat == V_RESP_CODE_MISMATCH;
      19: return r.det == "A09" && ch == "R" && r.cat == V_VALID_WITHDRAWAL;
      default: return 1'b0;
    endcase
  endfunction

  // A10 is a consequence of mutant 19 only when it follows the spurious A14
  // sample by one clock on the same observation point. Do not allow unrelated
  // response-payload instability elsewhere in the mutant's full-test run.
  function automatic bit mut_allow_secondary_record(input int id, input vrec_t r,
      input int unsigned base, input int unsigned nr);
    vrec_t cause;
    if (mut_allow_record(id, r)) return 1'b1;
    if (id != 19 || r.det != "A10" || (r.ch != "R" && r.ch != "D:R") ||
        r.cat != V_RESP_PAYLOAD_INSTAB) return 1'b0;
    for (int i = 0; i < nr; i++) begin
      cause = viol_mon::recs[base + i];
      if (cause.det == "A14" && cause.cat == V_UNEXPECTED_RESP &&
          cause.ch == r.ch && r.t > cause.t && (r.t - cause.t) == CLK_NS)
        return 1'b1;
    end
    return 1'b0;
  endfunction

  function automatic bit mut_expected_record(vrec_t r, string edet, string ech, vcat_e ecat);
    return (r.det == edet) && (chl(r.ch) == ech) && (r.cat == ecat);
  endfunction

  function automatic string elapsed_cycles(bit valid, time t0, time t1);
    if (!valid) return "na";
    if (t1 < t0) return "pre_reference";
    return $sformatf("%0d", (t1 - t0) / CLK_NS);
  endfunction

  function automatic bit has_tok(string lst, string d);
    string pat;
    pat = {" ", d, " "};
    for (int i = 0; i + pat.len() <= lst.len(); i++)
      if (lst.substr(i, i + pat.len() - 1) == pat) return 1'b1;
    return 1'b0;
  endfunction

  typedef struct {
    string got;
    string primary_diag;
    string sec_out;
    string unexp_out;
    string view;
    bit det_ok, ch_ok, cat_ok, expected_seen, primary_match;
    bit any_bus, any_dut, have_first, have_expected;
    time first_t, expected_t;
    int unsigned secondary_records, unexp_secondary_records;
    int unsigned unexp_identities, primary_count, unallowed_primary_count;
  } mut_diag_result_t;

  // Classify only retained records in [base, base+nr). Record order remains
  // available as `got` for compatibility; primary is the earliest timestamp.
  task automatic classify_mut_records(input int id, input string edet,
      input string ech, input vcat_e ecat, input int unsigned base,
      input int unsigned nr, output mut_diag_result_t d);
    vrec_t r;
    string diag_id, sig, sec_keys, unexp_keys, primary_keys;
    bit is_expected, allowed;
    d.got = "none"; d.primary_diag = "-"; d.sec_out = ""; d.unexp_out = "";
    d.view = "NA";
    d.det_ok = 0; d.ch_ok = 0; d.cat_ok = 0; d.expected_seen = 0;
    d.primary_match = 0; d.any_bus = 0; d.any_dut = 0;
    d.have_first = 0; d.have_expected = 0; d.first_t = 0; d.expected_t = 0;
    d.secondary_records = 0; d.unexp_secondary_records = 0;
    d.unexp_identities = 0; d.primary_count = 0; d.unallowed_primary_count = 0;
    sec_keys = " "; unexp_keys = " "; primary_keys = " ";

    // First pass establishes timestamps and whether the frozen tuple appears
    // anywhere. No queue-order assumption is made for primary selection.
    for (int i = 0; i < nr; i++) begin
      r = viol_mon::recs[base + i];
      diag_id = (r.det == "") ? "<no-detector>" : r.det;
      is_expected = mut_expected_record(r, edet, ech, ecat);
      allowed = mut_allow_record(id, r);
`ifdef MUT_TRACE
      $display("MUTTRACE_RECORD,id=%0d,scan_index=%0d,record_index=%0d,raw_det='%s',diag_id='%s',cat=%s,ch=%s,expected_tuple=%0d,allowlisted=%0d",
               id, i, base+i, r.det, diag_id, viol_mon::cname(r.cat), r.ch,
               is_expected, allowed);
`endif
      if (i == 0) d.got = {diag_id, "/", r.ch, "/", viol_mon::cname(r.cat)};
      if (!d.have_first || r.t < d.first_t) begin
        d.have_first = 1; d.first_t = r.t;
      end
      if (diag_id == edet) d.det_ok = 1;
      if (diag_id == edet && chl(r.ch) == ech) d.ch_ok = 1;
      if (is_expected) begin
        d.cat_ok = 1; d.expected_seen = 1;
        if (!d.have_expected || r.t < d.expected_t) begin
          d.have_expected = 1; d.expected_t = r.t;
        end
        if (r.ch.len() >= 2 && r.ch.substr(0, 1) == "D:") d.any_dut = 1;
        else d.any_bus = 1;
      end
    end

    // All unique diagnostic tuples at the earliest event timestamp are
    // co-primary. Normalize D: so paired checker views have one identity.
    if (d.have_first) begin
      for (int i = 0; i < nr; i++) begin
        r = viol_mon::recs[base + i];
        if (r.t == d.first_t) begin
          diag_id = (r.det == "") ? "<no-detector>" : r.det;
          sig = {diag_id, "/", chl(r.ch), "/", viol_mon::cname(r.cat)};
          if (!has_tok(primary_keys, sig)) begin
            primary_keys = {primary_keys, sig, " "};
            d.primary_count++;
            d.primary_diag = (d.primary_diag == "-") ? sig : {d.primary_diag, "+", sig};
            if (!mut_expected_record(r, edet, ech, ecat) && !mut_allow_record(id, r))
              d.unallowed_primary_count++;
          end
          if (mut_expected_record(r, edet, ech, ecat)) d.primary_match = 1;
        end
      end

      // Only records strictly later than the co-primary timestamp are
      // secondary events. Expected tuples later in the run remain visible via
      // expected_seen but are not mislabeled as unexpected secondary noise.
      for (int i = 0; i < nr; i++) begin
        r = viol_mon::recs[base + i];
        if (r.t > d.first_t && !mut_expected_record(r, edet, ech, ecat)) begin
          diag_id = (r.det == "") ? "<no-detector>" : r.det;
          allowed = mut_allow_secondary_record(id, r, base, nr);
          d.secondary_records++;
          if (!has_tok(sec_keys, diag_id)) begin
            sec_keys = {sec_keys, diag_id, " "};
            d.sec_out = (d.sec_out == "") ? diag_id : {d.sec_out, "+", diag_id};
          end
          if (!allowed) begin
            d.unexp_secondary_records++;
            if (!has_tok(unexp_keys, diag_id)) begin
              unexp_keys = {unexp_keys, diag_id, " "};
              d.unexp_identities++;
              d.unexp_out = (d.unexp_out == "") ? diag_id : {d.unexp_out, "+", diag_id};
            end
          end
`ifdef MUT_TRACE
          $display("MUTTRACE_CLASS,id=%0d,scan_index=%0d,classified=secondary,allowlisted=%0d,unexp_event=%0d,secondary_records=%0d,unexp_secondary_records=%0d,unexp_identities=%0d,unexp_out='%s'",
                   id, i, allowed, !allowed, d.secondary_records,
                   d.unexp_secondary_records, d.unexp_identities, d.unexp_out);
`endif
        end
      end
    end
    if (d.sec_out == "") d.sec_out = "-";
    if (d.unexp_out == "") d.unexp_out = "-";
    d.view = (d.any_bus && d.any_dut) ? "BOTH" : d.any_bus ? "BUS" : d.any_dut ? "DUT" : "NA";
  endtask

  // Classification is based on the earliest simulation timestamp, not queue
  // insertion order. Distinct tuples at that timestamp are co-primary.
  function automatic string mutation_class(bit ctl, bit probe_ok,
      int unsigned nr, int unsigned tr, int unsigned pd, bit val_inv,
      bit expected_seen, bit primary_match, int unsigned unexp_secondary_records,
      int unsigned unallowed_primary_count, output string reason);
    reason = "-";
    if (ctl) return (nr == 0 && tr == 0 && pd == 0) ? "CONTROL_OK" : "CONTROL_FAIL";
    if (!probe_ok) begin reason = "second_aw_probe_failed"; return "MISSED"; end
    if (nr > 0 && tr == 0) begin reason = "reports_without_activation"; return "INVALID_MUTANT"; end
    if (val_inv) begin reason = "activated_but_no_pin_difference_under_exposure"; return "INVALID_MUTANT"; end
    if (nr == 0) begin
      if (tr == 0) begin reason = "no_activation"; return "NOT_EXERCISED"; end
      if (pd == 0) begin reason = "no_pin_difference"; return "NOT_EXERCISED"; end
      reason = "no_violation_record";
      return "MISSED";
    end
    if (!expected_seen) begin reason = "expected_tuple_absent"; return "MISDIAGNOSED"; end
    if (!primary_match) begin reason = "expected_tuple_not_primary"; return "MISDIAGNOSED"; end
    if (unallowed_primary_count > 0) begin
      reason = "unallowed_co_primary_diagnostic";
      return "AMBIGUOUS";
    end
    if (unexp_secondary_records > 0) return "NOISY";
    return "KILLED";
  endfunction

  function automatic vrec_t mut_test_record(vcat_e cat, string ch,
      string det, time t);
    vrec_t r;
    r.cat = cat; r.ch = ch; r.det = det; r.t = t; r.from_chk = 1'b1;
    return r;
  endfunction

  // Fast classifier self-check. Synthetic records are appended only for this
  // opt-in mode and removed before it exits; violation totals are untouched.
  task automatic run_mut_class_check();
    int unsigned base, n0, dup0;
    mut_diag_result_t d;
    string cls, reason;
    bit ok, all_ok;
    vcat_e expected_cat;

    base = viol_mon::nrec();
    expected_cat = V_UNEXPECTED_RESP;
    all_ok = 1'b1;
    viol_mon::recs.push_back(mut_test_record(expected_cat, "B", "A13", 100));
    classify_mut_records(12, "A13", "B", expected_cat, base, 1, d);
    cls = mutation_class(0, 1, 1, 1, 1, 0, d.expected_seen, d.primary_match,
                         d.unexp_secondary_records, d.unallowed_primary_count, reason);
    ok = (cls == "KILLED" && d.expected_seen && d.primary_match);
    all_ok &= ok;
    $display("MUTCLASSCASE,case=exact_primary,class=%s,expected_seen=%0d,primary_match=%0d,%s",
             cls, d.expected_seen, d.primary_match, ok ? "PASS" : "FAIL");
    while (viol_mon::recs.size() > base) void'(viol_mon::recs.pop_back());

    viol_mon::recs.push_back(mut_test_record(V_VALID_WITHDRAWAL, "B", "A07", 99));
    viol_mon::recs.push_back(mut_test_record(expected_cat, "D:B", "A13", 100));
    classify_mut_records(12, "A13", "B", expected_cat, base, 2, d);
    cls = mutation_class(0, 1, 2, 1, 1, 0, d.expected_seen, d.primary_match,
                         d.unexp_secondary_records, d.unallowed_primary_count, reason);
    ok = (cls == "MISDIAGNOSED" && d.expected_seen && !d.primary_match);
    all_ok &= ok;
    $display("MUTCLASSCASE,case=wrong_primary_expected_later,class=%s,expected_seen=%0d,primary_match=%0d,%s",
             cls, d.expected_seen, d.primary_match, ok ? "PASS" : "FAIL");
    while (viol_mon::recs.size() > base) void'(viol_mon::recs.pop_back());

    viol_mon::recs.push_back(mut_test_record(V_VALID_WITHDRAWAL, "B", "A07", 100));
    classify_mut_records(12, "A13", "B", expected_cat, base, 1, d);
    cls = mutation_class(0, 1, 1, 1, 1, 0, d.expected_seen, d.primary_match,
                         d.unexp_secondary_records, d.unallowed_primary_count, reason);
    ok = (cls == "MISDIAGNOSED" && !d.expected_seen && !d.primary_match);
    all_ok &= ok;
    $display("MUTCLASSCASE,case=expected_absent,class=%s,expected_seen=%0d,primary_match=%0d,%s",
             cls, d.expected_seen, d.primary_match, ok ? "PASS" : "FAIL");
    while (viol_mon::recs.size() > base) void'(viol_mon::recs.pop_back());

    viol_mon::recs.push_back(mut_test_record(expected_cat, "B", "A13", 100));
    viol_mon::recs.push_back(mut_test_record(V_VALID_WITHDRAWAL, "B", "A07", 101));
    viol_mon::recs.push_back(mut_test_record(V_RESP_CODE_MISMATCH, "B", "S04", 102));
    classify_mut_records(12, "A13", "B", expected_cat, base, 3, d);
    cls = mutation_class(0, 1, 3, 1, 1, 0, d.expected_seen, d.primary_match,
                         d.unexp_secondary_records, d.unallowed_primary_count, reason);
    ok = (cls == "NOISY" && d.primary_match && d.unexp_secondary_records == 1 &&
          d.unexp_identities == 1 && d.sec_out == "A07+S04");
    all_ok &= ok;
    $display("MUTCLASSCASE,case=allowed_and_unexpected_secondary,class=%s,primary_match=%0d,secondary_records=%0d,unexp_records=%0d,unexp_ids=%s,%s",
             cls, d.primary_match, d.secondary_records, d.unexp_secondary_records,
             d.unexp_out, ok ? "PASS" : "FAIL");
    while (viol_mon::recs.size() > base) void'(viol_mon::recs.pop_back());

    // Simultaneous expected and explicitly allowed tuple are co-primary and
    // do not become noisy merely because the reports share a timestamp.
    viol_mon::recs.push_back(mut_test_record(expected_cat, "B", "A13", 300));
    viol_mon::recs.push_back(mut_test_record(V_VALID_WITHDRAWAL, "D:B", "A07", 300));
    classify_mut_records(12, "A13", "B", expected_cat, base, 2, d);
    cls = mutation_class(0, 1, 2, 1, 1, 0, d.expected_seen, d.primary_match,
                         d.unexp_secondary_records, d.unallowed_primary_count, reason);
    ok = (cls == "KILLED" && d.primary_match && d.primary_count == 2 &&
          d.unallowed_primary_count == 0);
    all_ok &= ok;
    $display("MUTCLASSCASE,case=co_primary_allowed,class=%s,primary_count=%0d,unallowed_primary_count=%0d,primary_match=%0d,%s",
             cls, d.primary_count, d.unallowed_primary_count, d.primary_match, ok ? "PASS" : "FAIL");
    while (viol_mon::recs.size() > base) void'(viol_mon::recs.pop_back());

    // S10/DRV timeout is an explicitly scoped consequence of the unanswered
    // request for mutants 13/14, even when final_check emits it at S09's time.
    viol_mon::recs.push_back(mut_test_record(V_MISSING_RESP, "REQ0", "S09", 350));
    viol_mon::recs.push_back(mut_test_record(V_RESP_TIMEOUT, "DRV0", "S10", 350));
    classify_mut_records(13, "S09", "REQ0", V_MISSING_RESP, base, 2, d);
    cls = mutation_class(0, 1, 2, 1, 1, 0, d.expected_seen, d.primary_match,
                         d.unexp_secondary_records, d.unallowed_primary_count, reason);
    ok = (cls == "KILLED" && d.primary_match && d.primary_count == 2 &&
          d.unallowed_primary_count == 0);
    all_ok &= ok;
    $display("MUTCLASSCASE,case=missing_response_with_scoped_timeout,class=%s,primary_count=%0d,unallowed_primary_count=%0d,%s",
             cls, d.primary_count, d.unallowed_primary_count, ok ? "PASS" : "FAIL");
    while (viol_mon::recs.size() > base) void'(viol_mon::recs.pop_back());

    // Mutant 19's A10 consequence is allowed only for the next-cycle event
    // on the same bus view; an unrelated later A10 remains noisy.
    viol_mon::recs.push_back(mut_test_record(V_UNEXPECTED_RESP, "R", "A14", 500));
    viol_mon::recs.push_back(mut_test_record(V_RESP_PAYLOAD_INSTAB, "R", "A10", 510));
    classify_mut_records(19, "A14", "R", V_UNEXPECTED_RESP, base, 2, d);
    cls = mutation_class(0, 1, 2, 1, 1, 0, d.expected_seen, d.primary_match,
                         d.unexp_secondary_records, d.unallowed_primary_count, reason);
    ok = (cls == "KILLED" && d.primary_match && d.unexp_secondary_records == 0);
    all_ok &= ok;
    $display("MUTCLASSCASE,case=mut19_causal_a10,class=%s,unexp_secondary_records=%0d,%s",
             cls, d.unexp_secondary_records, ok ? "PASS" : "FAIL");
    while (viol_mon::recs.size() > base) void'(viol_mon::recs.pop_back());

    viol_mon::recs.push_back(mut_test_record(V_UNEXPECTED_RESP, "R", "A14", 600));
    viol_mon::recs.push_back(mut_test_record(V_RESP_PAYLOAD_INSTAB, "R", "A10", 620));
    classify_mut_records(19, "A14", "R", V_UNEXPECTED_RESP, base, 2, d);
    cls = mutation_class(0, 1, 2, 1, 1, 0, d.expected_seen, d.primary_match,
                         d.unexp_secondary_records, d.unallowed_primary_count, reason);
    ok = (cls == "NOISY" && d.primary_match && d.unexp_secondary_records == 1);
    all_ok &= ok;
    $display("MUTCLASSCASE,case=mut19_unrelated_a10,class=%s,unexp_secondary_records=%0d,%s",
             cls, d.unexp_secondary_records, ok ? "PASS" : "FAIL");
    while (viol_mon::recs.size() > base) void'(viol_mon::recs.pop_back());

    // An unallowlisted, distinct co-primary tuple remains ambiguous.
    viol_mon::recs.push_back(mut_test_record(expected_cat, "B", "A13", 400));
    viol_mon::recs.push_back(mut_test_record(V_RESP_CODE_MISMATCH, "B", "S04", 400));
    classify_mut_records(12, "A13", "B", expected_cat, base, 2, d);
    cls = mutation_class(0, 1, 2, 1, 1, 0, d.expected_seen, d.primary_match,
                         d.unexp_secondary_records, d.unallowed_primary_count, reason);
    ok = (cls == "AMBIGUOUS" && d.primary_match && d.primary_count == 2 &&
          d.unallowed_primary_count == 1);
    all_ok &= ok;
    $display("MUTCLASSCASE,case=co_primary_unallowed,class=%s,primary_count=%0d,unallowed_primary_count=%0d,%s",
             cls, d.primary_count, d.unallowed_primary_count, ok ? "PASS" : "FAIL");
    while (viol_mon::recs.size() > base) void'(viol_mon::recs.pop_back());

    viol_mon::clear_expect();
    viol_mon::reset_dedup();
    n0 = viol_mon::nrec(); dup0 = viol_mon::dup_cnt;
    void'(viol_mon::report(V_UNEXPECTED_RESP, "R", 200, "checker view", 1'b1, "A14"));
    void'(viol_mon::report(V_UNEXPECTED_RESP, "R", 200, "procedural view", 1'b0, ""));
    viol_mon::reset_dedup();
    void'(viol_mon::report(V_UNEXPECTED_RESP, "R", 200, "after dedup reset", 1'b1, "A14"));
    ok = (viol_mon::nrec() - n0 == 2) && (viol_mon::dup_cnt - dup0 == 1);
    all_ok &= ok;
    $display("MUTCLASSCASE,case=checker_procedural_duplicate,retained=%0d,duplicates=%0d,%s",
             viol_mon::nrec() - n0, viol_mon::dup_cnt - dup0, ok ? "PASS" : "FAIL");
    viol_mon::reset_dedup();

    $display("MUTCLASSSUM,%s", all_ok ? "PASS" : "FAIL");
    if (!all_ok) $fatal(1, "MUTCLASS self-check failed");
  endtask

  // ---- counters for MUTSUM ----
  int unsigned c_kill = 0, c_noisy = 0, c_mis = 0, c_miss = 0, c_ambig = 0, c_nex = 0, c_inv = 0;
  int unsigned c_recorded = 0, c_expected_seen = 0, c_primary_match = 0;
  bit          ctrl_ok = 1'b1;

  // Full re-initialization of the mutant, the reference model and the dedup state.
  task automatic mut_init(input int id);
    dut.mutid = id;
    dut.minit = 1'b1;
    do_reset();                         // minit is high for the whole reset
    dut.minit = 1'b0;
    if (rmh != null) foreach (rmh.mem[i]) rmh.mem[i] = 32'h0;
    viol_mon::reset_dedup();
  endtask

  // Directed exposure sequence used only by the validation phase: word 15 then word 0 (alias),
  // reads of both, and a write run for the "k-th since reset" mutants.
  task automatic run_expose();
    generator    gen;
    int unsigned base, d0, t0;
    gen = new(env.g2d, seed + 400, depth);
    neg_prep(0, 0, 0, 0);
    base = env.checked;
    d0   = env.drv.completed;
    t0   = env.drv.timeouts;
    gen.wr(32'h3C, 32'h13572468, 4'hF, 0, 0, 0);
    gen.wr(32'h00, 32'h0F0F0F0F, 4'hF, 0, 0, 0);
    gen.rd(32'h3C, 0, 0);
    gen.rd(32'h00, 0, 0);
    gen.wr(32'h08, 32'h2468ACE0, 4'hF, 0, 0, 3);
    gen.rd(32'h08, 0, 3);
    env.wait_done(base + gen.num_gen);
    repeat (5) @(posedge ACLK);
    env.scb.final_check(env.drv.completed - d0, env.drv.timeouts - t0,
                        env.mon.pend_wr(), env.mon.pend_rd(), env.mon.inc_wr());
  endtask

  // Isolated scored stimulus for mutant 13: two acknowledged writes advance
  // wr_n, then the third accepted write drops BVALID. Stop there so later
  // responses cannot be paired with the unanswered request.
  task automatic run_mut13_drop_b();
    generator    gen;
    int unsigned base, d0, t0;

    viol_mon::set_ctx($sformatf("mut13_drop_b,seed=%0d", seed));
    env.scb.clear_stats();
    dprobe.clear();
    env.sig = 0;
    env.drv.flt_aw_chg = 0;
    env.scb.skip_rd = 0;

    base = env.checked;
    d0   = env.drv.completed;
    t0   = env.drv.timeouts;
    gen = new(env.g2d, seed + 413, depth);
    gen.wr(32'h00, 32'h13572468, 4'hF, 0, 0, 0);
    gen.wr(32'h04, 32'h2468ACE0, 4'hF, 0, 0, 0);
    gen.wr(32'h08, 32'hCAFEF00D, 4'hF, 0, 0, 0);

    env.wait_done(base + gen.num_gen);
    repeat (5) @(posedge ACLK);
    env.scb.final_check(env.drv.completed - d0, env.drv.timeouts - t0,
                        env.mon.pend_wr(), env.mon.pend_rd(), env.mon.inc_wr());
    env.scb.limit_check(LAT_LIMIT);
    viol_mon::set_ctx("between_tests");
  endtask

  // Isolated scored stimulus for mutant 1: keep BREADY low long enough to
  // sample the one-cycle BVALID withdrawal, then accept the recovered response
  // and stop before later traffic can build on a failed response wait.
  task automatic run_mut1_bvalid_withdraw();
    generator    gen;
    int unsigned base, d0, t0;

    viol_mon::set_ctx($sformatf("mut1_bvalid_withdraw,seed=%0d", seed));
    env.scb.clear_stats();
    dprobe.clear();
    env.sig = 0;
    env.drv.flt_aw_chg = 0;
    env.scb.skip_rd = 0;

    base = env.checked;
    d0   = env.drv.completed;
    t0   = env.drv.timeouts;
    gen = new(env.g2d, seed + 411, depth);
    gen.wr(32'h00, 32'hB1A70001, 4'hF, 0, 0, 5);

    env.wait_done(base + gen.num_gen);
    repeat (5) @(posedge ACLK);
    env.scb.final_check(env.drv.completed - d0, env.drv.timeouts - t0,
                        env.mon.pend_wr(), env.mon.pend_rd(), env.mon.inc_wr());
    env.scb.limit_check(LAT_LIMIT);
    viol_mon::set_ctx("between_tests");
  endtask

  // Isolated scored stimulus for mutant 14: two normal reads advance rd_n,
  // then the third accepted AR drops RVALID. Stop before any later R response
  // can be paired with the unanswered request.
  task automatic run_mut14_drop_r();
    generator    gen;
    int unsigned base, d0, t0;

    viol_mon::set_ctx($sformatf("mut14_drop_r,seed=%0d", seed));
    env.scb.clear_stats();
    dprobe.clear();
    env.sig = 0;
    env.drv.flt_aw_chg = 0;
    env.scb.skip_rd = 0;

    base = env.checked;
    d0   = env.drv.completed;
    t0   = env.drv.timeouts;
    gen = new(env.g2d, seed + 414, depth);
    gen.rd(32'h00, 0, 0);
    gen.rd(32'h04, 0, 0);
    gen.rd(32'h08, 0, 0);

    env.wait_done(base + gen.num_gen);
    repeat (5) @(posedge ACLK);
    env.scb.final_check(env.drv.completed - d0, env.drv.timeouts - t0,
                        env.mon.pend_wr(), env.mon.pend_rd(), env.mon.inc_wr());
    env.scb.limit_check(LAT_LIMIT);
    viol_mon::set_ctx("between_tests");
  endtask

  // Exercise AW capacity through the ordinary driver, then read both locations
  // through the ordinary generator/monitor/scoreboard path. Reset flushes the
  // intentionally incomplete mutant transaction after its observable effect.
  task automatic run_second_aw_probe(input int probe_mutid, output bit case_ok);
    generator gen;
    int unsigned base, rec_base, s06_count;
    bit accepted_early, probe_ok;
    string failure;
    case_ok = 1'b0;
    mut_init(probe_mutid);
    base = env.checked;
    rec_base = viol_mon::nrec();
    viol_mon::set_ctx("second_aw_probe");
    env.drv.probe_second_aw(32'h20, 32'h24, 32'h13579BDF, 32'h2468ACE0,
                            probe_ok, accepted_early, failure);
    if (!probe_ok) begin
      $display("AWPROBE,mutid=%0d,accepted_while_pending=%0d,FAIL,reason=%s",
               probe_mutid, accepted_early, failure);
    end else begin
      gen = new(env.g2d, seed + 417, depth);
      gen.rd(32'h20, 0, 0);
      gen.rd(32'h24, 0, 0);
      env.wait_done(base + gen.num_gen);
      repeat (3) @(posedge ACLK);
      s06_count = 0;
      for (int i = rec_base; i < viol_mon::nrec(); i++)
        if (viol_mon::recs[i].det == "S06" && viol_mon::recs[i].cat == V_DATA_MISMATCH)
          s06_count++;
      case_ok = (probe_mutid == 17)
                ? (accepted_early && s06_count == 2)
                : (!accepted_early && s06_count == 0);
      $display("AWPROBE,mutid=%0d,accepted_while_pending=%0d,S06_count=%0d,%s",
               probe_mutid, accepted_early, s06_count, case_ok ? "PASS" : "FAIL");
      // The mutant's overwrite changes memory as well as handshake state.
      // Reset clears the partial request; ordinary writes restore both words
      // in the DUT and reference model before any following test can observe it.
      do_reset();
      env.drv.reset_bus();
      base = env.checked;
      gen = new(env.g2d, seed + 418, depth);
      gen.wr(32'h20, 32'h0, 4'hF, 0, 0, 0);
      gen.wr(32'h24, 32'h0, 4'hF, 0, 0, 0);
      env.wait_done(base + gen.num_gen);
      repeat (3) @(posedge ACLK);
    end
    if (!probe_ok) begin
      do_reset();
      env.drv.reset_bus();
    end
    viol_mon::set_ctx("between_tests");
  endtask

  // Validation phase: does the mutation fire (trig) and change DUT pins (pdiff) under an
  // exposure stimulus? Detection is NOT evaluated here: concurrent assertions of the two
  // protocol checkers are switched off for this phase only (to keep the log small) and are
  // switched on again before the evaluation phase. Records made here are ignored.
  task automatic mut_validate(input int id, output int unsigned vt, output int unsigned vp);
    mut_init(id);
    $assertoff(0, chk);
    $assertoff(0, dchk);
    run_test(lib.find("t_directed"));
    run_test(lib.find("t_boundary"));
    run_test(lib.find("t_strobe"));
    run_expose();
    run_test(lib.find("t_reset_live"));
    if (id == 17) begin
      bit ctl_ok, mut_ok;
      run_second_aw_probe(0, ctl_ok);
      run_second_aw_probe(17, mut_ok);
      if (!ctl_ok || !mut_ok) $display("AWPROBE validation failed ctl=%0d mutant=%0d", ctl_ok, mut_ok);
    end
    $asserton(0, chk);
    $asserton(0, dchk);
    vt = dut.m_trig;
    vp = dut.m_pdiff;
  endtask

  function automatic bit mut_range_has_expected(input int unsigned lo,
      input int unsigned hi, input string edet, input string ech, input vcat_e ecat);
    vrec_t r;
    for (int unsigned i = lo; i < hi; i++) begin
      r = viol_mon::recs[i];
      if (mut_expected_record(r, edet, ech, ecat)) return 1'b1;
    end
    return 1'b0;
  endfunction

  task automatic run_mutant(input int id);
    string       edet, ech, got, view, cls, reason;
    string       lat_pin_s, lat_win_s, lat_expected_pin_s, lat_expected_win_s;
    vcat_e       ecat;
    mut_diag_result_t diag;
    int unsigned base, nr, first_test, expected_test, vt, vp, tr, pd;
    int unsigned rec_before;
    string       detect_stage, expected_stage;
    bit          val_inv, ctl, probe_contract_ok;
    time         t_start;

    ctl   = (id == 0);
    edet  = mut_edet(id);  ech = mut_ech(id);  ecat = mut_ecat(id);
    vt = 0; vp = 0;
    if (!ctl && mut_val != 0) mut_validate(id, vt, vp);

    if (id == 1 || id == 13 || id == 14) begin
      u_shim.cfg_aw = 0; u_shim.cfg_w = 0; u_shim.cfg_ar = 0;
      u_shim.cfg_b = 0;  u_shim.cfg_r = 0; u_shim.cfg_seed = seed;
      u_shim.cfg_fault = 0;
    end
    mut_init(id);
    base       = viol_mon::nrec();
    t_start    = $time;
    first_test = 0;
    expected_test = 0;
    detect_stage = "none";
    expected_stage = "none";
    probe_contract_ok = 1'b1;
    if (id == 17) begin
      bit ctl_ok, mut_ok;
      run_second_aw_probe(0, ctl_ok);
      if (!ctl_ok) ctrl_ok = 1'b0;
      probe_contract_ok = ctl_ok;
      base = viol_mon::nrec();
      t_start = $time;
      run_second_aw_probe(17, mut_ok);
      probe_contract_ok &= mut_ok;
      if (!mut_ok) $display("AWPROBE mutant case failed despite mutation evaluation");
      if (viol_mon::nrec() > base) begin
        first_test = 1;
        detect_stage = "second_aw_probe";
      end
      if (mut_range_has_expected(base, viol_mon::nrec(), edet, ech, ecat)) begin
        expected_test = 1; expected_stage = "second_aw_probe";
      end
    end
    if (id == 1) begin
      rec_before = viol_mon::nrec();
      run_mut1_bvalid_withdraw();
      if (viol_mon::nrec() > rec_before) begin
        first_test = 1;
        detect_stage = "mut1_bvalid_withdraw";
      end
      if (mut_range_has_expected(rec_before, viol_mon::nrec(), edet, ech, ecat)) begin
        expected_test = 1; expected_stage = "mut1_bvalid_withdraw";
      end
    end else if (id == 13) begin
      rec_before = viol_mon::nrec();
      run_mut13_drop_b();
      if (viol_mon::nrec() > rec_before) begin
        first_test = 1;
        detect_stage = "mut13_drop_b";
      end
      if (mut_range_has_expected(rec_before, viol_mon::nrec(), edet, ech, ecat)) begin
        expected_test = 1; expected_stage = "mut13_drop_b";
      end
    end else if (id == 14) begin
      rec_before = viol_mon::nrec();
      run_mut14_drop_r();
      if (viol_mon::nrec() > rec_before) begin
        first_test = 1;
        detect_stage = "mut14_drop_r";
      end
      if (mut_range_has_expected(rec_before, viol_mon::nrec(), edet, ech, ecat)) begin
        expected_test = 1; expected_stage = "mut14_drop_r";
      end
    end else if (probe_contract_ok && (id != 17 || mut_full != 0 || detect_stage == "none")) begin
      foreach (lib.list[i]) begin
        rec_before = viol_mon::nrec();
        run_test(lib.list[i]);
        if (viol_mon::nrec() > rec_before && detect_stage == "none") begin
          first_test = i + 1;
          detect_stage = lib.list[i].name;
        end
        if (expected_test == 0 && mut_range_has_expected(rec_before, viol_mon::nrec(), edet, ech, ecat)) begin
          expected_test = i + 1;
          expected_stage = lib.list[i].name;
        end
        if (first_test != 0 && mut_full == 0 && !ctl) break;
      end
    end
    tr = dut.m_trig;
    pd = dut.m_pdiff;
    nr = viol_mon::nrec() - base;
    classify_mut_records(id, edet, ech, ecat, base, nr, diag);
    got = diag.got; view = diag.view;

    val_inv = (!ctl && mut_val != 0 && vt > 0 && vp == 0);
    reason  = "-";
    cls = mutation_class(ctl, probe_contract_ok, nr, tr, pd, val_inv,
                         diag.expected_seen, diag.primary_match,
                         diag.unexp_secondary_records, diag.unallowed_primary_count, reason);
    if (ctl) begin
      if (cls == "CONTROL_FAIL") ctrl_ok = 1'b0;
    end else begin
      case (cls)
        "KILLED": c_kill++;
        "NOISY": c_noisy++;
        "MISDIAGNOSED": c_mis++;
        "MISSED": c_miss++;
        "AMBIGUOUS": c_ambig++;
        "NOT_EXERCISED": c_nex++;
        "INVALID_MUTANT": c_inv++;
        default: ;
      endcase
      // These denominator-based rates are computed from the same outcome set
      // as MUTSUM. Record detection, tuple presence and primary correctness
      // remain distinct observations.
      if (cls == "KILLED" || cls == "NOISY" || cls == "MISDIAGNOSED" ||
          cls == "MISSED" || cls == "AMBIGUOUS") begin
        if (nr > 0) c_recorded++;
        if (diag.expected_seen) c_expected_seen++;
        if (diag.primary_match) c_primary_match++;
      end
    end

    lat_win_s = elapsed_cycles(diag.have_first, t_start, diag.first_t);
    lat_pin_s = elapsed_cycles(diag.have_first && (dut.m_tdiff != 0),
                               time'(dut.m_tdiff), diag.first_t);
    lat_expected_win_s = elapsed_cycles(diag.have_expected, t_start, diag.expected_t);
    lat_expected_pin_s = elapsed_cycles(diag.have_expected && (dut.m_tdiff != 0),
                                        time'(dut.m_tdiff), diag.expected_t);

`ifdef MUT_TRACE
    $display("MUTTRACE_FINAL,id=%0d,base=%0d,nr=%0d,sec_out='%s',unexp_sec=%0d,unexp_out='%s'",
             id, base, nr, diag.sec_out, diag.unexp_identities, diag.unexp_out);
`endif
    $display("MUTRES,id=%0d,name=%s,exp=%s/%s/%s,got=%s,detected=%0d,det_ok=%0d,ch_ok=%0d,cat_ok=%0d,sec=%s,unexp_sec=%0d,unexp_ids=%s,trig=%0d,pdiff=%0d,val_trig=%0d,val_pdiff=%0d,nrec=%0d,tests_to_detect=%0d,detected_in=%s,lat_pin_cyc=%s,lat_win_cyc=%s,view=%s,class=%s,reason=%s,expected_seen=%0d,primary_match=%0d,primary_diag=%s,primary_count=%0d,secondary_records=%0d,unexp_secondary_records=%0d,lat_expected_pin_cyc=%s,lat_expected_win_cyc=%s,expected_test=%0d,expected_in=%s",
             id, mut_name(id), edet, ech, viol_mon::cname(ecat), got, (nr > 0) ? 1 : 0,
             diag.det_ok, diag.ch_ok, diag.cat_ok, diag.sec_out, diag.unexp_identities,
             diag.unexp_out, tr, pd, vt, vp, nr, first_test, detect_stage,
             lat_pin_s, lat_win_s, view, cls, reason, diag.expected_seen,
             diag.primary_match, diag.primary_diag, diag.primary_count,
             diag.secondary_records, diag.unexp_secondary_records,
             lat_expected_pin_s, lat_expected_win_s, expected_test, expected_stage);
  endtask

  function automatic string pct(int unsigned n, int unsigned d);
    if (d == 0) return "n/a";
    return $sformatf("%0d/%0d=%0.1f%%", n, d, 100.0 * real'(n) / real'(d));
  endfunction

  task automatic run_mutsweep();
    int unsigned den, lo, n_run;
    viol_mon::quiet = (mut_verbose == 0);
    rt_quiet        = (mut_verbose == 0);
    c_kill = 0; c_noisy = 0; c_mis = 0; c_miss = 0; c_ambig = 0; c_nex = 0; c_inv = 0;
    c_recorded = 0; c_expected_seen = 0; c_primary_match = 0;
    run_mutant(0);                                    // control first, always full regress
    lo = (mut_first < 1) ? 1 : mut_first;
    n_run = 0;
    for (int id = lo; id <= mut_last && id <= N_MUT; id++) begin
      run_mutant(id);
      n_run++;
    end
    den = c_kill + c_noisy + c_mis + c_miss + c_ambig;
    $display("MUTSUM dut=rtlmut seed=%0d range=%0d..%0d mutants=%0d control=%s killed=%0d noisy=%0d misdiagnosed=%0d missed=%0d ambiguous=%0d not_exercised=%0d invalid=%0d full=%0d val=%0d records=%0d expected_seen=%0d primary_match=%0d",
             seed, lo, mut_last, n_run, ctrl_ok ? "OK" : "FAIL",
             c_kill, c_noisy, c_mis, c_miss, c_ambig, c_nex, c_inv, mut_full, mut_val,
             c_recorded, c_expected_seen, c_primary_match);
    $display("MUTRATE den=%0d (classified outcomes; excludes not_exercised=%0d invalid=%0d and control) detection_rate=%s expected_diag_rate=%s primary_diag_rate=%s clean_kill_rate=%s ambiguous_rate=%s misdiag_rate=%s noise_rate=%s",
             den, c_nex, c_inv,
             pct(c_recorded, den), pct(c_expected_seen, den),
             pct(c_primary_match, den), pct(c_kill, den),
             pct(c_ambig, den), pct(c_mis, den), pct(c_noisy, den));
    viol_mon::quiet = 1'b0;
    rt_quiet        = 1'b0;
  endtask
