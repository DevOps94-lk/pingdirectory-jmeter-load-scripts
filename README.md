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

**Fill in these three lines** (replace REPLACE_ME):

```
pd.hostWrite = REPLACE_ME     <- the PingDirectory address (IP or hostname)
pd.bindDN    = REPLACE_ME     <- the login it should use (e.g. cn=directory manager)
pd.bindPw    = REPLACE_ME     <- the password for that login
```

**Then set how much traffic**, in operations per second. Each line is one action:

```
pd.searchPerSec = 25     <- look-ups per second
pd.addPerSec    = 1      <- new records created per second
pd.deletePerSec = 0      <- records removed per second
pd.modifyPerSec = 0      <- records changed per second
```

These are your **starting** numbers. Set any to `0` to switch that action off.
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

**Test 2 — find the breaking point.** Starts at your rates and pushes 30% harder
every 2 minutes, on and on. It does **not** stop by itself — you stop it. Watch
PingDirectory, and when it starts failing, press **Ctrl-C** to end it.

While Test 2 runs, open a second terminal and watch the pods so you can see what
happened at the moment it broke:

```
kubectl get pods -n userstore-blue -l app.kubernetes.io/name=pingdirectory -o wide -w
kubectl top  pods -n userstore-blue -l app.kubernetes.io/name=pingdirectory
```

---

## Cleaning up test records

Adds create records **directly under your base DN**, named `uid=e-...`. Deletes
during the run remove some; if you add faster than you delete, the rest stay
after the run. To remove any leftovers, delete the `uid=e-*` entries under your
base DN (adjust host, port, bind, and base DN):

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
  (`trustAll`) and skips the hostname check, so pointing `pd.hostWrite` at a load
  balancer IP is fine. Before each run the script does a quick TLS handshake and
  stops with a clear message if the server isn't reachable. This is meant for
  test environments only. For plain LDAP (port 1389) instead of LDAPS, ask and
  I'll give you a plain build.
- **Each run replaces the last report.** Copy the folder first to keep an old one.
- **The starting numbers are a sensible guess** based on recent production
  figures (mostly look-ups). Change them to whatever you want to test.
- **If Test 2 "breaks" but the pods look fine**, the limit is probably the machine
  running the test, not PingDirectory. Run it from a stronger machine.

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
| `pd.durationSec` | Test 1 run length | 1800 |
| `pd.port` | LDAPS port | 1636 |

To change one, open `settings.properties`, edit the value, save, run again.
