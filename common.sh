#!/usr/bin/env bash
# Shared pre-flight for run-test1.sh / run-test2.sh (sourced, not run directly).
set -e
cd "$(dirname "${BASH_SOURCE[0]}")"

die() { echo "ERROR: $*"; exit 1; }
prop() { grep -E "^[[:space:]]*$1[[:space:]]*=" settings.properties | head -1 | sed -E 's/^[^=]*=//' | tr -d '[:space:]'; }

command -v jmeter  >/dev/null || die "'jmeter' is not on your PATH. Install Apache JMeter 5.6+ and try again."
command -v keytool >/dev/null || die "'keytool' not found (it comes with Java). Put Java's bin folder on your PATH."

# JMeter needs Java 17+.
JV=$(java -version 2>&1 | head -1 | sed -E 's/.*version "([0-9]+).*/\1/')
if [[ "$JV" =~ ^[0-9]+$ ]] && [ "$JV" -lt 17 ]; then
  die "JMeter needs Java 17 or newer, but you have Java $JV."
fi

grep REPLACE_ME settings.properties | grep -qv '^[[:space:]]*#' \
  && die "open settings.properties and replace the REPLACE_ME values, then save."

HOST=$(prop 'pd\.hostWrite'); PORT=$(prop 'pd\.port')

# --- TLS pre-flight: fail fast if LDAPS isn't reachable at all ---
keytool -printcert -sslserver "$HOST:$PORT" >/dev/null 2>&1 \
  || die "no TLS handshake with $HOST:$PORT. Check pd.hostWrite / pd.port and network reachability."

# --- TLS client settings ---
# The .jmx samplers set trustall=true (JMeter's TrustAllSSLSocketFactory), so no
# truststore is needed. The flag below also turns off JNDI's LDAPS hostname check
# as a safety net, since pd.hostWrite is usually an LB IP not in the cert SAN.
export JVM_ARGS="${JVM_ARGS:-} -Dcom.sun.jndi.ldap.object.disableEndpointIdentification=true"

# Usage: run_test <name> <jmx>
run_test() {
  local out="out/$1"
  rm -rf "$out" && mkdir -p "$out"
  jmeter -n -t "$2" -q settings.properties -l "$out/results.jtl" -e -o "$out/report"
  echo ">> DONE. Open in a browser:  $out/report/index.html"
  echo ">> To remove leftover test records, see the cleanup command in the README."
}
