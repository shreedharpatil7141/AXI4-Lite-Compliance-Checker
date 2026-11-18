@echo off
rem Require the mode summary and the successful final verdict in this invocation's log.
findstr /b /c:"%~2" "%~1" >nul
if errorlevel 1 (
  echo [ERROR] Missing required summary %~2 in %~1
  exit /b 1
)
findstr /b /c:"CAMPAIGN PASS" "%~1" >nul
if errorlevel 1 (
  echo [ERROR] Missing successful campaign verdict in %~1
  exit /b 1
)
exit /b 0
