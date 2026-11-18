# Vivado verification patch - 2026-11-18

Source baseline: git HEAD `82d2bcdfa42779fc57ec8cbdfbe15c1abbca8273`, dirty working tree.
No AGENTS.md was found in the workspace or checked parent locations.
At entry README.md and root TB/assertions.sv, TB/driver.sv, TB/testbench.sv were
already modified, with additional untracked audit/manuscript artifacts and logs.
Those root TB edits and untracked artifacts were preserved. The initial Vivado
wait_r included reset handling after its single acceptance edge; that handling
was retained and extended to bounded actual-handshake waiting.
No commit or push was performed. Hashes of the tested port sources are in
`check_logs/verified_source_sha256.csv`.

## Evidence and changes

* `check_logs/mutant5.log` contains repeated driver timeouts and subsequent
  request-withdrawal/accounting diagnostics. The old wait_r and wait_b sampled
  VALID only once after raising READY. A withdrawn response could miss that edge,
  leaving an outstanding request while later traffic continued. Request waits
  dropped VALID unconditionally at timeout.
* `TB/driver.sv`: bounded VALID observation and actual READY/VALID handshake
  waits, response sampling only on handshake, reset cancellation during delays
  and waits. A stalled request retains VALID/payload until runner reset. Timeout
  is counted once; driver pauses dequeue until recovery completes; drv2done still
  receives every transaction exactly once, allowing env.wait_done to complete.
* `TB/testbench.sv`: recovery records S09 before monitor reset flushes pending
  requests, retains timeout S10 accounting, logs incomplete requests, updates
  reference memory for fully accepted writes (RAM retains memory on reset), and
  uses normal do_reset for GPIO model reset, shim, and both monitors. Mailboxes
  are not emptied. Queued traffic resumes after reset. RSTREQ and DRVREC checks
  cover stalled AW/W/AR cancellation and timeout recovery; DRVREC requires two
  subsequent successful completions, idle monitor queues and no bus violations.
* A deterministic word-15 write, distinct word-0 write and immediate word-15
  read precede directed_basic through the normal generator/driver/monitor/
  scoreboard paths. This also runs on golden controls. Mutation validation
  counters remain separate; scored records begin after mut_init/base capture.
* Invalid test, watchdog and failed final verdict use fatal. Successful campaigns
  emit CAMPAIGN PASS. Expected assertion reports do not themselves fail negative
  or mutation campaigns. Individual mutant regression failures do not abort the
  sweep. Final mutation policy requires control OK and all selected mutants KILLED.
  Allowlists and classifier logic were not broadened; M05 still runs all ordinary
  regression tests with MUTFULL=1. Existing isolated M01/M13/M14 probes remain.
* `TB/mutant_tasks.sv`: enforce the final mutation policy after all selected mutants.
* Batch runners propagate failure and require final summaries; the mutant runner
  runs 1-20, MUTFULL=1, seeds 7 and 1. validate_patch.ps1 records commands and exits.
* Root README fixes latency_injector.sv/fault_tasks.sv filenames, links this port,
  and distinguishes allowed from unallowed co-primary tuples. Port README and
  COMPATIBILITY_AUDIT document the reset semantic difference: !==1'b1 accepts
  X/Z VALID while original !VALID does not pass on X/Z. Assertions were unchanged.

## Reproduction (CMD)

Run sequentially; do not run builds concurrently in this directory:

```cmd
cd /d "C:\AXI4-Lite Compliance Checker\Vivado_Port"
call scripts\compile_xsim.bat > check_logs\rerun_compile.log 2>&1
call scripts\elaborate_xsim.bat > check_logs\rerun_elaborate.log 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\validate_patch.ps1
```

The script runs seeds 7 then 1 and records every exact quoted CMD command and exit
status in `check_logs/verified_exit_status.csv`. It covers RAM/GPIO regression,
closure, both NEG=100 suites, FAULT=100, MUTCLASSCHECK=1, RSTREQ=1, DRVREC=1,
focused M05/M09 with MUTFULL=1, all 20 mutants with MUTFULL=1, invalid TEST,
INJOUT=1 final campaign failure and WATCHDOG_NS=1 expiry. Example syntax:

```cmd
call scripts\run_xsim.bat "-testplusarg" "TEST=regress" "-testplusarg" "DUT=ram" "-testplusarg" "SEED=7"
call scripts\run_xsim.bat "-testplusarg" "MUTSWEEP=1" "-testplusarg" "MUTFULL=1" "-testplusarg" "SEED=7"
```

## Result provenance

User-supplied pre-change observations: seed 7 RAM 14/14, 49/49, 10518 cycles;
GPIO 14/14, 49/49, 10471; closure 6/6, 49/49, 6287; both negative suites 9/9;
faults 18/18; classifier PASS; full sweep 18 KILLED, 1 NOISY, 1 NOT_EXERCISED.
These are not patch results. Original logs were preserved.

`after_*` and `final_*` logs are intermediate development runs. In particular,
recovery initially removed pending evidence before S09; intermediate M13/M14
misdiagnoses led to recording S09 before reset. `after_m09_s7.log` also has a
wrapper failure caused by editing the batch runner during that development run.
Only `verified_*` logs below validate the final HDL source.

XSim 2026.1 was available and used through the supplied compile/elaborate scripts.
Elaboration retains the known XSim warning that scoped assertion control acts
on all assertions; validation completes and assertions are re-enabled before scoring.
No Xcelium run was performed. Reset X/Z semantics remain a documented port limitation.

## Measured final HDL results

Compile and elaborate: PASS (`verified_compile.log`, `verified_elaborate.log`).

| Campaign | Seed 7 | Seed 1 |
|---|---|---|
| RAM regression | 14 PASS, 49/49 goals, 10779 cycles | 14 PASS, 49/49 goals, 10757 cycles |
| GPIO regression | 14 PASS, 49/49 goals, 10747 cycles | 14 PASS, 49/49 goals, 10717 cycles |
| RAM closure | 6 PASS, 49/49 goals, 6385 cycles | 6 PASS, 49/49 goals, 6382 cycles |
| RAM NEG=100 | 9/9 detected | 9/9 detected |
| GPIO NEG=100 | 9/9 detected | 9/9 detected |
| FAULT=100 | 18/18 detected | 18/18 detected |
| MUTCLASSCHECK=1 | PASS | PASS |
| RSTREQ=1 | 3/3 PASS | 3/3 PASS |
| DRVREC=1 | 3/3 PASS | 3/3 PASS |
| Focused M05, MUTFULL=1 | KILLED; no unexpected secondary records | KILLED; no unexpected secondary records |
| Focused M09, MUTFULL=1 | KILLED; scored S06/R/DATA_MISMATCH | KILLED; scored S06/R/DATA_MISMATCH |
| Full 1-20, MUTFULL=1 | control OK; 20 KILLED; all other classes zero | control OK; 20 KILLED; all other classes zero |
| Invalid TEST | exit 1 | exit 1 |
| INJOUT=1 failed final verdict | exit 1 | exit 1 |
| WATCHDOG_NS=1 | exit 1 | exit 1 |

All 30 recorded exit expectations passed (24 successful campaigns and six intentional
failures). The final wrapper delegates summary validation to check_xsim_summary.bat.
Its checks were replayed against all 30 actual logs with matching exit statuses
(`verified_summary_recheck.csv`). Missing-summary and missing-verdict fixtures
returned 1; a valid fixture returned 0. After this wrapper refactor, RAM seed-7,
COVREQ=1 and COVSKEW=1 smoke runs each returned 0 (`verified_wrapper_*.log`).
The wrapper refactor changed no HDL or campaign policy.

`git diff --check` reports only the pre-existing whitespace at root TB/assertions.sv:19;
that user edit was left intact. No further user commands are required to validate
these results. Reproduction commands above are optional; archive existing verified_*
logs first if rerunning the validation script, which uses those same filenames.

## Finalization review

Re-read the complete tracked diff and untracked patch scripts. No further HDL,
accounting, classifier or allowlist changes were needed. Request VALID and payload
remain held until handshake/reset; the only payload-changing hook is the existing
explicit negative-test flt_aw_chg injection. Pending S09 records are emitted before
reset flush, S10 timeout counts survive, drv2done is delivered before recovery
blocks dequeue, and no mailbox is emptied. The golden and mutation evidence
supports these paths; this is not a proof for arbitrary DUT implementations.

The original report-processing SyntaxError came from a regex backslash inside an
f-string expression. Its replacement computed the regex result before formatting
and completed the populated measured-results table above. The retained script
`scripts/audit_saved_results.py` now independently executes successfully against
that report: 30 campaign expectations, command seeds/log filenames, cycle counts,
compile/elaboration summaries and source hashes all pass. Its output is retained
in `check_logs/finalization_evidence_audit.log`. The audit handles the UTF-16
compile/elaborate logs. Six empty rows from captured helper error output were
removed from verified_summary_recheck.csv; all 30 result records are unchanged.

The historical source hash manifest is retained unchanged. All Design/ and TB/
hashes still match it. The sole changed previously recorded script is run_xsim.bat:
finalization fixed summary selection for disabled plusargs (NEG=0, FAULT=0,
MASK=0) and aligned mixed-mode selection with testbench dispatch priority.
Only affected runner checks were rerun: disabled-mode RAM regression, NEG=100,
MUTCLASSCHECK=1 together with NEG=100, focused M05 MUTFULL=1, FAULT=100 all
returned 0; invalid TEST and short watchdog returned 1. Exact commands and exits
are in finalization_runner_status.csv. Missing-summary/missing-verdict fixtures
returned 1 and the valid fixture returned 0 (finalization_summary_fixtures.csv).
No full sweep rerun was required because the HDL and classifier are unchanged.
The current port source hashes are in finalization_source_sha256.csv.

The compatibility audit introduction's stale blanket semantic-equivalence claim
was corrected. No Xcelium run or strict reset semantic equivalence is claimed.
.gitignore now excludes loose simulator logs and intermediate check_logs files,
with explicit exceptions for retained validation evidence. Files are preserved
on disk. PATCH_COMMIT_FILES.txt enumerates the intended files; only patch-related
README hunks belong in that commit, excluding the pre-existing Section 16.1/16.2
Xcelium results addition. Root TB/assertions.sv, TB/driver.sv and TB/testbench.sv
are pre-existing edits and are excluded. No staging, commit or push was performed.
