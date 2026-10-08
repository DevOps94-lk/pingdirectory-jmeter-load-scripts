# PingDirectory flow load test

Simulates real LDAP traffic: every worker thread repeatedly runs one **full user
lifecycle** (search, add, read, bind as the new user, modify, validate, delete,
confirm gone) and records response time, LDAP outcome and validation result for
every step. Works the same on Linux, macOS and Windows.

The kit is three files. Nothing else to install or maintain.

| File | What it is |
|---|---|
| `settings.properties` | The only thing you edit. Every value the test needs. |
| `pingdir-flow-steady.jmx` | Holds a fixed rate until you stop it. **Start here.** |
| `pingdir-flow-ramp.jmx` | Starts at your rate and keeps raising it until you stop it, to find the breaking point. |

---

## 0. One-time setup on every machine that connects to PingDirectory

That is the machine running the test if you use one machine, or **every engine** if
you use engines (the controller does not connect to PingDirectory).

Java and JMeter: use **Apache JMeter 5.6.3** on every machine, with the same Java
version everywhere. **Any Java your JMeter runs on is fine**: the kit uses no scripting
(no Groovy or other script engine), so it does not depend on the Java version.

Add these two lines to `<jmeter>/bin/system.properties` (JMeter reads this file at
start-up, including for `jmeter-server`), then restart JMeter / `jmeter-server`:

```
com.sun.jndi.ldap.object.disableEndpointIdentification=true
com.sun.jndi.ldap.read.timeout=30000
```

- The first skips the LDAPS **hostname** check, so `pd.hostWrite` can be a load
  balancer name or IP that is not in the certificate. (Trusting the certificate
  itself is built into the plan.)
- The second makes a request with no reply within 30 seconds count as a failure.
  JMeter's LDAP sampler has no read timeout of its own, so without it a hung server
  would never show up as an error.

No file editing wanted? Set them for one run instead: Linux/macOS
`JVM_ARGS="-Dcom.sun.jndi.ldap.object.disableEndpointIdentification=true -Dcom.sun.jndi.ldap.read.timeout=30000" jmeter ...`;
Windows PowerShell `$env:JVM_ARGS="-Dcom.sun.jndi.ldap.object.disableEndpointIdentification=true -Dcom.sun.jndi.ldap.read.timeout=30000"`
then run `jmeter ...` in the same window.

## 1. Set up (once) - only needed for remote engines

> **Running on one machine only?** Do section 0, skip sections 1 and 3, and go to
> **3A** (command line) or **3B** (JMeter GUI). No engines, RMI, firewall ports or `-G` are needed.

**Controller** (the machine you run the test from) **and every engine**:

- The **same Apache JMeter version (5.6.3)** and the same Java version on all of them (see section 0).
- Put the kit in a folder **without spaces in its path** (for example `C:\loadtest`
  or `/opt/loadtest`). It avoids quoting problems.

**Each engine**: start the agent and leave it running.

| | Command |
|---|---|
| Linux / macOS | `<jmeter>/bin/jmeter-server` |
| Windows | `<jmeter>\bin\jmeter-server.bat` |

Only one `jmeter-server` can run per machine (unless you give each its own port).

### 1a. RMI security: pick ONE option, same on every machine

JMeter 5.x encrypts controller-to-engine traffic by default and needs a keystore.
If you skip this step the engine refuses to start or the controller cannot connect.

- **Option A (simple, for a trusted test network).** Turn encryption off. In
  `<jmeter>/bin/jmeter.properties` on the **controller and every engine**, find the
  line `server.rmi.ssl.disable` (it is commented out), uncomment it and set:
  ```
  server.rmi.ssl.disable=true
  ```
- **Option B (encrypted).** On one machine run JMeter's `create-rmi-keystore`
  script (`create-rmi-keystore.sh` or `create-rmi-keystore.bat`, in `<jmeter>/bin`)
  and copy the `rmi_keystore.jks` it creates into `<jmeter>/bin` on the
  **controller and every engine**.

### 1b. Network and firewall

- Every **engine** must reach PingDirectory on `pd.hostWrite:pd.port` (LDAPS).
  The controller does not need to.
- The controller connects to each engine on port **1099**. Each engine then
  connects **back** to the controller on high-numbered ports to return results.
  Both directions must be open.
- By default those return ports are random, which firewalls block. **On Windows
  VMs (Windows Defender Firewall) and any locked-down network, fix them**:
  - Engine, in `<jmeter>/bin/jmeter.properties`: `server.rmi.localport=4000`
  - Controller, in `<jmeter>/bin/jmeter.properties`: `client.rmi.localport=4001`
    (JMeter uses up to three ports from there: 4001-4003)
  - Allow **inbound** TCP **1099 and 4000** on every engine, and **4001-4003** on
    the controller.
- If an engine has more than one network address or is behind NAT, start it with
  its own address set, for example Linux
  `JVM_ARGS="-Djava.rmi.server.hostname=10.0.0.11" ./jmeter-server`, Windows
  `set JVM_ARGS=-Djava.rmi.server.hostname=10.0.0.11` then `jmeter-server.bat`.

### 1c. Tell the controller where the engines are (pick one)

- **Once**, in the controller's `<jmeter>/bin/jmeter.properties`:
  `remote_hosts=10.0.0.11,10.0.0.12`, then run with `-r`.
- **Per run**: use `-R 10.0.0.11,10.0.0.12` instead of `-r`.

## 2. Fill in `settings.properties`

Replace every `REPLACE_ME`. The ones that matter:

| Setting | Meaning |
|---|---|
| `pd.hostWrite`, `pd.port` | PingDirectory address (LDAPS, default 1636) |
| `pd.bindDN`, `pd.bindPw` | The loadtester admin account |
| `pd.testOuDN` | The test OU. **Everything the test touches lives under it.** |
| `pd.userPassword` | One password for all test users. Must pass the password policy. |
| `pd.name.1`, `pd.name.2`, ... and `pd.nameCount` | Name templates, `First Last`. Number them with no gaps and set `pd.nameCount` to how many there are. |
| `pd.modify.cnSuffix`, `pd.modify.snSuffix` | What step 6 appends to `cn` / `sn`. Must differ. |
| `pd.flowsPerSec` | Target **full flows per second, total across all engines** |
| `pd.engineCount` | How many engines. The plan gives each engine its share. |
| `pd.threads` | Worker threads **per engine** |

Format rules: `key = value`, nothing after the value, no quotes, and a backslash
must be doubled (`\\`). **No spaces after a value**: a trailing space becomes part of
the value and breaks the connection. On Windows, edit with Notepad or any editor and
save as plain text. A preflight on every engine binds as the admin and checks the test
OU; if either fails, the run stops straight away and the `PRE` rows in the report show
why.

## 3. Run with remote engines

Run from the folder holding the three files, **on the controller**. Delete the old
`out` folder first (JMeter needs the report folder to be empty or missing).

**Linux / macOS**
```
rm -rf out && mkdir out
jmeter -n -t pingdir-flow-steady.jmx -Gsettings.properties -r \
       -l out/results.jtl -j out/jmeter.log -e -o out/report
```

**Windows (Command Prompt)**
```
rmdir /s /q out
mkdir out
jmeter -n -t pingdir-flow-steady.jmx -Gsettings.properties -r -l out\results.jtl -j out\jmeter.log -e -o out\report
```

**Windows (PowerShell)**
```
Remove-Item -Recurse -Force out -ErrorAction SilentlyContinue
New-Item -ItemType Directory out | Out-Null
jmeter -n -t pingdir-flow-steady.jmx -Gsettings.properties -r -l out\results.jtl -j out\jmeter.log -e -o out\report
```

If `jmeter` is not found, use the full path, e.g. `C:\apache-jmeter-5.6.3\bin\jmeter.bat`.
To use `-R` instead of `-r`, replace `-r` with `-R 10.0.0.11,10.0.0.12`.

**Why `-Gsettings.properties` is required** (no space between `-G` and the file
name). A plain `-r` sends the plan to the engines but **not** your settings; every
engine would silently fall back to defaults (no host, no password). `-G` is
JMeter's way to send a properties file to all engines.

Use `pingdir-flow-ramp.jmx` the same way for the breaking-point test.

The test **runs until you stop it**. Watch the controller's console: the
`summary +` lines show combined throughput and errors every 30 seconds across all
engines.

## 3A. Run on one machine (no engines), command line

The same files work on a single machine. That machine generates all the load, so
none of section 1 applies (no `jmeter-server`, RMI option, firewall ports or
`remote_hosts`). Do section 0 on this machine, and make sure it can reach PingDirectory on LDAPS.

In `settings.properties` set `pd.engineCount = 1`. Then use `-q settings.properties`
(loads the file into this JMeter) and **leave out** `-G` and `-r`:

**Linux / macOS**
```
rm -rf out && mkdir out
jmeter -n -t pingdir-flow-steady.jmx -q settings.properties \
       -l out/results.jtl -j out/jmeter.log -e -o out/report
```

**Windows (Command Prompt)**
```
rmdir /s /q out
mkdir out
jmeter -n -t pingdir-flow-steady.jmx -q settings.properties -l out\results.jtl -j out\jmeter.log -e -o out\report
```

**Windows (PowerShell)** (note: the Command Prompt lines above do not work in PowerShell)
```
Remove-Item -Recurse -Force out -ErrorAction SilentlyContinue
New-Item -ItemType Directory out | Out-Null
jmeter -n -t pingdir-flow-steady.jmx -q settings.properties -l out\results.jtl -j out\jmeter.log -e -o out\report
```

If `jmeter` is not found, use the full path, e.g.
`& "C:\apache-jmeter-5.6.3\bin\jmeter.bat" -n -t ...` in PowerShell.

Stop it from a second terminal on the same machine with `shutdown` (section 4).
Everything else (preflight, certificate trust, report, row names) is identical.

**Limit of one machine:** the load generator's CPU, memory and network cap the
rate and thread count. If the achieved rate stays below `pd.flowsPerSec` while
errors are about 0, raise `pd.threads`. If the machine itself is maxed out, the
limit is the load generator, not PingDirectory: that is when to move to engines.

## 3B. Run from the JMeter GUI

Use the GUI for a first look, a smoke test (README section 6) or debugging. For real
load use the command line (3 or 3A): JMeter's GUI uses extra CPU and memory and can
skew results.

1. **Start JMeter with your settings loaded.** The GUI has no place to type them,
   and without them every value falls back to a default so the preflight stops the
   run. From the kit folder:
   ```
   jmeter -q settings.properties
   ```
   (PowerShell without `jmeter` on PATH:
   `& "C:\apache-jmeter-5.6.3\bin\jmeter.bat" -q settings.properties`.)
   The file is read once at startup: if you edit it, close JMeter and relaunch.
2. **Open the plan:** File > Open > `pingdir-flow-steady.jmx` (or the ramp plan).
   For one machine, keep `pd.engineCount = 1`.
3. **Add a results listener** (the plan ships without one): right-click the top node
   **PingDirectory flow ...** > Add > Listener > **Summary Report**. Then:
   - type `out\results.jtl` in "Filename" (create an `out` folder first),
   - click **Configure** next to it and tick **Response Code**, **Response Message**
     and **Assertion failure message** (plus Latency and Connect Time if offered), so
     the LDAP result codes are saved,
   - the Summary Report itself shows only counts, times and Error % (no response
     codes and no colours). The codes are in the HTML report (step 6).
   Avoid View Results Tree: it slows the run and uses a lot of memory.
4. **Start:** the green Start button (or Run > Start). The Summary Report shows
   per-step counts, averages and error % live. The test runs until you stop it.
5. **Stop:** Run > **Shutdown** (use this). Threads stop after the step they are on, then the
   cleanup sweep deletes any test users left behind (section 4). The red Stop button
   is immediate; the sweep should still run afterwards, but prefer Shutdown.
6. **HTML report:** Tools > Generate HTML report. Choose `out\results.jtl`, keep
   the default `user.properties`, and pick an **empty or new** output folder. Open
   its `index.html`.

**Remote engines from the GUI:** launch with
`jmeter -Gsettings.properties -q settings.properties`, then use Run > **Remote Start**
(or Remote Start All). `-G` is what sends your settings to the engines; section 1
still has to be done.

## 4. Stop

Open a **second terminal on the controller** and run:

| | Graceful (use this) | Immediate |
|---|---|---|
| Linux / macOS | `<jmeter>/bin/shutdown.sh` | `<jmeter>/bin/stoptest.sh` |
| Windows | `<jmeter>\bin\shutdown.cmd` | `<jmeter>\bin\stoptest.cmd` |

**What stopping does.** JMeter stops each thread after the step it is currently on,
**not at the end of its flow** (graceful and immediate behave the same way here, the
graceful one just lets the current step finish). So a flow can be cut off between
`02 Add user` and `08 Admin delete user`. That is why the plan ends with a
**cleanup sweep** (a tearDown group, rows labelled `TD ...`): once the threads are
gone, each engine binds as the admin and deletes every entry in the test OU that
carries the `pd.description` marker and has that engine's name in its uid. Check the
`TD delete leftover` rows in the results: one row per entry removed.

**Do not close the window or press Ctrl-C** to stop; use the scripts so JMeter runs
the sweep and builds the report. If a run is killed some other way, the sweep never
runs; the next run's sweep (same machine) removes those leftovers, or use section 7.

## 5. Create and read the report

### 5.1 Creating the HTML report

The report is built from the results file `out/results.jtl`. It holds every step's
response time, LDAP response code, message and validation result.

**Automatically (command line, sections 3 and 3A).** The run commands already end with
`-l out/results.jtl -e -o out/report`. When you stop the test, JMeter builds
`out/report/index.html` by itself. With engines, this happens on the controller.
Before every run the report folder must not exist or must be empty:

- Linux / macOS: `rm -rf out/report`
- PowerShell: `Remove-Item -Recurse -Force out\report -ErrorAction SilentlyContinue`
- cmd.exe: `rmdir /s /q out\report`

(Keep `out/results.jtl` too: delete or rename it before a new run, or the new results are
appended to the old ones.)

**From the GUI (section 3B).** After the run: Tools > Generate HTML report. Choose
`out\results.jtl`, keep the default `user.properties`, and pick a new or empty folder.

**Rebuilding later from a saved results file** (for example to change the report settings
or to build the report from a GUI run). Same folder rule applies:

```
jmeter -q settings.properties -g out/results.jtl -o out/report
```

(PowerShell: `jmeter -q settings.properties -g out\results.jtl -o out\report`.) Passing
`-q settings.properties` applies the Reporting section of that file (hides the `PRE` and `TD`
rows, chart resolution, Apdex thresholds).

**Opening and sharing.** Open `out/report/index.html` in any browser. To share it, zip the
whole `out/report` folder (the page needs the files beside it).

### 5.2 Reading the report

Open `out/report/index.html`. Every step has its own row, numbered in order:

| Row | Step | Passes when |
|---|---|---|
| `00 Admin bind` | Admin connects **once per thread** and that connection is kept for the whole test (it is re-bound only if the connection breaks) | bind succeeds |
| `01 Admin search (generic)` | Search of the test OU | search succeeds |
| `02 Add user` | Admin adds the test user | add succeeds |
| `03 Admin read added user` | Admin reads it back | found, and uid / cn / mail / description match what was added |
| `04 User bind` | The new user binds with the shared password on its **own connection** (held by this thread's partner thread; the admin connection is untouched) | bind succeeds (a wrong password shows LDAP code 49) |
| `05 User self-search` | The user searches for its own entry over that connection | its own entry is returned |
| `05.1 User unbind` | The user disconnects | unbind succeeds |
| `06 Admin modify cn+sn` | Admin updates cn and sn | modify succeeds |
| `07 Admin read + validate modify` | Admin reads it again | found, **cn shows the new value, sn shows the new value** |
| `08 Admin delete user` | Admin deletes it | delete succeeds |
| `09 Admin read (must not exist)` | Admin looks for it | **not found** (finding it is a failure) |
| **`FLOW - full loop duration`** | One whole loop, start to finish | every step above passed |

**The admin connection persists.** Each flow thread binds the admin once (`00`) and uses that
same connection for every admin step of every loop. JMeter's LDAP sampler can hold only one
connection per thread, so a user who bound in the same thread would replace the admin's.
Instead, each flow thread has a **partner thread** (the second thread group in the plan,
"User sessions"). Per loop the flow thread hands it the new user's uid, the partner does `04`,
`05` and `05.1` on its own connection, and hands back; the flow thread waits meanwhile. The
admin connection is never replaced. It is re-bound only if it breaks (a `Closing previous
context` line in the log). Because of the partners, JMeter shows twice `pd.threads` threads
(half of them mostly idle). If a partner does not finish within `pd.userStepTimeoutMs`, the loop
records a failed row `04-05.1 TIMEOUT ...` and carries on.

**Step 10 (admin disconnect)** happens when the test ends: JMeter closes every thread's admin
connection then (`Tidying old Context` in the log). It has no row of its own because a stopped
thread cannot report a step. The `FLOW` row measures the whole loop including the user steps,
but it shows pass or fail for the admin steps only: read the `04`, `05` and `05.1` rows for the user steps.

Rows beginning `PRE` are the one-time preflight on each engine. Rows beginning `TD` are the
end-of-test cleanup sweep. Both are left out of the HTML report on purpose (see the
Reporting section of `settings.properties`) but appear in the Summary Report listener.

### How each metric is reported

| You want | Where in the HTML report |
|---|---|
| **Loop duration** | Statistics table, row `FLOW - full loop duration` (average, median, 90/95/99th percentile, min, max). Charts: Response Times Over Time, Response Time Percentiles. |
| **Response time per step** | Statistics table, one row per step `00`-`10`, same columns. |
| **LDAP response codes** | **Errors table** and **Top 5 Errors by Sampler**: step, LDAP code and message, count (see below). **Response Codes per Second** chart: `0` against any failure code over time. |
| **Attribute validation** (steps 03, 07, 09) | **Error %** on those rows (see below for how a failure reads). |
| **Flows per second achieved vs target** | **Transactions per Second** chart for `FLOW` and the Throughput column. If it stays under `pd.flowsPerSec` while errors are ~0, raise `pd.threads`. |
| **Concurrency** | Active Threads Over Time chart. |

**Reading LDAP response codes.** The LDAP sampler records the real LDAP result code:

| Code shown | Meaning |
|---|---|
| `0` (message `Success`) | The operation succeeded. Successes are not listed in the Errors table: **samples minus errors = successes**. |
| ` 49`, ` 32`, ` 68` ... (a leading space is normal) | The server's LDAP result code, e.g. 49 invalid credentials, 32 no such object, 68 entry already exists, 50 insufficient access. |
| `800` | The connection was lost or refused (no LDAP code came back). |
| `500` | Any other error inside JMeter. |

**Reading a validation failure.** If steps `03`, `07` or `09` fail a check, the LDAP
operation itself worked (code `0`), so JMeter's report lists the error type as
`0/Success` on that step's row. The row tells you which check failed:

- `03` = the entry read back does not match what was added,
- `07` = cn or sn does not show the new value,
- `09` = the deleted entry still exists.

The exact message (e.g. `VALIDATION FAILED: cn does not show the updated value`) is
in the results file; View Results Tree or the `failureMessage` column of
`out/results.jtl` shows it.

Other things to look at: **Over Time** charts show where errors or response times
climb. In the ramp test that moment is the breaking point.

**Failure behaviour inside a flow.** If a step fails, steps that depend on it are
skipped, and the flow still tries to delete the user and confirm it is gone, so
test entries are not left behind. If `02 Add user` itself fails, the rest of that
flow is skipped.

## 6. First run (do this once, at a low rate)

This kit was built without the chance to run JMeter against a directory server, so
a few behaviours depend on how JMeter's LDAP sampler acts with PingDirectory. Run
the steady plan for a few minutes at a very low rate first (for example
`pd.flowsPerSec = 1`, `pd.threads = 5`, `pd.engineCount = 1`) and check:

1. **The run starts.** If the preflight fails, the `PRE` rows show the error (wrong
   host, bad admin password, test OU not found). If an engine cannot be reached,
   re-check section 1 (RMI option, firewall ports, `remote_hosts`).
2. **Every step passes.** Steps `00`-`09` should show 0% errors on a healthy
   directory, and there should be no `04-05.1 TIMEOUT` row (it would mean the partner
   thread did not answer: send me the log). If `04 User bind` fails, check the shared password against the
   password policy and that the user may bind. If `05 User self-search` fails with
   `VALIDATION FAILED: user could not read its own entry`, the user's access
   controls do not let it read its own entry.
3. **The LDAP codes are captured.** To prove it, run one flow with a wrong
   `pd.userPassword`: step `04 User bind` must appear in the Errors table with
   code `49` (invalid credentials), `05` and `05.1` are skipped, and the modify,
   delete and cleanup steps still run. Then set the password back. (Separately, confirm a
   healthy run shows 0% errors on `00`-`09`.)
4. **Nothing is left behind.** After a Shutdown, search the test OU for `(description=PD-LOADTEST)`: it should return nothing. If the sweep rows `TD ...` show errors, send them to me.
5. **Step 09 passes.** A deleted user must read as not found.
6. **Connections stay flat.** Watch the number of connections to PingDirectory from
   the test (PingDirectory's connection monitor; on Linux `ss -tn | grep :1636`; on
   Windows `netstat -an | find ":1636"`). It should level off at roughly one per
   thread (the admin connections) plus one short-lived user connection per thread while it is in steps 04-05.1, not climb.

In `jmeter.log`, each thread opens its admin connection once. A line
`WARN ... Closing previous context for thread` means that thread had to **re-bind** the
admin (its connection broke). It should be rare; if you see it on every flow, send me the log.
At the end of the test JMeter closes every remaining connection (`Tidying old Context`);
that is the admin disconnect.

## 7. Clean up leftovers

Each flow deletes its own user (step 08), and the cleanup sweep at the end of the test
deletes any that stopping or a failed step left behind, so normally nothing remains. If
something does (a killed JMeter, an engine that lost power), they all carry the marker in
`pd.description` (default `PD-LOADTEST`). Remove them with the commands below.

**Linux / macOS**
```
ldapsearch --hostname YOUR_HOST --port 1636 --useSSL --trustAll \
  --bindDN "YOUR_BIND_DN" --bindPassword "YOUR_PASSWORD" \
  --baseDN "YOUR_TEST_OU_DN" --searchScope one "(description=PD-LOADTEST)" "1.1" \
  | grep "^dn:" | sed "s/^dn: //" \
  | ldapdelete --hostname YOUR_HOST --port 1636 --useSSL --trustAll \
      --bindDN "YOUR_BIND_DN" --bindPassword "YOUR_PASSWORD"
```

**Windows**: run the `ldapsearch.bat` part alone first (same arguments) to list
the DNs, then delete them with `ldapdelete.bat`, or filter and delete from a
Linux/macOS machine with the command above.

(`ldapsearch` and `ldapdelete` ship in PingDirectory's `bin` folder. Always run the
search part alone first to see what would be deleted.)

## 8. Good to know

- **Certificate trust is automatic.** Every LDAPS connection trusts whatever
  certificate PingDirectory presents (no truststore needed), and the plan also
  skips the LDAPS hostname check, so `pd.hostWrite` can be a load balancer IP. This
  is for test environments only.
- **Load is split for you.** `pd.flowsPerSec` is the total target. Each engine runs
  `pd.flowsPerSec / pd.engineCount`. If the achieved rate in the report stays below
  the target while errors are about 0, raise `pd.threads`.
- **Hung server shows up as failures.** Requests with no reply within 30 seconds are
  recorded as failures (the read timeout set in section 0).
- **What the preflight does** (once per engine, before any load): binds as the admin and
  confirms the test OU exists. If either fails, the whole run stops immediately.
- **Uniqueness.** Every test uid contains a run timestamp, the engine's hostname
  and a counter, so engines and reruns never collide.
- **Step 1 size limit.** If you set `pd.step1SizeLimit` and the OU holds more
  entries, step 1 is recorded as a failure (JMeter's behaviour when a limit is hit).
