@echo off
REM Shared pre-flight for run-test1.bat / run-test2.bat (called, not run directly).
cd /d "%~dp0"

where jmeter >nul 2>nul || (echo ERROR: 'jmeter' is not on your PATH. Install Apache JMeter 5.6+. & exit /b 1)
where keytool >nul 2>nul || (echo ERROR: 'keytool' not found ^(comes with Java^). Put Java's bin folder on your PATH. & exit /b 1)

set "JV="
for /f "tokens=3" %%v in ('java -version 2^>^&1 ^| findstr /i "version"') do set "JV=%%~v"
for /f "delims=. tokens=1" %%a in ("%JV%") do set "JMAJOR=%%a"
if defined JMAJOR if %JMAJOR% LSS 17 (echo ERROR: JMeter needs Java 17 or newer, but you have Java %JV%. & exit /b 1)

findstr /R /C:"REPLACE_ME" settings.properties | findstr /V /R /C:"^#" >nul && (echo ERROR: open settings.properties and replace the REPLACE_ME values, then save. & exit /b 1)

set "PDHOST="
set "PDPORT="
for /f "tokens=2 delims==" %%a in ('findstr /r /c:"^ *pd.hostWrite *=" settings.properties') do set "PDHOST=%%a"
for /f "tokens=2 delims==" %%a in ('findstr /r /c:"^ *pd.port *=" settings.properties') do set "PDPORT=%%a"
set "PDHOST=%PDHOST: =%"
set "PDPORT=%PDPORT: =%"

REM TLS pre-flight: fail fast if LDAPS isn't reachable at all.
keytool -printcert -sslserver %PDHOST%:%PDPORT% >nul 2>nul || (echo ERROR: no TLS handshake with %PDHOST%:%PDPORT%. Check pd.hostWrite / pd.port and reachability. & exit /b 1)

REM trustall=true is set in the .jmx; this flag also turns off JNDI's LDAPS
REM hostname check (pd.hostWrite is usually an LB IP not in the cert SAN).
set "JVM_ARGS=%JVM_ARGS% -Dcom.sun.jndi.ldap.object.disableEndpointIdentification=true"
exit /b 0
