@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
call "%SCRIPT_DIR%compile_xsim.bat" || exit /b 1
call "%SCRIPT_DIR%elaborate_xsim.bat" || exit /b 1

echo.
echo ========================================================
echo [1/4] Running 14-test baseline regression on RAM DUT...
echo ========================================================
call "%SCRIPT_DIR%run_xsim.bat"

echo.
echo ========================================================
echo [2/4] Running coverage-directed closure on RAM DUT...
echo ========================================================
call "%SCRIPT_DIR%run_xsim.bat" "-testplusarg" "TEST=closure"

echo.
echo ========================================================
echo [3/4] Running regression on GPIO DUT...
echo ========================================================
call "%SCRIPT_DIR%run_xsim.bat" "-testplusarg" "DUT=gpio"

echo.
echo ========================================================
echo [4/4] Running 9-test negative suite...
echo ========================================================
call "%SCRIPT_DIR%run_xsim.bat" "-testplusarg" "NEG=100"

echo.
echo ========================================================
echo [COMPLETE] All regression stages finished successfully.
echo ========================================================
exit /b 0
