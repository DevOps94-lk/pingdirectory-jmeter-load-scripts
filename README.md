# PingDirectory load test — simple guide

This kit puts a controlled amount of traffic on PingDirectory so you can see how
it copes. Two ready-made tests. Fill in a few lines and run.

It uses JMeter's built-in LDAP samplers, so it runs on any modern Java (Java 17
or newer) with no extra setup. Test records are created directly under the base DN you specify, and named
`uid=e-...` so they're easy to find and remove.

---

## Step 1 — Install the tool (once)

Install **Apache JMeter 5.6+** and **Java 17 or newer**. Check it works:

```
jmeter -v
```

If it says "not found", add JMeter's `bin` folder to your PATH. (Java's `bin`
folder should be on your PATH too - the scripts use `keytool` from it for a quick
connection check before each run.)

## Step 2 — Tell it where to connect and how hard to push

Open **settings.properties** in any text editor.

**Fill in these four lines** (replace REPLACE_ME):

```
pd.hostWrite = REPLACE_ME     <- the PingDirectory address (IP or hostname)
pd.bindDN    = REPLACE_ME     <- the login it should use (e.g. cn=directory manager)
pd.bindPw    = REPLACE_ME     <- the password for that login
pd.baseDN    = REPLACE_ME     <- where test records go (e.g. ou=test,o=TUCUSTOMERSTAGE)
```

The entry that searches look for (`pd.searchFilter`, default `uid=tommytester`)
must exist under `pd.baseDN`. If it doesn't, every Search is marked as an error
with the message "Search matched no entry", so a wrong setting can't look healthy.

**Then set how much traffic**, in operations per second. Each line is one action:

```
pd.searchPerSec = 25     <- look-ups per second
pd.addPerSec    = 1      <- new records created per second
pd.deletePerSec = 0      <- records removed per second
pd.modifyPerSec = 0      <- records changed per second
```

These are your **starting** numbers. Set any to `0` to switch that action off
completely (no connections are opened for it).
One rule: **keep deletes at or below adds** — deletes remove the records that
adds create, so if you delete faster than you add, deletes run out of records
to remove and start reporting errors.

Save the file.

## Step 3 — Run a test

**Mac/Linux:**
```
./run-test1.sh     (steady traffic for about 30 minutes)
./run-test2.sh     (traffic that keeps rising, to find the limit)
```

**Windows:** double-click `run-test1.bat` or `run-test2.bat`.

The scripts stop with a plain message if JMeter is missing, Java is too old, or
you left a REPLACE_ME in the settings.

## Step 4 — Look at the results

When a test finishes it prints where the report is. Open it in a browser:

```
out/test1/report/index.html      (or out/test2/report/index.html)
```

In the **Statistics** table each action (Search, Add, Delete, Modify) is its own
row, showing how many per second, how fast it responded, and the **Error %** —
the number that matters. Near 0 is healthy; when it climbs, PingDirectory is
starting to struggle.

---

## Which test to use

**Test 1 — steady traffic.** Holds your rates flat for 30 minutes. The safe one
to start with.

**Test 2 — find the breaking point.** Starts at your rates and keeps raising them
smoothly: every 2 minutes, another 30% of the starting rate is added (after 10
minutes it runs at 2.5x). It stops by itself after 2 hours (`pd.durationSec`);
normally you stop it earlier. Watch PingDirectory, and when it starts failing,
press **Ctrl-C once**. The script stops JMeter cleanly and still builds the
report. (On Windows, answer **N** to "Terminate batch job?".)

> Running out of headroom on one load machine? See
> **Running across multiple machines** below to spread the load over several
> engines from one controller.

Each action can only go as fast as its connections allow: roughly
`threads / response time`. With 20 search threads at 10 ms that's about 2,000
searches/s. If the achieved rate in the report stops rising while errors stay at
0, raise `pd.searchThreads` (e.g. 100) and rerun.

While Test 2 runs, open a second terminal and watch the pods so you can see what
happened at the moment it broke:

```
kubectl get pods -n userstore-blue -l app.kubernetes.io/name=pingdirectory -o wide -w
kubectl top  pods -n userstore-blue -l app.kubernetes.io/name=pingdirectory
```

---

## Running across multiple machines (controller + remote engines)

One load machine can only push so hard. To go bigger, run JMeter in
**distributed mode**: one **controller** (where you run the script) drives
several **remote engines** (where the load is actually generated). The
controller collects every engine's results and builds one combined report — it
does **not** generate load itself.

Turning this on is one line in `settings.properties`:

```
pd.remoteEngines = 10.0.0.11,10.0.0.12,10.0.0.13
```

Leave it blank (the default) to run everything on one machine exactly as before.
Nothing else in how you run the tests changes — `./run-test1.sh` /
`./run-test2.sh` (or the `.bat` files) detect the setting and switch modes.

### Important: your rates are now PER ENGINE

The per-second rates and thread counts in `settings.properties` apply to **each
engine**. With 3 engines, `pd.searchPerSec = 25` pushes about **75/s in total**.
Divide your target by the number of engines, or just read the combined numbers
in the report. The same goes for the `threads / response-time` ceiling in
"Which test to use" — it is now that ceiling **times the number of engines**.

### One-time setup on each engine

Do this once per engine machine (Linux, macOS, or Windows):

1. **Install the same JMeter and Java** as the controller. The versions must
   match (the plans here are JMeter 5.6.3, Java 17+).
2. **Network:** the engine must be able to reach PingDirectory at
   `pd.hostWrite:pd.port` over LDAPS. (The controller does **not** need to — in
   distributed mode the script skips its own reachability check for that reason.)
3. **Read timeout** (so a hung PingDirectory is still recorded as a failure on
   the engine): create a file `jndi.properties` containing one line

   ```
   com.sun.jndi.ldap.read.timeout=30000
   ```

   and drop it in JMeter's `lib/` folder on the engine (that folder is on
   JMeter's classpath). Use the same number as `pd.readTimeoutMs`.
4. **LDAPS hostname check** (needed because `pd.hostWrite` is usually a load
   balancer IP not in the certificate): add this line to
   `<jmeter>/bin/system.properties` on the engine

   ```
   com.sun.jndi.ldap.object.disableEndpointIdentification=true
   ```
5. **Start the engine agent:** run `jmeter-server` (Linux/macOS) or
   `jmeter-server.bat` (Windows) and leave it running. On a trusted test network
   the simplest working config is to disable RMI SSL on **both** the controller
   and every engine — set this in `<jmeter>/bin/jmeter.properties`:

   ```
   server.rmi.ssl.disable=true
   ```

   If an engine has several network interfaces (or sits behind NAT), also start
   it with its own address: `jmeter-server -Djava.rmi.server.hostname=10.0.0.11`.
6. **Firewall:** the controller and engines talk over RMI. Allow the engine's
   port `1099` plus its callback port from the controller (and the return path
   back to the controller). On a locked-down network, pin the callback ports
   with `server.rmi.localport` (engine) and `client.rmi.localport` (controller)
   and open just those.

### Running it

On the controller, set `pd.remoteEngines`, fill in the usual four
`REPLACE_ME` values, and run as normal:

```
./run-test1.sh        (or run-test1.bat on Windows)
```

You'll see `>> Distributed mode: engines = ...` and then the test runs on all
engines at once.

### Where the output appears

Same place as a single-machine run — on the **controller**. The live
`summary + ... Err: ... Active: ...` lines are the **combined** figures across
all engines, printed to the controller's console and saved to
`out/testN/console.log` and `out/testN/jmeter.log`. `tail -f out/test2/console.log`
to watch. The engines' own consoles only show start/stop messages, not the
per-interval summaries.

> **Tip:** the combined console line can hide one struggling engine (the fleet
> average still looks fine). For per-engine, real-time graphs, add a JMeter
> **Backend Listener → InfluxDB → Grafana**; each engine reports tagged by host.
> At very high rates also set `mode=StrippedBatch` in each engine's
> `jmeter.properties` so streaming results back doesn't overload the controller.

### Stopping Test 2 cleanly

Press **Ctrl-C once** on the controller, same as before — the controller stops
the run, signals every engine, and still builds the report. If you ever need to
stop it from another window, run JMeter's own `bin/stoptest.sh` (or
`bin/shutdown.sh` for a graceful stop) on the controller.

---

## Cleaning up test records

Adds create records **directly under your base DN**, named `uid=e-...` (in
distributed mode the name also carries the engine's host, e.g.
`uid=e-<run>-<engine>-<n>`, so engines never collide — but they all still start
`uid=e-`). Deletes during the run remove some; if you add faster than you delete,
the rest stay after the run. To remove any leftovers, delete the `uid=e-*`
entries under your base DN (adjust host, port, bind, and base DN):

```
ldapsearch --hostname YOUR_HOST --port 1636 --useSSL --trustAll \
  --bindDN "YOUR_BIND_DN" --bindPassword "YOUR_PASSWORD" \
  --baseDN "ou=test,o=TUCUSTOMERSTAGE" --searchScope one "(uid=e-*)" "1.1" \
  | grep "^dn:" | sed "s/^dn: //" \
  | ldapdelete --hostname YOUR_HOST --port 1636 --useSSL --trustAll \
      --bindDN "YOUR_BIND_DN" --bindPassword "YOUR_PASSWORD"
```

(`ldapsearch` and `ldapdelete` ship with PingDirectory, in its `bin` folder. On
Windows use the `.bat` versions. Run the `ldapsearch` part alone first to see
what would be deleted.)

---

## First-time check (do this once)

Because JMeter's LDAP settings can vary slightly by version, do a quick check the
very first time on a new machine:

1. Open the `.jmx` file in the JMeter GUI (File > Open). It should load without
   errors.
2. Set small numbers in settings (search 5, add 1, delete 1), run Test 1 for a
   minute, and open the report.
3. Confirm the Search and Add rows are mostly green. If Add fails, check the bind
   login can create entries under `ou=test`, and the records appear under your base DN.

Once that looks good, set your real numbers.

---

## Good to know

- **LDAPS just works.** The test trusts PingDirectory's certificate automatically
  (`trustall`) and skips the hostname check, so pointing `pd.hostWrite` at a load
  balancer IP is fine. Before each run the script does a quick TLS handshake and
  stops with a clear message if the server isn't reachable. This is meant for
  test environments only. For plain LDAP (port 1389) instead of LDAPS, ask and
  I'll give you a plain build.
- **Lost connections heal themselves.** If PingDirectory drops a connection
  (restart, failover), that thread reconnects on its next request, so results
  recover when the server does. Reconnects appear as a `Reconnect` row.
- **Everything for a run lives in `out/test1` or `out/test2`**: report, raw
  results, and `jmeter.log` for troubleshooting.
- **Each run replaces the last report.** Copy the folder first to keep an old one.
- **The starting numbers are a sensible guess** based on recent production
  figures (mostly look-ups). Change them to whatever you want to test.
- **If Test 2 "breaks" but the pods look fine**, the limit is probably the machine
  running the test, not PingDirectory. Run it from a stronger machine - or spread
  it over several with **Running across multiple machines** above.

---

## What changed from the single-machine kit

If you used the earlier version, these are the only differences:

- New optional `pd.remoteEngines` setting turns on controller + remote-engine
  mode. Blank = unchanged single-machine behaviour.
- In distributed mode the run scripts **send** your settings to the engines
  (`-G`) instead of setting them locally (`-q`), so rates, host, bind and base DN
  actually reach the engines; and they skip the controller's own
  PingDirectory reachability check (the engines do the connecting).
- The created-entry DN now includes the engine host (`${__machineName}`), so
  multiple engines can't create the same DN. Cleanup is unchanged (`uid=e-*`).
- Read timeout and the LDAPS hostname-check flag must be set **on each engine**
  (the script can only set them on the controller) - see the engine setup steps.

---

## Full list of settings (optional)

| Setting | What it does | Default |
|---|---|---|
| `pd.searchPerSec` `pd.addPerSec` `pd.deletePerSec` `pd.modifyPerSec` | starting traffic per action, per second (0 = off) | 25 / 1 / 0 / 0 |
| `pd.searchFilter` | what each look-up searches for | `(uid=tommytester)` |
| `pd.modifyTargetDN` | which existing entry Modify updates | `uid=tommytester` |
| `pd.rampStepPercent` / `pd.rampStepSeconds` | Test 2 step size / interval | 30 / 120 |
| `pd.deleteStartDelaySec` | head start for adds before deletes begin | 10 |
| `pd.searchThreads` `pd.addThreads` `pd.deleteThreads` `pd.modifyThreads` | connections per action | 20 / 10 / 10 / 10 |
| `pd.durationSec` | run length (Test 1 / Test 2 maximum) | 1800 / 7200 |
| `pd.port` | LDAPS port | 1636 |
| `pd.readTimeoutMs` | a request with no reply within this time is recorded as a failure | 30000 |

To change one, open `settings.properties`, edit the value, save, run again.
