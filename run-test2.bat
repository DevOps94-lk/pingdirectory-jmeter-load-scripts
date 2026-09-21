@echo off
setlocal enabledelayedexpansion
REM Test 2 - breaking point
cd /d "%~dp0"

where jmeter >nul 2>nul || (echo ERROR: 'jmeter' is not on your PATH. Install Apache JMeter 5.6+ and try again. & pause & exit /b 1)
where keytool >nul 2>nul || (echo ERROR: 'keytool' not found ^(comes with Java^). Put Java's bin folder on your PATH. & pause & exit /b 1)

set "JV="
for /f "tokens=3" %%v in ('java -version 2^>^&1 ^| findstr /i "version"') do set "JV=%%~v"
for /f "delims=. tokens=1" %%a in ("%JV%") do set "JMAJOR=%%a"
if defined JMAJOR if %JMAJOR% LSS 17 (echo ERROR: JMeter needs Java 17 or newer, but you have Java %JV%. Install Java 17+ and rerun. & pause & exit /b 1)

findstr /R /C:"REPLACE_ME" settings.properties | findstr /V /R /C:"^#" >nul && (echo ERROR: open settings.properties and replace the REPLACE_ME values, then save. & pause & exit /b 1)

REM --- Auto-trust PingDirectory's certificate (built once, no manual import) ---
set "PDHOST="
set "PDPORT="
for /f "tokens=2 delims==" %%a in ('findstr /r /c:"^ *pd.hostWrite *=" settings.properties') do set "PDHOST=%%a"
for /f "tokens=2 delims==" %%a in ('findstr /r /c:"^ *pd.port *=" settings.properties') do set "PDPORT=%%a"
set "PDHOST=!PDHOST: =!"
set "PDPORT=!PDPORT: =!"
if not exist pd-truststore.jks (
  echo ^>^> First run: fetching and trusting PingDirectory's certificate from !PDHOST!:!PDPORT! ...
  keytool -printcert -sslserver !PDHOST!:!PDPORT! -rfc > pd-cert.pem 2>nul
  for %%s in (pd-cert.pem) do if %%~zs==0 (echo ERROR: couldn't fetch the certificate from !PDHOST!:!PDPORT!. Check pd.hostWrite/pd.port and that the server is reachable. & del pd-cert.pem 2>nul & pause & exit /b 1)
  keytool -importcert -noprompt -alias pd -file pd-cert.pem -keystore pd-truststore.jks -storepass changeit >nul 2>nul
  del pd-cert.pem 2>nul
  echo ^>^> Certificate trusted ^(saved in pd-truststore.jks^). Delete that file to re-fetch if the cert changes.
)
set "JVM_ARGS=-Djavax.net.ssl.trustStore=%CD%\pd-truststore.jks -Djavax.net.ssl.trustStorePassword=changeit"

if exist out\test2 rmdir /s /q out\test2
mkdir out\test2
echo ^>^> Running Test 2 (breaking point)...
echo ^>^> It KEEPS CLIMBING - press Ctrl-C when PingDirectory starts failing.
echo ^>^> Watch: kubectl get pods -n userstore-blue -l app.kubernetes.io/name=pingdirectory -o wide -w
call jmeter -n -t pingdir-test2-breakingpoint.jmx -q settings.properties -l out\test2\results.jtl -e -o out\test2\report
echo ^>^> DONE. Open in a browser:  out\test2\report\index.html
echo ^>^> To remove leftover test records, purge the ou=loadgen branch (see README).
pause
