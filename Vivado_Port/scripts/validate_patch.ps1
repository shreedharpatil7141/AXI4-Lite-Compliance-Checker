$ErrorActionPreference = 'Stop'
$cases = @(@('ram','TEST=regress','DUT=ram'),@('gpio','TEST=regress','DUT=gpio'),@('closure','TEST=closure'),@('neg_ram','NEG=100'),@('neg_gpio','NEG=100','DUT=gpio'),@('fault','FAULT=100'),@('class','MUTCLASSCHECK=1'),@('rstreq','RSTREQ=1'),@('recovery','DRVREC=1'),@('m05','MUTSWEEP=1','MUTFIRST=5','MUTLAST=5','MUTFULL=1'),@('m09','MUTSWEEP=1','MUTFIRST=9','MUTLAST=9','MUTFULL=1'),@('full','MUTSWEEP=1','MUTFULL=1'),@('invalid','TEST=does_not_exist'),@('fail','INJOUT=1'),@('watchdog','WATCHDOG_NS=1'))
$results = @()
foreach ($seed in @(7,1)) {
 foreach ($c in $cases) {
  $argline = ($c[1..($c.Count-1)] | ForEach-Object { '"-testplusarg" "' + $_ + '"' }) -join ' '
  $log = "check_logs\verified_$($c[0])_s$seed.log"
  $command = "call scripts\run_xsim.bat $argline `"-testplusarg`" `"SEED=$seed`" > $log 2>&1"
  cmd /c $command
  $code = $LASTEXITCODE
  $expected = $c[0] -in @('invalid','fail','watchdog')
  $ok = if ($expected) { $code -ne 0 } else { $code -eq 0 }
  $results += [pscustomobject]@{case=$c[0];seed=$seed;exit=$code;expected_failure=$expected;ok=$ok;command=$command}
  $results | Export-Csv check_logs/verified_exit_status.csv -NoTypeInformation
  Write-Output "$log exit=$code expected_failure=$expected ok=$ok"
 }
}

if ($results | Where-Object { -not $_.ok }) { exit 1 }
exit 0
