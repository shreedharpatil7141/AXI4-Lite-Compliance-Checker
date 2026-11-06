@echo off
setlocal
set VIVADO_BIN=C:\AMDDesignTools\2026.1\Vivado\bin
if not exist "%VIVADO_BIN%\xvlog.bat" (
  where xvlog >nul 2>nul
  if %errorlevel% neq 0 (
    echo [ERROR] Vivado xvlog not found in PATH or at %VIVADO_BIN%
    exit /b 1
  )
  set XVLOG_CMD=xvlog
) else (
  set "XVLOG_CMD=%VIVADO_BIN%\xvlog.bat"
)

echo [INFO] Compiling Design and Testbench with %XVLOG_CMD%...
call "%XVLOG_CMD%" -sv -i "%~dp0..\Design" "%~dp0..\Design\design.sv" -i "%~dp0..\TB" -i "%~dp0..\Design" "%~dp0..\TB\testbench.sv"
if %errorlevel% neq 0 (
  echo [ERROR] Compilation failed.
  exit /b %errorlevel%
)
echo [INFO] Compilation successful.
exit /b 0
