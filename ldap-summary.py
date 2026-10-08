"""Response-time summary of a JMeter results file, grouped by LDAP operation.

    python -I ldap-summary.py out/results.jtl              # BIND, SEARCH, ADD, ...
    python -I ldap-summary.py out/results.jtl --by-step    # one row per step label
    python -I ldap-summary.py out/results.jtl --by-group   # operation x thread group
    add  --csv out/summary.csv  to also save the table

Reads the CSV .jtl that `-l` writes (it needs the header row). The operation is the
first word of the sample label ("BIND - 04 user" -> BIND). Times are milliseconds
and include failed samples (an assertion failure still has a response time).
"""
import argparse
import csv
import math
import re
import sys

ORDER = ["BIND", "SEARCH", "ADD", "MODIFY", "DELETE", "UNBIND"]


def pct(sorted_vals, p):
    """Nearest-rank percentile."""
    if not sorted_vals:
        return 0
    k = max(1, math.ceil(p / 100 * len(sorted_vals)))
    return sorted_vals[k - 1]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("jtl")
    ap.add_argument("--by-step", action="store_true", help="one row per full label instead of per operation")
    ap.add_argument("--by-group", action="store_true", help="split each operation by thread group")
    ap.add_argument("--csv", help="also write the table to this CSV file")
    a = ap.parse_args()

    groups = {}
    first = last = None
    with open(a.jtl, newline="", encoding="utf-8-sig") as f:
        rd = csv.DictReader(f)
        need = {"timeStamp", "elapsed", "label", "success"}
        if not rd.fieldnames or not need <= set(rd.fieldnames):
            sys.exit(f"{a.jtl}: expected a CSV .jtl with a header containing {sorted(need)}; "
                     f"found {rd.fieldnames}")
        for r in rd:
            label = r["label"]
            if a.by_step:
                key = label
            else:
                key = label.split(" ", 1)[0].upper()
            if a.by_group:
                tg = re.sub(r" \d+-\d+$", "", r.get("threadName", ""))
                key = (key, tg)
            else:
                key = (key, "")
            ts = int(r["timeStamp"])
            end = ts + int(r["elapsed"])
            first = ts if first is None else min(first, ts)
            last = end if last is None else max(last, end)
            g = groups.setdefault(key, {"t": [], "err": 0})
            g["t"].append(int(r["elapsed"]))
            if r["success"].strip().lower() != "true":
                g["err"] += 1

    if not groups:
        sys.exit("no samples found")

    def sort_key(k):
        op = k[0].split(" ", 1)[0]
        return (ORDER.index(op) if op in ORDER else len(ORDER), k)

    span = max((last - first) / 1000.0, 0.001)
    cols = ["operation"] + (["thread group"] if a.by_group else []) + \
           ["samples", "errors", "err %", "avg", "min", "median", "p90", "p95", "p99", "max", "per sec"]
    rows = []
    for k in sorted(groups, key=sort_key):
        t = sorted(groups[k]["t"])
        n = len(t)
        e = groups[k]["err"]
        row = [k[0]] + ([k[1]] if a.by_group else []) + [
            n, e, f"{100.0 * e / n:.1f}", f"{sum(t) / n:.0f}", t[0], pct(t, 50),
            pct(t, 90), pct(t, 95), pct(t, 99), t[-1], f"{n / span:.2f}"]
        rows.append(row)

    widths = [max(len(str(x)) for x in [c] + [r[i] for r in rows]) for i, c in enumerate(cols)]
    fmt = lambda r: "  ".join(str(x).ljust(w) if i < (2 if a.by_group else 1) else str(x).rjust(w)
                             for i, (x, w) in enumerate(zip(r, widths)))
    print(fmt(cols))
    print("  ".join("-" * w for w in widths))
    for r in rows:
        print(fmt(r))
    print(f"\n{sum(len(g['t']) for g in groups.values())} samples over {span:.1f}s; times in ms")

    if a.csv:
        with open(a.csv, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(cols)
            w.writerows(rows)
        print(f"written {a.csv}")


if __name__ == "__main__":
    main()
