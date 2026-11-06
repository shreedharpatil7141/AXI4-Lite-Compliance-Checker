@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
call "%SCRIPT_DIR%compile_xsim.bat" || exit /b 1
call "%SCRIPT_DIR%elaborate_xsim.bat" || exit /b 1

echo.
echo ========================================================
echo Running Mutation Classifier Logic Verification...
echo ========================================================
call "%SCRIPT_DIR%run_xsim.bat" "-testplusarg" "MUTCLASSCHECK=1"

echo.
echo ========================================================
echo Running Single Mutant Verification Sample (M01)...
echo ========================================================
call "%SCRIPT_DIR%run_xsim.bat" "-testplusarg" "DUT=rtlmut" "-testplusarg" "MUTID=1"

echo.
echo ========================================================
echo Running Single Mutant Verification Sample (M02)...
echo ========================================================
call "%SCRIPT_DIR%run_xsim.bat" "-testplusarg" "DUT=rtlmut" "-testplusarg" "MUTID=2"

echo.
echo ========================================================
echo [COMPLETE] Mutation testing finished.
echo ========================================================
exit /b 0
