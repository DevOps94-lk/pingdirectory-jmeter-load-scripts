@echo off
REM Test 2
cd /d "%~dp0"
echo ^>^> Running Test 2 (breaking point)...
echo ^>^> It KEEPS CLIMBING (max pd.durationSec, default 2h). For a clean stop run JMeter's bin\stoptest.cmd in another window, or press Ctrl-C and answer N.
echo ^>^> Watch: kubectl get pods -n userstore-blue -l app.kubernetes.io/name=pingdirectory -o wide -w
call common.bat test2 pingdir-test2-breakingpoint.jmx
pause
