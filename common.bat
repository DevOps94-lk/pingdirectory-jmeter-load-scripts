@echo off
REM Shared pre-flight for run-test1.bat / run-test2.bat (called, not run directly).
REM Two modes, chosen by pd.remoteEngines in settings.properties:
REM   blank -> standalone (this machine generates load)
REM   set   -> distributed (this machine is the controller; engines generate load)
cd /d "%~dp0"

where jmeter >nul 2>nul || (echo ERROR: 'jmeter' is not on your PATH. Install Apache JMeter 5.6+. & exit /b 1)

set "JV="
for /f "tokens=3" %%v in ('java -version 2^>^&1 ^| findstr /i "version"') do set "JV=%%~v"
for /f "delims=. tokens=1" %%a in ("%JV%") do set "JMAJOR=%%a"
if defined JMAJOR if %JMAJOR% LSS 17 (echo ERROR: JMeter needs Java 17 or newer, but you have Java %JV%. & exit /b 1)

findstr /R /C:"REPLACE_ME" settings.properties | findstr /V /R /C:"^#" >nul && (echo ERROR: open settings.properties and replace the REPLACE_ME values, then save. & exit /b 1)

set "PDHOST="
set "PDPORT="
set "REMOTE="
for /f "tokens=2 delims==" %%a in ('findstr /r /c:"^ *pd.hostWrite *=" settings.properties') do set "PDHOST=%%a"
for /f "tokens=2 delims==" %%a in ('findstr /r /c:"^ *pd.port *=" settings.properties') do set "PDPORT=%%a"
for /f "tokens=2 delims==" %%a in ('findstr /r /c:"^ *pd.remoteEngines *=" settings.properties') do set "REMOTE=%%a"
set "PDHOST=%PDHOST: =%"
set "PDPORT=%PDPORT: =%"
set "REMOTE=%REMOTE: =%"

if not defined REMOTE (
  REM STANDALONE: this machine connects to PingDirectory, so check it can.
  where keytool >nul 2>nul || (echo ERROR: 'keytool' not found ^(comes with Java^). Put Java's bin folder on your PATH. & exit /b 1)
  keytool -printcert -sslserver %PDHOST%:%PDPORT% >nul 2>nul || (echo ERROR: no TLS handshake with %PDHOST%:%PDPORT%. Check pd.hostWrite / pd.port and reachability. & exit /b 1)
) else (
  REM DISTRIBUTED: the ENGINES connect to PingDirectory, not this controller.
  echo ^>^> Distributed mode: engines = %REMOTE%
  echo ^>^> Each engine must reach PingDirectory at %PDHOST%:%PDPORT% and have the one-time
  echo ^>^> engine setup applied ^(read timeout + LDAPS hostname check^). See the README.
)

REM trustall=true is set in the .jmx; this flag also turns off JNDI's LDAPS
REM hostname check (pd.hostWrite is usually an LB IP not in the cert SAN).
REM In DISTRIBUTED mode this applies to the controller only; set it on each ENGINE too.
set "JVM_ARGS=%JVM_ARGS% -Dcom.sun.jndi.ldap.object.disableEndpointIdentification=true"

REM ---- run: common.bat <name> <jmx> ----
set "OUT=out\%~1"
if exist "%OUT%" rmdir /s /q "%OUT%"
mkdir "%OUT%"
REM Java .properties keeps trailing spaces (e.g. "10.0.0.5 " breaks the LDAP URL) - strip them.
powershell -NoProfile -Command "(Get-Content 'settings.properties') -replace '\s+$','' | Set-Content '%OUT%\settings.clean.properties'"
REM JMeter's LDAP sampler sets no read timeout; JNDI picks it up from jndi.properties on the classpath.
REM (Local only; in distributed mode set the read timeout on each ENGINE too - see the README.)
set "RTO="
for /f "tokens=2 delims==" %%a in ('findstr /r /c:"^ *pd.readTimeoutMs *=" "%OUT%\settings.clean.properties"') do set "RTO=%%a"
if not defined RTO set "RTO=30000"
set "RTO=%RTO: =%"
mkdir "%OUT%\jndi"
>"%OUT%\jndi\jndi.properties" echo com.sun.jndi.ldap.read.timeout=%RTO%
echo ^>^> If you press Ctrl-C and Windows asks "Terminate batch job (Y/N)?", answer N so the report still gets built.

REM -G<file> SENDS the settings to the engines; -q would set them locally only and they
REM would never reach the engines (plan would fall back to defaults and every op would fail).
if defined REMOTE (
  call jmeter -n -t "%~2" -R %REMOTE% -G"%CD%\%OUT%\settings.clean.properties" -Jjmeter.save.saveservice.autoflush=true "-Juser.classpath=%CD%\%OUT%\jndi" -l "%OUT%\results.jtl" -j "%OUT%\jmeter.log"
) else (
  call jmeter -n -t "%~2" -q "%OUT%\settings.clean.properties" -Jjmeter.save.saveservice.autoflush=true "-Juser.classpath=%CD%\%OUT%\jndi" -l "%OUT%\results.jtl" -j "%OUT%\jmeter.log"
)
if not exist "%OUT%\results.jtl" (echo ^>^> No results recorded - check %OUT%\jmeter.log & exit /b 1)
findstr /c:" ERROR " "%OUT%\jmeter.log" >nul 2>nul && echo ^>^> WARNING: jmeter.log has ERROR lines - review: findstr /c:" ERROR " %OUT%\jmeter.log
echo ^>^> Building HTML report...
call jmeter -g "%OUT%\results.jtl" -o "%OUT%\report" -j "%OUT%\report.log" >nul 2>nul && (echo ^>^> DONE. Open in a browser:  %OUT%\report\index.html) || (echo ^>^> Report generation failed - see %OUT%\report.log)
echo ^>^> To remove leftover test records, see the cleanup command in the README.
exit /b 0
