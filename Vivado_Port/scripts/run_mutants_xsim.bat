@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
call "%SCRIPT_DIR%compile_xsim.bat" || exit /b 1
call "%SCRIPT_DIR%elaborate_xsim.bat" || exit /b 1
call "%SCRIPT_DIR%run_xsim.bat" "-testplusarg" "MUTCLASSCHECK=1" || exit /b 1
for %%S in (7 1) do (
  call "%SCRIPT_DIR%run_xsim.bat" "-testplusarg" "MUTSWEEP=1" "-testplusarg" "MUTFIRST=1" "-testplusarg" "MUTLAST=20" "-testplusarg" "MUTFULL=1" "-testplusarg" "SEED=%%S" || exit /b 1
)
exit /b 0
