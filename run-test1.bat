@echo off
REM Test 1 - sustained, ~30 min
cd /d "%~dp0"
call common.bat || (pause & exit /b 1)
if exist out\test1 rmdir /s /q out\test1
mkdir out\test1
echo ^>^> Running Test 1 (sustained, ~30 min)...
call jmeter -n -t pingdir-test1-sustained.jmx -q settings.properties -l out\test1\results.jtl -e -o out\test1\report
echo ^>^> DONE. Open in a browser:  out\test1\report\index.html
echo ^>^> To remove leftover test records, see the cleanup command in the README.
pause
