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

rem Pass any additional plusargs quoted to avoid delimiter splitting
call "%XSIM_CMD%" axi4l_sim -R %*
exit /b %errorlevel%
