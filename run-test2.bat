@echo off
REM Test 2 - breaking point
cd /d "%~dp0"
call common.bat || (pause & exit /b 1)
if exist out\test2 rmdir /s /q out\test2
mkdir out\test2
echo ^>^> Running Test 2 (breaking point)...
echo ^>^> It KEEPS CLIMBING - press Ctrl-C when PingDirectory starts failing.
echo ^>^> Watch: kubectl get pods -n userstore-blue -l app.kubernetes.io/name=pingdirectory -o wide -w
call jmeter -n -t pingdir-test2-breakingpoint.jmx -q settings.properties -l out\test2\results.jtl -e -o out\test2\report
echo ^>^> DONE. Open in a browser:  out\test2\report\index.html
echo ^>^> To remove leftover test records, see the cleanup command in the README.
pause
