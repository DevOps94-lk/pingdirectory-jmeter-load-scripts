#!/usr/bin/env bash
# Test 2 - breaking point
set -e
cd "$(dirname "$0")"

command -v jmeter >/dev/null || { echo "ERROR: 'jmeter' is not on your PATH. Install Apache JMeter 5.6+ and try again."; exit 1; }
command -v keytool >/dev/null || { echo "ERROR: 'keytool' not found (it comes with Java). Make sure Java's bin folder is on your PATH."; exit 1; }

# JMeter itself needs Java 17+. Any newer version is fine (these tests use no Groovy).
JV=$(java -version 2>&1 | head -1 | sed -E 's/.*version "([0-9]+).*/\1/')
if echo "$JV" | grep -qE '^[0-9]+$'; then
  if [ "$JV" -lt 17 ]; then
    echo "ERROR: JMeter needs Java 17 or newer, but you have Java $JV. Install Java 17+ and rerun."
    exit 1
  fi
fi

if grep REPLACE_ME settings.properties | grep -qv '^[[:space:]]*#'; then
  echo "ERROR: open settings.properties and replace the REPLACE_ME values, then save."
  exit 1
fi

# --- Auto-trust PingDirectory's certificate (built once, no manual import) ---
HOST=$(grep -E '^[[:space:]]*pd\.hostWrite[[:space:]]*=' settings.properties | head -1 | sed -E 's/^[^=]*=//' | tr -d '[:space:]')
PORT=$(grep -E '^[[:space:]]*pd\.port[[:space:]]*=' settings.properties | head -1 | sed -E 's/^[^=]*=//' | tr -d '[:space:]')
TS="$PWD/pd-truststore.jks"
if [ ! -f "$TS" ]; then
  echo ">> First run: fetching and trusting PingDirectory's certificate from $HOST:$PORT ..."
  keytool -printcert -sslserver "$HOST:$PORT" -rfc > pd-cert.pem 2>/dev/null || true
  if [ ! -s pd-cert.pem ]; then
    echo "ERROR: couldn't fetch the certificate from $HOST:$PORT."
    echo "       Check pd.hostWrite and pd.port in settings.properties, and that the server is reachable."
    rm -f pd-cert.pem; exit 1
  fi
  keytool -importcert -noprompt -alias pd -file pd-cert.pem -keystore "$TS" -storepass changeit >/dev/null 2>&1
  rm -f pd-cert.pem
  echo ">> Certificate trusted (saved in pd-truststore.jks). Delete that file to re-fetch if the cert changes."
fi
export JVM_ARGS="-Djavax.net.ssl.trustStore=$TS -Djavax.net.ssl.trustStorePassword=changeit"

rm -rf out/test2 && mkdir -p out/test2
echo ">> Running Test 2 (breaking point). Report will be out/test2/report/index.html"
echo ">> It KEEPS CLIMBING - press Ctrl-C when PingDirectory starts failing."
echo ">> Watch: kubectl get pods -n userstore-blue -l app.kubernetes.io/name=pingdirectory -o wide -w"
jmeter -n -t pingdir-test2-breakingpoint.jmx -q settings.properties -l out/test2/results.jtl -e -o out/test2/report
echo ">> DONE. Open in a browser:  out/test2/report/index.html"
echo ">> To remove leftover test records, purge the ou=loadgen branch (see README)."
