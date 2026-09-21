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

# Ctrl-C handler: ask JMeter to stop via its UDP control port (same as bin/stoptest.sh),
# so the run ends cleanly and the report can still be built.
stop_jmeter() {
  local port
  port=$(grep -oE 'on port [0-9]+' "$1/console.log" 2>/dev/null | awk '{print $3}' | tail -1)
  echo; echo ">> Ctrl-C received: stopping JMeter (StopTestNow, port ${port:-4445}), then building the report..."
  printf 'StopTestNow' > "/dev/udp/127.0.0.1/${port:-4445}" 2>/dev/null || true
}

# Usage: run_test <name> <jmx>
run_test() {
  local out="out/$1" jmx="$2" pid
  rm -rf "$out" && mkdir -p "$out"
  # Java .properties keeps trailing spaces/CRs (e.g. "10.0.0.5 " breaks the LDAP URL) - strip them.
  sed -e 's/[[:space:]]*$//' settings.properties > "$out/settings.clean.properties"

  # JMeter runs in the background so Ctrl-C reaches only this script (background jobs ignore SIGINT);
  # the trap then stops JMeter gracefully instead of killing it and losing the report.
  jmeter -n -t "$jmx" -q "$out/settings.clean.properties" \
    -Jjmeter.save.saveservice.autoflush=true \
    -l "$out/results.jtl" -j "$out/jmeter.log" \
    > >(trap '' INT; exec tee "$out/console.log") 2>&1 &
  pid=$!
  trap "stop_jmeter '$out'" INT
  while kill -0 "$pid" 2>/dev/null; do wait "$pid" 2>/dev/null || true; done
  trap - INT

  if [ ! -s "$out/results.jtl" ]; then
    echo ">> No results recorded - check $out/jmeter.log"; return 1
  fi
  echo ">> Building HTML report..."
  if jmeter -g "$out/results.jtl" -o "$out/report" -j "$out/report.log" >/dev/null 2>&1; then
    echo ">> DONE. Open in a browser:  $out/report/index.html"
  else
    echo ">> Report generation failed - see $out/report.log"
  fi
  echo ">> To remove leftover test records, see the cleanup command in the README."
}
