@echo off
REM Test 1
cd /d "%~dp0"
echo ^>^> Running Test 1 (sustained, ~30 min)...
call common.bat test1 pingdir-test1-sustained.jmx
pause
