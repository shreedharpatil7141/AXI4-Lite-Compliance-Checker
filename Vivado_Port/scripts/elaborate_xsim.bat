@echo off
setlocal
set VIVADO_BIN=C:\AMDDesignTools\2026.1\Vivado\bin
if not exist "%VIVADO_BIN%\xelab.bat" (
  where xelab >nul 2>nul
  if %errorlevel% neq 0 (
    echo [ERROR] Vivado xelab not found in PATH or at %VIVADO_BIN%
    exit /b 1
  )
  set XELAB_CMD=xelab
) else (
  set "XELAB_CMD=%VIVADO_BIN%\xelab.bat"
)

echo [INFO] Elaborating testbench tb with %XELAB_CMD%...
call "%XELAB_CMD%" -debug typical tb -s axi4l_sim
if %errorlevel% neq 0 (
  echo [ERROR] Elaboration failed.
  exit /b %errorlevel%
)
echo [INFO] Elaboration successful: snapshot axi4l_sim generated.
exit /b 0
