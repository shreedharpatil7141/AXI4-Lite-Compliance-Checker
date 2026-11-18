@echo off
setlocal
set VIVADO_BIN=C:\AMDDesignTools\2026.1\Vivado\bin
if not exist "%VIVADO_BIN%\xsim.bat" (
  where xsim >nul 2>nul
  if %errorlevel% neq 0 (
    echo [ERROR] Vivado xsim not found in PATH or at %VIVADO_BIN%
    exit /b 1
  )
  set XSIM_CMD=xsim
) else (
  set "XSIM_CMD=%VIVADO_BIN%\xsim.bat"
)

rem Match testbench dispatch order; explicitly disabled modes must not win.
for %%K in (MUTCLASSCHECK COVREQ RSTREQ COVSKEW AWPROBE DEDUP FAULT NEG MUTSWEEP MASK) do set "MODE_%%K=0"
set "MODE_DRVREC=0"
for %%A in (%*) do (
  for /f "tokens=1,2 delims==" %%K in ("%%~A") do (
    if "%%K"=="DRVREC" (set "MODE_DRVREC=1") else set "MODE_%%K=%%L"
  )
)
set "SUMMARY=STAGE9 mode="
if not "%MODE_MASK%"=="0" set "SUMMARY=MASKSUM "
if not "%MODE_MUTSWEEP%"=="0" set "SUMMARY=MUTSUM "
if not "%MODE_NEG%"=="0" set "SUMMARY=NEGSUM "
if not "%MODE_FAULT%"=="0" set "SUMMARY=FAULTSUM "
if not "%MODE_DEDUP%"=="0" set "SUMMARY=DEDUPTEST,"
if not "%MODE_AWPROBE%"=="0" set "SUMMARY=AWPROBESUM,"
if not "%MODE_COVSKEW%"=="0" set "SUMMARY=COVSKEW_RESULT,"
if not "%MODE_RSTREQ%"=="0" set "SUMMARY=RSTREQSUM,"
if not "%MODE_DRVREC%"=="0" set "SUMMARY=DRVRECSUM "
if not "%MODE_COVREQ%"=="0" set "SUMMARY=COVREQ_RESULT,"
if not "%MODE_MUTCLASSCHECK%"=="0" set "SUMMARY=MUTCLASSSUM,"
set "RUN_LOG=%TEMP%\axi4l_%RANDOM%_%RANDOM%.log"
call "%XSIM_CMD%" axi4l_sim -R -log "%RUN_LOG%" %*
if errorlevel 1 exit /b 1
rem Expected assertion reports do not themselves fail negative or mutation campaigns.
call "%~dp0check_xsim_summary.bat" "%RUN_LOG%" "%SUMMARY%"
exit /b %errorlevel%
