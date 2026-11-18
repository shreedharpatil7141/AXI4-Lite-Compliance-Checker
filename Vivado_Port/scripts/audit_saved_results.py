"""Recheck retained XSim evidence without rerunning simulation."""
from pathlib import Path
import csv, hashlib, re
root = Path(__file__).resolve().parents[1]
logs = root / 'check_logs'
rows = list(csv.DictReader((logs / 'verified_exit_status.csv').open()))
assert len(rows) == 30
cycles = {}
for r in rows:
    case, seed = r['case'], r['seed']
    t = (logs / ('verified_%s_s%s.log' % (case, seed))).read_text(errors='replace')
    assert ('"SEED=%s"' % seed) in r['command']
    assert ('verified_%s_s%s.log' % (case, seed)) in r['command']
    bad = case in ('invalid', 'fail', 'watchdog')
    assert int(r['exit']) == (1 if bad else 0)
    assert r['ok'] == 'True'
    assert ('CAMPAIGN PASS' in t) != bad
    if case in ('ram', 'gpio', 'closure'):
        n = 6 if case == 'closure' else 14
        assert re.search(r'REGRESS dut=\w+ tests=%d pass=%d fail=0 goals_hit=49/49' % (n,n),t)
        c = re.search(r'STAGE9 mode=\w+ dut=\w+ seed=%s mut=0 cycles=(\d+) PASS' % seed,t).group(1)
        cycles[case + '_s' + seed] = int(c)
        assert c + ' cycles' in (root / 'VALIDATION_PATCH.md').read_text()
    elif case.startswith('neg_'):
        assert re.search(r'NEGSUM dut=\w+ run=9 detected=9 missed=0 PASS',t)
    elif case == 'fault':
        assert 'FAULTSUM run=18 detected=18 missed=0 PASS' in t
    elif case == 'class':
        assert 'MUTCLASSSUM,PASS' in t
    elif case == 'rstreq':
        assert 'RSTREQSUM,cases=3,pass=3,PASS' in t
    elif case == 'recovery':
        assert 'DRVRECSUM cases=3 PASS' in t
    elif case in ('full','m05','m09'):
        n = 20 if case == 'full' else 1
        summary = re.search(r'^MUTSUM .*',t,re.M).group()
        assert re.search(r'control=\s*OK killed=%d noisy=0 misdiagnosed=0 missed=0 ambiguous=0 not_exercised=0 invalid=0 full=1' % n, summary)
        records = [x for x in re.findall(r'^MUTRES,.*',t,re.M) if not x.startswith('MUTRES,id=0,')]
        assert len(records) == n
        assert all(',class=KILLED,' in x for x in records)
        if case == 'full':
            assert [int(re.search(r'id=(\d+)',x).group(1)) for x in records] == list(range(1,21))
        for x in records:
            assert ',val_trig=' in x and ',val_pdiff=' in x
        if case == 'm05':
            assert ',unexp_secondary_records=0,' in records[0]
        if case == 'm09':
            assert 'primary_diag=S06/R/DATA_MISMATCH' in records[0]
    elif case == 'invalid':
        assert 'STAGE9 ERROR unknown test does_not_exist' in t
    elif case == 'watchdog':
        assert 'STAGE9 WATCHDOG FAIL' in t
    elif case == 'fail':
        assert 'Final regression verdict failed' in t
hash_rows = list(csv.DictReader((logs / 'verified_source_sha256.csv').open()))
changed = []
for r in hash_rows:
    # Retained manifest contains original absolute Windows workspace paths.
    rel = r['Path'].replace('\\','/').split('/Vivado_Port/',1)[1]
    actual = hashlib.sha256((root / rel).read_bytes()).hexdigest().upper()
    if actual != r['Hash']:
        changed.append(rel)
assert changed == ['scripts/run_xsim.bat'], changed
rechecks = list(csv.DictReader((logs / 'verified_summary_recheck.csv').open()))
assert len(rechecks) == 30 and all(r['exit'] == r['expected'] for r in rechecks)
assert 'Compilation successful.' in (logs / 'verified_compile.log').read_text(encoding='utf-16')
assert 'Elaboration successful:' in (logs / 'verified_elaborate.log').read_text(encoding='utf-16')
print('PASS: 30 saved campaigns, command seeds/log paths, source hashes, cycles, 30 summary rechecks')
print('Only source-manifest difference: reviewed runner dispatch fix; HDL hashes all match.')
print('Cycles:', cycles)


