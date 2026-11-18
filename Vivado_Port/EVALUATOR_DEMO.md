# Evaluator demonstration: AXI4-Lite verification in Vivado/XSim

## Using this guide

Plan for **nine minutes**, excluding preparation. Commands are for **Windows CMD**, not PowerShell. Paste no visible prompt. Execute each block separately and check the immediately printed return code before continuing. Unless explicitly testing failure, expect exit 0 and stop on a nonzero result. Redirected simulations can show **no output while running**: wait for CMD to return. Do not run concurrent simulations or simultaneous XSim builds in this directory.

New presentation output belongs in **demo_logs**. Never overwrite `check_logs/verified_*`. Rehearsals overwrite only the named demo logs; archive demo_logs first if necessary. Expected fields below were checked against current sources, runners, and saved seed-7/seed-1 logs. Writing this guide did not run new simulations. Call each result **live** only after executing its command; call existing check_logs results **saved evidence**. Historical README cycle figures are not this demonstration's baseline. See [VALIDATION_PATCH.md](VALIDATION_PATCH.md) for provenance.

## Preparation before the presentation

Use the installed Vivado 2026.1 environment if tools are not on PATH. The runners first look in `C:\AMDDesignTools\2026.1\Vivado\bin`. Build the port, not the root EDA Playground implementation. Run this block, then inspect `COMPILE_EXIT` before continuing:

```cmd
cd /d "C:\AXI4-Lite Compliance Checker\Vivado_Port"
if not exist "demo_logs" mkdir "demo_logs"
call scripts\compile_xsim.bat > "demo_logs\compile.log" 2>&1
echo COMPILE_EXIT=%ERRORLEVEL%
findstr /L /C:"[INFO] Compilation successful." "demo_logs\compile.log"
```

After exit 0, elaborate:

```cmd
cd /d "C:\AXI4-Lite Compliance Checker\Vivado_Port"
call scripts\elaborate_xsim.bat > "demo_logs\elaborate.log" 2>&1
echo ELABORATE_EXIT=%ERRORLEVEL%
findstr /L /C:"Built simulation snapshot axi4l_sim" /C:"[INFO] Elaboration successful:" "demo_logs\elaborate.log"
```

Expect exit 0, `[INFO] Compilation successful.`, `Built simulation snapshot axi4l_sim`, and `[INFO] Elaboration successful: snapshot axi4l_sim generated.` Scoped assertion-control warnings are documented XSim limitations; inspect other warnings/errors. Build success is not runtime verification. Recompile **and** elaborate after any HDL change; never use a stale snapshot to claim success.

Pre-open `TB/testbench.sv`, `TB/assertions.sv`, `TB/driver.sv`, `TB/test.sv`, `TB/mutant_tasks.sv`, `VALIDATION_PATCH.md`, and this guide in your editor. Bookmark the symbols below. Rehearse launch time and terminal readability on the presentation machine.

## Nine-minute core demonstration

### 1. Introduction — 0:00-0:45 (45 seconds)

**Show:** project title and `Design/interface.sv`.

**Say:** “This project checks an AXI4-Lite slave under normal traffic, delayed requests and response backpressure. A transfer happens only when VALID and READY are high on the same clock edge. While waiting, VALID must remain asserted and its payload must stay stable. Timing can be legal while data is wrong, so I also compare observed transactions with a reference model. Backpressure matters because a design that works when READY is always high can fail when the receiver pauses.”

```cmd
cd /d "C:\AXI4-Lite Compliance Checker\Vivado_Port"
type "Design\interface.sv"
echo SOURCE_DISPLAY_EXIT=%ERRORLEVEL%
```

**Expected:** exit 0 and five channel groups: AWADDR/AWVALID/AWREADY; WDATA/WSTRB/WVALID/WREADY; BRESP/BVALID/BREADY; ARADDR/ARVALID/ARREADY; RDATA/RRESP/RVALID/RREADY, plus clock/reset and modports. This is source inspection, not a runtime verdict.

**Proves / limit:** identifies the contract checked; does not establish exhaustive compliance.

**Transition:** “Here is how the environment observes and checks that contract.”

### 2. Architecture — 0:45-2:00 (75 seconds)

**Show:** this diagram, then source anchors from the table.

```text
Generator -> Driver -> bus interface -> Latency shim -> dbus -> Selected DUT
                          |                             |
                 passive monitor + chk          passive dmon + dchk
                          |                             |
                scoreboard/reference model        latency probe
                          |
                  coverage and violation reports
```

Responses return through the shim. Both checkers share `viol_mon`; assertion-fault tests also have a separate `fbus/fchk`.

| Exact file | Symbol or code to open |
|---|---|
| `TB/testbench.sv` | `bus`, `dbus`, `dut`, `u_shim`, `chk`, `dchk`; DUT/model selection; `run_test`, `run_closure` |
| `TB/generator.sv` | `wr`, `rd`, directed methods, `rand_traffic` |
| `TB/driver.sv` | `drive_aw`, `drive_w`, `drive_read`, `wait_b`, `wait_r`, `run`, `recovery_needed` |
| `Design/interface.sv` | `axi4l_if`, channel signals and modports |
| `TB/latency_injector.sv` | `axi4l_shim`, `cfg_aw/cfg_w/cfg_ar/cfg_b/cfg_r` |
| `Design/dut_sel.sv` | `dut_sel`, request gating and response mux |
| `TB/monitor.sv` | `monitor.run`, `obs_txn.c_req/c_vld/c_rsp`, pending queues |
| `TB/assertions.sv` | `a01/a03/a05/a07/a09` persistence; `a02/a04/a06/a08/a10` payload stability |
| `TB/scoreboard.sv` | `ref_model`, `ram_model`, `check_write`, `check_read`, `final_check` |
| `TB/gpio_model.sv` | `gpio_model.do_write`, `do_read`, `on_reset` |
| `TB/environment.sv` | `start`, `drain_loop`, `wait_done`, `scoreboard2` |
| `TB/coverage.sv` | `cov_collector`, `gname/ghit`, covergroups, `report` |
| `TB/violation_monitor.sv` | `viol_mon.report`, detector/channel/category records |

**Say:** “The driver creates pin activity. The shim controls timing independently of the DUT. Passive monitors reconstruct actual handshakes, so checking does not simply trust driver intent. Assertions check cycle-level rules; the reference model checks data and response semantics. Coverage records scenarios, and the violation monitor gives diagnostics stable identities.”

```cmd
cd /d "C:\AXI4-Lite Compliance Checker\Vivado_Port"
findstr /N /L /C:"dut_sel    dut" /C:"axi4l_shim u_shim" /C:"axi4l_checker chk" /C:"env = new" "TB\testbench.sv"
echo ARCHITECTURE_ANCHORS_EXIT=%ERRORLEVEL%
```

**Expected:** exit 0 and source lines instantiating DUT, shim, checker and shared environment; not runtime PASS output. In top-level selection, RAM uses `ram_model`, depth 16; GPIO uses `gpio_model`, depth 8. Shared: driver, monitor, assertions, scoreboard framework, shim and test library. Changed per DUT: selection, address range, functional model and reset semantics. GPIO input is tied to `32'hA5C30F1E` in `Design/dut_sel.sv`.

**Proves / limit:** protocol checking is separated from DUT behavior. A new peripheral still needs an appropriate model, map/configuration and measured timing expectations; reuse is not universal plug-and-play support.

**Transition:** “First I will establish that golden RAM passes the complete configured regression.”

### 3. Golden RAM regression — 2:00-3:15 (75 seconds)

**Show:** live filtered summary, then one `RESULT` and `DLAT` pair. If asked, `TB/test.sv:test_lib.new` lists the 14 tests.

**Say:** “This is a new live run with base seed seven. The suite combines directed, boundary, strobe, random, latency, request-delay and reset tests. Individual tests derive seeds from the base seed. I check the test totals and the final verdict.”

```cmd
cd /d "C:\AXI4-Lite Compliance Checker\Vivado_Port"
call scripts\run_xsim.bat "-testplusarg" "TEST=regress" "-testplusarg" "DUT=ram" "-testplusarg" "SEED=7" > "demo_logs\ram_s7.log" 2>&1
echo RAM_EXIT=%ERRORLEVEL%
findstr /B /L /C:"REGRESS " /C:"GLOBAL " /C:"STAGE9 mode=" /C:"CAMPAIGN PASS" "demo_logs\ram_s7.log"
```

**Expected:** `RAM_EXIT=0` and these saved reference lines:

```text
REGRESS dut=ram tests=14 pass=14 fail=0 goals_hit=49/49
STAGE9 mode=regress dut=ram seed=7 mut=0 cycles=10779 PASS
CAMPAIGN PASS
```

`GLOBAL` should report `unexpected_total=0`, isolation counts zero, `iso_metric_oracle=PASS`, `dut_facing=0`, `inj_mismatch=0`.

```cmd
cd /d "C:\AXI4-Lite Compliance Checker\Vivado_Port"
findstr /B /L /C:"HDR," /C:"RESULT,t_directed," /C:"DLAT,t_directed," /C:"DLAT,t_lat5," "demo_logs\ram_s7.log"
```

**Say:** “Slash-separated latencies are minimum, average and maximum in cycles. L1 runs from request acceptance to first response VALID; for writes the request point is the later AW/W handshake. L2 is first response VALID to response handshake. L3 is request to response handshake. Zero injected response delay gives DUT L1 of two cycles for writes and one for reads. Backpressure can increase completion latency without increasing first-VALID latency.”

Saved `DLAT,t_directed` fields are `dut_wrL1=2/2.00/2,dut_rdL1=1/1.00/1,inj_wr=ok,inj_rd=ok`. `RESULT` includes generated/accepted/completed counts, timeouts, mismatches, violations, goals and status. The 49 goals are custom functional goals, not code coverage.

**Proves / limit:** these 14 tests pass at this seed with tracked goals hit and zero unexpected diagnostics. It does not cover all orderings, addresses or data. If cycles differ, inspect the manifest, configuration and snapshot before quoting saved figures.

**Transition:** “Now I will reuse the checking environment on a GPIO register peripheral.”

### 4. GPIO reuse — 3:15-4:05 (50 seconds)

**Show:** GPIO summary beside RAM and optionally `gpio_model`.

**Say:** “I select GPIO rather than replace the protocol environment. Its model changes because it has registers, fixed input data and different reset behavior. The shared protocol and transaction paths remain in use.”

```cmd
cd /d "C:\AXI4-Lite Compliance Checker\Vivado_Port"
call scripts\run_xsim.bat "-testplusarg" "TEST=regress" "-testplusarg" "DUT=gpio" "-testplusarg" "SEED=7" > "demo_logs\gpio_s7.log" 2>&1
echo GPIO_EXIT=%ERRORLEVEL%
findstr /B /L /C:"REGRESS " /C:"GLOBAL " /C:"STAGE9 mode=" /C:"CAMPAIGN PASS" "demo_logs\gpio_s7.log"
```

**Expected:** `GPIO_EXIT=0`, zero unexpected/isolation diagnostics, and:

```text
REGRESS dut=gpio tests=14 pass=14 fail=0 goals_hit=49/49
STAGE9 mode=regress dut=gpio seed=7 mut=0 cycles=10747 PASS
CAMPAIGN PASS
```

**Proves / limit:** reuse across these two DUTs, not arbitrary peripherals. Register side effects and new maps require model adaptation. Shared boundary traffic is interpreted using each model's range; GPIO is not assumed to behave like RAM.

**Transition:** “Passing good designs is necessary; next I will show detection and diagnosis of an actual RTL defect.”

### 5. Focused RTL mutant M05 — 4:05-6:05 (2 minutes)

**Show:** `Design/axi4_lite_ram_mutlib.sv` at the M5 comment, `TB/assertions.sv:a09`, and the new result.

**Say:** “Mutant five withdraws RVALID for one cycle while RREADY is low. The source must hold VALID until acceptance. A09 checks that a stalled response remains valid on the following sampled edge. This is an RTL mutation, not simply a corrupted scoreboard expectation.”

```cmd
cd /d "C:\AXI4-Lite Compliance Checker\Vivado_Port"
call scripts\run_xsim.bat "-testplusarg" "MUTSWEEP=1" "-testplusarg" "MUTFIRST=5" "-testplusarg" "MUTLAST=5" "-testplusarg" "MUTFULL=1" "-testplusarg" "SEED=7" > "demo_logs\m05_s7.log" 2>&1
echo M05_CAMPAIGN_EXIT=%ERRORLEVEL%
findstr /B /L /C:"MUTRES,id=5," /C:"MUTSUM " /C:"CAMPAIGN PASS" "demo_logs\m05_s7.log"
```

**Expected:** exit 0. On the single long `MUTRES` line: `name=rvalid_withdraw`, `exp=A09/R/VALID_WITHDRAWAL`, `got=A09/D:R/VALID_WITHDRAWAL`, `view=BOTH`, `class=KILLED`, `expected_seen=1`, `primary_match=1`, `primary_diag=A09/R/VALID_WITHDRAWAL`, `unexp_secondary_records=0`. Saved summary:

```text
MUTSUM dut=rtlmut seed=7 range=5..5 mutants=1 control=  OK killed=1 noisy=0 misdiagnosed=0 missed=0 ambiguous=0 not_exercised=0 invalid=0 full=1 val=1 records=1 expected_seen=1 primary_match=1
CAMPAIGN PASS
```

The two spaces before OK are formatting. MUTSWEEP selects rtlmut automatically and first runs the unmodified control. MUTFULL=1 runs M05 through the ordinary regression instead of stopping at its first detecting test. Default mutation output suppresses ordinary RESULT/DLAT lines; the full log still contains intentional assertion reports.

**Say:** “Detected means a scored diagnostic exists. expected_seen means the frozen expected detector/channel/category tuple occurred. primary_match means that tuple belongs to the earliest diagnostic timestamp. D:R and R normalize to the same logical channel. KILLED requires the expected primary diagnosis with no disallowed competing diagnostics. Merely triggering the mutation is not a kill.”

Allowed co-primary tuples do not automatically cause ambiguity: an **unallowed** co-primary tuple does. Disallowed later secondary records cause NOISY. The checker reports remain visible; an allowlist does not erase them. See `TB/mutant_tasks.sv:classify_mut_records`, `mutation_class`, `run_mutant`, `run_mutsweep`.

**Say:** “An ordinary test is expected to fail on defective RTL. The mutation campaign succeeds when its control passes and selected defects receive the required KILLED classification. Intentional assertion reports therefore coexist with campaign exit zero. A failed final mutation policy returns nonzero; the sweep does not abort at its first detected defect.”

**Proves / limit:** this fault is exercised and correctly diagnosed; not all possible RTL bugs. Scored `trig/pdiff` describe activation/pin-difference observations. `val_trig/val_pdiff` belong to separate exposure validation; validation records are excluded from scoring. Saved focused M05 has `trig=445,pdiff=445,val_trig=19,val_pdiff=19`; these are not 445 independent defect types.

#### Separately labeled M09 alias explanation (20 seconds within step 5)

**Show:** `TB/testbench.sv:run_test`, immediately before `gen.directed_basic()`.

**Say:** “M09 corrupts word fifteen when word zero is written. The scored directed path writes 0x13579BDF with full strobes to address 0x3C, writes 0x2468ACE0 to address zero, then reads 0x3C before another write can mask the corruption. These use the normal generator, driver, monitor and scoreboard. Golden control passes the same stimulus.”

Display **saved**, not live, M09 evidence:

```cmd
cd /d "C:\AXI4-Lite Compliance Checker\Vivado_Port"
findstr /B /L /C:"MUTRES,id=9," /C:"MUTSUM " "check_logs\verified_m09_s7.log"
echo SAVED_M09_FILTER_EXIT=%ERRORLEVEL%
```

Expected filter exit 0, `exp=S06/R/DATA_MISMATCH`, `class=KILLED`, `expected_seen=1`, `primary_match=1`, scored `trig=11,pdiff=48` and separately `val_trig=4,val_pdiff=6`. This illustrates functional checking of a timing-legal transaction, not a new live M09 run.

**Transition:** “Now I will compare the full regression with a smaller selection closing the same tracked goals.”

### 6. Coverage-driven closure — 6:05-7:20 (75 seconds)

**Show:** `TB/testbench.sv:run_closure`, `TB/test.sv:gap_test`, then closure and RAM summaries.

**Say:** “Closure starts with the directed test, examines missing goals, and uses a fixed gap-to-test map to select more tests. It deduplicates names and repeats in a bounded loop. This is gap-driven selection, not AI or adaptive stimulus generation.”

```cmd
cd /d "C:\AXI4-Lite Compliance Checker\Vivado_Port"
call scripts\run_xsim.bat "-testplusarg" "TEST=closure" "-testplusarg" "DUT=ram" "-testplusarg" "SEED=7" > "demo_logs\closure_s7.log" 2>&1
echo CLOSURE_EXIT=%ERRORLEVEL%
findstr /B /L /C:"CLOSURE " /C:"REGRESS " /C:"STAGE9 mode=" /C:"CAMPAIGN PASS" "demo_logs\closure_s7.log"
findstr /B /L /C:"STAGE9 mode=" "demo_logs\ram_s7.log" "demo_logs\closure_s7.log"
```

**Expected:** exit 0 and:

```text
CLOSURE iter=0 goals_hit=35/49 picked=5
CLOSURE run t_rand_big
CLOSURE run t_lat1
CLOSURE run t_lat2
CLOSURE run t_lat5
CLOSURE run t_lat10
CLOSURE iter=1 goals_hit=49/49 picked=0
REGRESS dut=ram tests=6 pass=6 fail=0 goals_hit=49/49
STAGE9 mode=closure dut=ram seed=7 mut=0 cycles=6385 PASS
CAMPAIGN PASS
```

**Say:** “At the same base seed, RAM regression uses 10,779 cycles and closure uses 6,385. The reduction is (10,779 minus 6,385) divided by 10,779 times 100, or **40.76%**. This measures simulation cycles, not wall-clock speedup. Totals include the runner's reset and overhead cycles.”

The **49 custom functional goals** cover selected scenarios such as strobes, response classes, address regions, latency ranges, ordering/backpressure and reset. Native covergroups/crosses also exist. `49/49` is neither every native coverage bin nor RTL statement/branch/toggle coverage. Do not call it 100% code coverage.

**Proves / limit:** equal coverage of these tracked goals with fewer cycles at seed 7. Six tests omit scenarios and random histories from the fourteen-test suite. Equal tracked-goal coverage does **not** make closure equivalent to full regression or exhaustive verification.

**Transition:** “The live examples are small; saved validation shows the complete campaign at two seeds.”

### 7. Full validation evidence — 7:20-8:35 (75 seconds)

**Show:** `VALIDATION_PATCH.md`, saved full summaries and exit CSV. State **saved evidence**, as distinct from newly executed demo_logs.

**Say:** “These are retained validation results, not full sweeps executed during this presentation. Both seeds one and seven ran the twenty-mutant campaign with MUTFULL enabled. The control passed, all twenty were killed, and every other classification count is zero.”

```cmd
cd /d "C:\AXI4-Lite Compliance Checker\Vivado_Port"
findstr /B /L /C:"MUTSUM " /C:"CAMPAIGN PASS" "check_logs\verified_full_s1.log" "check_logs\verified_full_s7.log"
echo SAVED_SWEEP_FILTER_EXIT=%ERRORLEVEL%
findstr /B /L /C:"NEGSUM " "check_logs\verified_neg_ram_s7.log" "check_logs\verified_neg_gpio_s7.log"
findstr /B /L /C:"FAULTSUM " "check_logs\verified_fault_s7.log"
findstr /B /L /C:"MUTCLASSSUM," /C:"RSTREQSUM," /C:"DRVRECSUM " "check_logs\verified_class_s7.log" "check_logs\verified_rstreq_s7.log" "check_logs\verified_recovery_s7.log"
type "check_logs\verified_exit_status.csv"
type "check_logs\finalization_summary_fixtures.csv"
```

**Expected at each seed:** `range=1..20 mutants=20 control=  OK killed=20 noisy=0 misdiagnosed=0 missed=0 ambiguous=0 not_exercised=0 invalid=0 full=1 val=1 records=20 expected_seen=20 primary_match=20`, followed by `CAMPAIGN PASS`. Filter exit 0 means saved matching lines exist, not that a new simulation ran. The CSV contains 30 cases; `ok=True` means exit matched expected success/failure.

| Saved evidence at both seeds (substitute 1 or 7 for S) | Expected summary |
|---|---|
| `verified_ram_sS.log`, `verified_gpio_sS.log` | Each 14/14 PASS, 49/49 goals |
| `verified_closure_sS.log` | 6/6 PASS, 49/49 goals |
| `verified_neg_ram_sS.log`, `verified_neg_gpio_sS.log` | Each run=9 detected=9 missed=0 PASS |
| `verified_fault_sS.log` | `FAULTSUM run=18 detected=18 missed=0 PASS` |
| `verified_class_sS.log` | `MUTCLASSSUM,PASS` |
| `verified_rstreq_sS.log` | `RSTREQSUM,cases=3,pass=3,PASS` |
| `verified_recovery_sS.log` | `DRVRECSUM cases=3 PASS` |
| `verified_invalid_sS.log` | Unknown TEST; recorded process exit 1 |
| `verified_fail_sS.log` | INJOUT=1 causes failed final verdict; exit 1 |
| `verified_watchdog_sS.log` | WATCHDOG_NS=1 expiry; exit 1 |
| `finalization_summary_fixtures.csv` | Missing summary: 1; missing verdict: 1; valid fixture: 0 |

Seed-1 cycles: RAM 10,757, GPIO 10,717, closure 6,382. Do not mix these with the seed-7 reduction calculation. `verified_source_sha256.csv` and `finalization_source_sha256.csv` identify source states; `finalization_evidence_audit.log` records the evidence cross-check. The wrapper requires both a mode summary and `CAMPAIGN PASS`, even if XSim returns zero after fatal/finish handling.

**Say:** “Negative suites check intentional faults. The assertion-fault suite uses an independent fault bus. Recovery checks cover reset during stalled requests and bounded timeout recovery. Their success means expected detection or recovery occurred, not that injected traffic was legal.”

**Proves / limit:** scoped, reproducible simulation evidence at two seeds and tested failure reporting. Twenty mutations are a finite fault model, not mathematical proof or exhaustive certification. This patch has XSim validation; no fresh Xcelium run is claimed.

**Transition:** “I will close with the contribution and the boundary of the claim.”

### Closing — 8:35-9:00 (25 seconds)

**Show:** diagram and golden/M05/closure summaries.

**Say:** “The contribution is an integrated, reusable simulation environment combining protocol assertions, observed-transaction data checking, timing perturbation, functional goals and mutation diagnosis. I demonstrated good RAM and GPIO implementations, a correctly diagnosed RTL fault, and smaller fixed-map coverage selection. The claims are limited to these DUTs, tests, goals and measured simulations. Further work is broader DUT models, fault classes, coverage and portability validation.”

## Three-minute fallback (saved evidence, no new simulation)

Say explicitly: “I am showing saved validation evidence, not claiming new simulation runs.”

- **0:00-0:40:** handshake explanation and architecture diagram.
- **0:40-1:20:** saved RAM/GPIO summaries; shared checks versus changed models.
- **1:20-2:10:** M05/A09; expected_seen, primary_match and KILLED.
- **2:10-2:40:** closure and full summaries; 40.76% is a seed-7 tracked-goal cycle comparison only.
- **2:40-3:00:** state limitations and deliver closing script.

```cmd
cd /d "C:\AXI4-Lite Compliance Checker\Vivado_Port"
findstr /B /L /C:"REGRESS " /C:"STAGE9 mode=" "check_logs\verified_ram_s7.log" "check_logs\verified_gpio_s7.log" "check_logs\verified_closure_s7.log"
echo SAVED_GOLDEN_FILTER_EXIT=%ERRORLEVEL%
findstr /B /L /C:"MUTRES,id=5," /C:"MUTSUM " "check_logs\verified_m05_s7.log"
echo SAVED_M05_FILTER_EXIT=%ERRORLEVEL%
findstr /B /L /C:"MUTSUM " "check_logs\verified_full_s1.log" "check_logs\verified_full_s7.log"
echo SAVED_FULL_FILTER_EXIT=%ERRORLEVEL%
```

Expected fields/limits are those in the core steps. Exit 0 means matching lines were found. No build or live snapshot is required for this fallback.

## Optional extended live demonstration (outside the nine minutes)

Complete preparation first. Show the newly named demo log, say its purpose, check the immediate exit and inspect the final summary. Time allowances include explanation and depend on the machine. Transition back to the saved evidence after each optional check. Never imply an omitted check ran live.

### Both DUT-path negative suites (about 45 seconds)

**Show:** `TB/testbench.sv:run_neg` and NEGSUM.

**Say:** “These nine intentional negative tests check whether the expected violations are reported without unexpected categories. They validate checker sensitivity, not correctness of faulty behavior.”

```cmd
cd /d "C:\AXI4-Lite Compliance Checker\Vivado_Port"
call scripts\run_xsim.bat "-testplusarg" "NEG=100" "-testplusarg" "DUT=ram" "-testplusarg" "SEED=7" > "demo_logs\neg_ram_s7.log" 2>&1
echo NEG_RAM_EXIT=%ERRORLEVEL%
findstr /B /L /C:"NEGRES," /C:"NEGSUM " /C:"CAMPAIGN PASS" "demo_logs\neg_ram_s7.log"
call scripts\run_xsim.bat "-testplusarg" "NEG=100" "-testplusarg" "DUT=gpio" "-testplusarg" "SEED=7" > "demo_logs\neg_gpio_s7.log" 2>&1
echo NEG_GPIO_EXIT=%ERRORLEVEL%
findstr /B /L /C:"NEGSUM " /C:"CAMPAIGN PASS" "demo_logs\neg_gpio_s7.log"
```

**Expected:** both exits 0; `NEGSUM dut=ram run=9 detected=9 missed=0 PASS` and equivalent `dut=gpio`. Expected assertion reports are allowed; missed detections/unexpected categories fail the policy. This checks only the implemented negative stimuli.

**Transition:** “The next check isolates assertion stimulus from the DUT.”

### Assertion faults (about 30 seconds)

**Show:** `TB/fault_tasks.sv:run_fault`, and `fbus/fchk` in the top.

**Say:** “A separate fault bus deliberately violates rules to test the assertions themselves. This is simulation-based assertion testing, not formal proof.”

```cmd
cd /d "C:\AXI4-Lite Compliance Checker\Vivado_Port"
call scripts\run_xsim.bat "-testplusarg" "FAULT=100" "-testplusarg" "SEED=7" > "demo_logs\fault_s7.log" 2>&1
echo FAULT_EXIT=%ERRORLEVEL%
findstr /B /L /C:"FAULTSUM " /C:"CAMPAIGN PASS" "demo_logs\fault_s7.log"
```

**Expected:** exit 0, `FAULTSUM run=18 detected=18 missed=0 PASS`, `CAMPAIGN PASS`. These are 18 implemented stimuli, not every temporal assertion corner case.

**Transition:** “Now I will show legal reset cancellation and bounded timeout recovery.”

### Reset and recovery (about 60 seconds)

**Show:** `TB/testbench.sv:run_rstreq_check`, `run_recovery_check`, runner recovery block; `TB/driver.sv:recovery_needed`.

**Say:** “Reset cancels stalled requests. A timeout must not illegally withdraw VALID in normal operation. The driver holds stalled requests until runner reset, pending diagnostics are recorded before flush, completion mailboxes continue draining, and queued work resumes. Fully accepted writes update the reference model; GPIO reset semantics use its model.”

```cmd
cd /d "C:\AXI4-Lite Compliance Checker\Vivado_Port"
call scripts\run_xsim.bat "-testplusarg" "RSTREQ=1" "-testplusarg" "DUT=ram" "-testplusarg" "SEED=7" > "demo_logs\rstreq_s7.log" 2>&1
echo RSTREQ_EXIT=%ERRORLEVEL%
findstr /B /L /C:"RSTREQ_CASE," /C:"RSTREQSUM," /C:"CAMPAIGN PASS" "demo_logs\rstreq_s7.log"
call scripts\run_xsim.bat "-testplusarg" "DRVREC=1" "-testplusarg" "DUT=ram" "-testplusarg" "SEED=7" > "demo_logs\recovery_s7.log" 2>&1
echo RECOVERY_EXIT=%ERRORLEVEL%
findstr /B /L /C:"RECOVERY " /C:"DRVRECSUM " /C:"CAMPAIGN PASS" "demo_logs\recovery_s7.log"
```

**Expected:** exits 0; `RSTREQSUM,cases=3,pass=3,PASS`; `DRVRECSUM cases=3 PASS`. RSTREQ cases cover stalled AW, W, AR: one abort, zero timeouts and two subsequent completions each. DRVREC intentionally lowers the driver bound for the probe; timeout/reset messages there are expected, followed by successful recovery. These finite checks do not prove absence of every reset/scheduling race.

**Transition:** “The full mutation campaign evaluates control behavior and diagnosis together.”

### Live full mutation sweep (allow 1-2 minutes)

**Show:** MUTSUM/MUTRATE and `TB/mutant_tasks.sv:run_mutsweep`.

**Say:** “This is a new full campaign, unlike the saved results shown earlier. All twenty selected mutants are evaluated before final policy. MUTFULL preserves the full ordinary sequence for mutants such as M05. Existing isolated probes remain for M01, M13 and M14, with a second-AW probe for M17. It is not correct to say every mutant runs exactly the same fourteen tests.”

```cmd
cd /d "C:\AXI4-Lite Compliance Checker\Vivado_Port"
call scripts\run_xsim.bat "-testplusarg" "MUTSWEEP=1" "-testplusarg" "MUTFIRST=1" "-testplusarg" "MUTLAST=20" "-testplusarg" "MUTFULL=1" "-testplusarg" "SEED=7" > "demo_logs\full_s7.log" 2>&1
echo FULL_MUTATION_EXIT=%ERRORLEVEL%
findstr /B /L /C:"MUTSUM " /C:"MUTRATE " /C:"CAMPAIGN PASS" "demo_logs\full_s7.log"
```

**Expected:** exit 0, control OK, killed=20, all other classification counts zero, full=1 (step 7 gives exact fields). A finite mutation library is not universal fault coverage. If time permits, run seed 1 **after** seed 7 finishes:

```cmd
cd /d "C:\AXI4-Lite Compliance Checker\Vivado_Port"
call scripts\run_xsim.bat "-testplusarg" "MUTSWEEP=1" "-testplusarg" "MUTFIRST=1" "-testplusarg" "MUTLAST=20" "-testplusarg" "MUTFULL=1" "-testplusarg" "SEED=1" > "demo_logs\full_s1.log" 2>&1
echo FULL_MUTATION_SEED1_EXIT=%ERRORLEVEL%
findstr /B /L /C:"MUTSUM " /C:"CAMPAIGN PASS" "demo_logs\full_s1.log"
```

Expected the same totals with seed=1 and exit 0. Avoid the umbrella `run_mutants_xsim.bat` in the timed demo: it rebuilds and runs both seeds.

**Transition:** “The result is strong for this fault model; the limits remain explicit.”

### Failure-exit checks (about 45 seconds; intentional failures)

**Show:** the immediately printed exits and each full log if asked.

**Say:** “Expected assertion diagnostics do not fail a successful negative campaign, but an invalid command or failed final policy must return nonzero. Missing required summaries also fail.”

```cmd
cd /d "C:\AXI4-Lite Compliance Checker\Vivado_Port"
call scripts\run_xsim.bat "-testplusarg" "TEST=does_not_exist" "-testplusarg" "SEED=7" > "demo_logs\invalid_s7.log" 2>&1
echo INVALID_EXPECT_1=%ERRORLEVEL%
call scripts\run_xsim.bat "-testplusarg" "TEST=regress" "-testplusarg" "DUT=ram" "-testplusarg" "INJOUT=1" "-testplusarg" "SEED=7" > "demo_logs\failed_campaign_s7.log" 2>&1
echo FAILED_CAMPAIGN_EXPECT_1=%ERRORLEVEL%
call scripts\run_xsim.bat "-testplusarg" "WATCHDOG_NS=1" "-testplusarg" "SEED=7" > "demo_logs\watchdog_s7.log" 2>&1
echo WATCHDOG_EXPECT_1=%ERRORLEVEL%
> "demo_logs\missing_summary.log" echo CAMPAIGN PASS
call scripts\check_xsim_summary.bat "demo_logs\missing_summary.log" "MUTSUM "
echo MISSING_SUMMARY_EXPECT_1=%ERRORLEVEL%
```

**Expected:** all four exits 1. The invalid log reports unknown TEST; INJOUT fails the final regression verdict; watchdog expires at 1 ns; the artificial fixture contains a final marker but no required mode summary. These are deliberate failures only in this labeled step. Missing summaries never count as success.

**Transition:** “Reliable exits make the campaign usable by automation as well as by a reader.”

## Optional waveforms: manual guidance, rehearse separately

Available sources verify that elaboration uses `-debug typical`, the runner executes snapshot `axi4l_sim` with `-R`, and `TB/testbench.sv` calls `$dumpfile("dump.vcd")` and `$dumpvars(0, tb)`. No GUI-opening or Tcl waveform command was verified for this guide. Therefore no invented `add_wave`, `log_wave` or GUI-launch command is provided. GUI menu names/import support must be checked on the installed simulator before presenting.

**Manual workflow:** use the installed GUI's supported workflow to open the existing snapshot with the same plusargs, or load generated dump.vcd in a compatible viewer. Rehearse this first. Confirm top `tb`, the selected mutant and run configuration. A VCD may be large and later runs overwrite it; preserve it between runs when comparing golden and mutant behavior. If a signal is absent from the dump, use a verified live-debug GUI workflow rather than assuming it was captured.

Add these exact source signals (GUI hierarchy separators may differ):

- `tb.ACLK`, `tb.ARESETN`.
- On **both** `tb.bus` and `tb.dbus`: `AWADDR`, `AWVALID`, `AWREADY`, `WDATA`, `WSTRB`, `WVALID`, `WREADY`, `BRESP`, `BVALID`, `BREADY`, `ARADDR`, `ARVALID`, `ARREADY`, `RDATA`, `RRESP`, `RVALID`, `RREADY`.
- If exposed in the debug view: `tb.dut.mutid`, `tb.dut.m_trig`, `tb.dut.m_pdiff`. Do not require class internals; use the log/scoreboard for functional diagnosis.

**Golden:** on a rising edge with VALID=1, READY=0, show VALID held and payload unchanged at the following sampled edge. VALID=READY=1 is acceptance. AW and W can handshake independently; do not demand simultaneous AW/W. RDATA/RRESP remain stable while a valid read response waits for RREADY.

**M05:** inspect a scored interval after validation/control, with mutid=5. Show RVALID dropping on the following sampled edge after RVALID=1/RREADY=0, then correlate with A09. Compare bus and dbus: response-delay shims can mask DUT-side events at the master interface. Do not mistake reset cancellation or disabled assertions during validation for a missing scored diagnostic. For M09, timing may look legal while the read of 0x3C is corrupted; S06 supplies the functional diagnosis.

## Common evaluator questions

| Question | Answer you can say directly |
|---|---|
| What is the novelty or contribution? | “The contribution is this implementation and integration: passive data checking, protocol assertions on both sides of a timing shim, fixed-map goal selection, and mutation diagnosis with explicit policy. AXI checking and mutation testing are established concepts; I do not claim a first-of-its-kind method.” |
| Why no UVM? | “For this bounded educational/research environment, classes, interfaces and mailboxes keep the flow small and inspectable. UVM adds standard reuse and scaling infrastructure. Avoiding it is a scope choice, not a claim it is unnecessary in large projects.” |
| How DUT-independent is it? | “RAM and GPIO share protocol/environment components. New maps, side effects, reset behavior and timing expectations still require model/configuration adaptation.” |
| Why assertions and scoreboard? | “Assertions check cycle-level persistence, stability and response legality. The passive scoreboard checks observed data/response semantics and transaction accounting. They expose different defect classes.” |
| What does coverage mean? | “49/49 is the custom functional-goal tracker. It is not all native bins, code coverage or exhaustive compliance.” |
| Detection versus diagnosis? | “A diagnostic can exist without the expected tuple, or the expected report can follow a wrong primary. expected_seen and primary_match separate those cases, with co-primary and secondary-noise rules.” |
| What is the timeout policy? | “Normal driver waits are bounded at 200 cycles. LAT_LIMIT=100 separately checks first-response latency. A timeout is recorded; stalled VALID/payload remain stable until runner reset, pending diagnostics survive and queued work is not silently discarded. The focused recovery test temporarily lowers the bound. The watchdog is a last escape.” |
| Is closure AI-based? | “No. It uses a fixed gap_test mapping and bounded loop. The 40.76% reduction is seed-7 simulation cycles for this goal set, not universal speedup.” |
| Is XSim equivalent to Xcelium? | “Strict equivalence is not established. This patch was validated on XSim 2026.1; no fresh Xcelium run is claimed. Root EDA Playground sources and their existing local edits are separate.” |
| Reset X/Z behavior? | “A12/A12b use VALID !== 1'b1, accepting X/Z as well as zero. Original !VALID does not pass on X/Z. Active-operation unknown checks do not make reset semantics equivalent.” |
| Assertion-control scoping? | “XSim warns that scoped $assertoff/$asserton act globally. Validation finishes and assertions are re-enabled before scoring, with validation records excluded from the scored base. The simulator limitation remains.” |
| Does 20/20 prove completeness? | “It establishes sensitivity and diagnosis for twenty implemented mutants under these campaigns. Other defects, temporal combinations, seeds and DUTs remain possible.” |
| Formal proof or exhaustive compliance certification? | “No. These are scoped simulation results. Broader claims need more protocol cases, models, configurations and independent validation.” |

## Troubleshooting

1. **Quoting:** use CMD with separate quoted tokens `"-testplusarg" "KEY=value"`. Do not use Xcelium-style `+TEST=...` in the runner. Do not copy a visible prompt. Inspect the `MANIFEST,` line for selected test/DUT/seed. `findstr /B` stops echoed simulator commands from masquerading as summaries.
2. **Missing summaries/nonzero exit:** stop and read the complete demo log, for example `type "demo_logs\ram_s7.log"`. The wrapper requires the correct mode summary and final CAMPAIGN PASS, not just a simulator exit. Never substitute a canned PASS for missing output.
3. **Compile/elaborate failure:** inspect demo_logs/compile.log and elaborate.log, working directory, include paths and tool installation. Do not continue with an old snapshot. Fix/build outside the timed segment or label and use the saved fallback.
4. **Expected assertions:** mutant/negative/fault runs intentionally report violations. Judge their final policy and exit. Golden assertion reports, unexpected secondary records or missed expected faults require investigation; do not dismiss every diagnostic as intentional.
5. **Stale snapshot/unexpected cycles:** rebuild compile and elaborate sequentially in Vivado_Port. Check no source edits since build, correct seed/DUT, no extra plusargs, no concurrent process. Compare source state rather than choosing whichever log looks best.
6. **Quiet redirected run:** wait for process completion. A growing log has no final verdict yet. If the tool stalls, do not launch a second build; switch to saved evidence and investigate afterwards.
7. **Long lines:** widen the console or open the log in the editor. MUTRES is one long line. A display filter does not replace campaign validation. Multi-file findstr output prepends filenames; these are not simulator fields.
8. **Live versus saved:** label the source aloud. demo_logs is presentation output; check_logs/verified_* is retained evidence. Never overwrite or relabel saved results as fresh.

## Final pre-presentation checklist

- [ ] CMD working directory is the port; quoted commands rehearsed without visible prompts.
- [ ] Compile/elaborate exits zero; source and snapshot agree; no parallel builds/runs.
- [ ] demo_logs exists and prior presentation outputs are archived if needed; verified evidence untouched.
- [ ] Editor bookmarks, readable fonts and a roughly nine-minute rehearsal completed.
- [ ] Live golden/M05/closure launch times measured on this machine; fallback evidence accessible.
- [ ] Seed-7 figures ready: RAM 10779, GPIO 10747, closure 6385, cycle reduction 40.76%.
- [ ] Expected failures explained by campaign policy; no illegal traffic described as golden success.
- [ ] Claims limited to these DUTs, tests, goals and mutants; reset X/Z and assertion-control caveats ready.
- [ ] Waveform workflow rehearsed manually if used; otherwise omit it.
- [ ] No claim of exhaustive compliance, universal DUT support, AI closure, formal proof or fresh Xcelium validation.

Closing reminder: “I can show the stimulus, the observed handshake, the checker or model expectation, and the final policy. That makes passing results and detected defects explainable within the stated scope.”
