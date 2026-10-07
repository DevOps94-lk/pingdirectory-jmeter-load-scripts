#!/usr/bin/env bash
# Shared pre-flight for run-test1.sh / run-test2.sh (sourced, not run directly).
# Runs on Linux and macOS (bash). Supports two modes, chosen by pd.remoteEngines
# in settings.properties:
#   - blank  -> standalone: load is generated on this machine (original behaviour).
#   - set    -> distributed: this machine is the CONTROLLER; load is generated on
#               the remote engines listed. See the README for one-time engine setup.
set -e
cd "$(dirname "${BASH_SOURCE[0]}")"

die() { echo "ERROR: $*"; exit 1; }
prop() { grep -E "^[[:space:]]*$1[[:space:]]*=" settings.properties | head -1 | sed -E 's/^[^=]*=//' | tr -d '[:space:]'; }

command -v jmeter  >/dev/null || die "'jmeter' is not on your PATH. Install Apache JMeter 5.6+ and try again."

# JMeter needs Java 17+.
JV=$(java -version 2>&1 | head -1 | sed -E 's/.*version "([0-9]+).*/\1/')
if [[ "$JV" =~ ^[0-9]+$ ]] && [ "$JV" -lt 17 ]; then
  die "JMeter needs Java 17 or newer, but you have Java $JV."
fi

grep REPLACE_ME settings.properties | grep -qv '^[[:space:]]*#' \
  && die "open settings.properties and replace the REPLACE_ME values, then save."

HOST=$(prop 'pd\.hostWrite'); PORT=$(prop 'pd\.port')
REMOTE=$(prop 'pd\.remoteEngines')   # blank = standalone, non-blank = distributed

if [ -z "$REMOTE" ]; then
  # --- STANDALONE: this machine connects to PingDirectory, so check it can. ---
  command -v keytool >/dev/null || die "'keytool' not found (it comes with Java). Put Java's bin folder on your PATH."
  # TLS pre-flight: fail fast if LDAPS isn't reachable at all.
  keytool -printcert -sslserver "$HOST:$PORT" >/dev/null 2>&1 \
    || die "no TLS handshake with $HOST:$PORT. Check pd.hostWrite / pd.port and network reachability."
else
  # --- DISTRIBUTED: the ENGINES connect to PingDirectory, not this controller. ---
  # Skip the local TLS check: the controller may have no route to PingDirectory,
  # and that is fine. Each engine must be able to reach $HOST:$PORT itself.
  echo ">> Distributed mode: engines = $REMOTE"
  echo ">> Each engine must reach PingDirectory at $HOST:$PORT and have the one-time"
  echo ">> engine setup applied (read timeout + LDAPS hostname check). See the README."
fi

# --- TLS client settings (used in standalone; harmless in distributed) ---
# The .jmx samplers set trustall=true (JMeter's TrustAllSSLSocketFactory), so no
# truststore is needed. The flag below also turns off JNDI's LDAPS hostname check
# as a safety net, since pd.hostWrite is usually an LB IP not in the cert SAN.
# In DISTRIBUTED mode this applies to the controller only; set it on each ENGINE too
# (see the README) because the engines are the ones opening LDAPS connections.
export JVM_ARGS="${JVM_ARGS:-} -Dcom.sun.jndi.ldap.object.disableEndpointIdentification=true"

# Ctrl-C handler: ask JMeter to stop via its UDP control port (same as bin/stoptest.sh),
# so the run ends cleanly and the report can still be built. In distributed mode the
# controller relays the stop to all engines.
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

  # JMeter's LDAP sampler sets no read timeout, so a hung server would never be recorded as a failure.
  # JNDI merges jndi.properties from the classpath into every connection's environment - use that.
  # NOTE: this classpath entry is LOCAL. In distributed mode it protects the controller only;
  # the read timeout must also be set on each ENGINE (see the README) to protect the real connections.
  local rto; rto=$(prop 'pd\.readTimeoutMs'); mkdir -p "$out/jndi"
  echo "com.sun.jndi.ldap.read.timeout=${rto:-30000}" > "$out/jndi/jndi.properties"

  # Mode args: distributed (controller + engines) vs standalone (local load).
  #   -R  : the remote engines to drive.
  #   -G<file> : send these properties TO the engines. This is the key difference from
  #              standalone's -q: -q sets properties locally only and they never reach the
  #              engines, so the plan (host, bind, base DN, rates) would fall back to defaults
  #              and every LDAP op would fail. -G propagates them.
  local mode_args=()
  if [ -n "$REMOTE" ]; then
    mode_args=(-R "$REMOTE" -G"$PWD/$out/settings.clean.properties")
  else
    mode_args=(-q "$out/settings.clean.properties")
  fi

  # JMeter runs in the background so Ctrl-C reaches only this script (background jobs ignore SIGINT);
  # the trap then stops JMeter gracefully instead of killing it and losing the report.
  jmeter -n -t "$jmx" "${mode_args[@]}" \
    -Jjmeter.save.saveservice.autoflush=true \
    -Juser.classpath="$PWD/$out/jndi" \
    -l "$out/results.jtl" -j "$out/jmeter.log" \
    > >(trap '' INT; exec tee "$out/console.log") 2>&1 &
  pid=$!
  trap "stop_jmeter '$out'" INT
  while kill -0 "$pid" 2>/dev/null; do wait "$pid" 2>/dev/null || true; done
  trap - INT

  if [ ! -s "$out/results.jtl" ]; then
    echo ">> No results recorded - check $out/jmeter.log"; return 1
  fi
  # Problems inside JMeter itself (bad setting, function error) go to jmeter.log, not the results.
  local nerr; nerr=$(grep -c ' ERROR ' "$out/jmeter.log" 2>/dev/null || true)
  [ "${nerr:-0}" -gt 0 ] && echo ">> WARNING: $nerr ERROR line(s) in $out/jmeter.log - review them: grep ' ERROR ' $out/jmeter.log"
  echo ">> Building HTML report..."
  if jmeter -g "$out/results.jtl" -o "$out/report" -j "$out/report.log" >/dev/null 2>&1; then
    echo ">> DONE. Open in a browser:  $out/report/index.html"
  else
    echo ">> Report generation failed - see $out/report.log"
  fi
  echo ">> To remove leftover test records, see the cleanup command in the README."
}
