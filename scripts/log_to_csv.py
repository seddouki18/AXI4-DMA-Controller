#!/usr/bin/env python3
"""Turn a tb_dma_top simulation log (GHDL or XSim) into a per-test CSV.

Usage:  python3 scripts/log_to_csv.py <sim.log> <out.csv> [seed] [max_beats]

Columns follow the guide's log structure: one row per PASS line, with the
copy size and CYCLE_COUNT taken from the METRIC note printed just before it.
"""
import csv
import re
import sys

PASS_RE = re.compile(r"PASS (\d+) (.+?)\s*$")
METRIC_RE = re.compile(r"METRIC bytes=(\d+) cycles=(\d+)")
GHDL_TIME_RE = re.compile(r"@(\d+)ns")
XSIM_TIME_RE = re.compile(r"^Time: (\d+) ns")


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    log, out = sys.argv[1], sys.argv[2]
    seed = sys.argv[3] if len(sys.argv) > 3 else "1"
    beats = sys.argv[4] if len(sys.argv) > 4 else "256"
    rows, metric, pending = [], None, None
    with open(log, errors="replace") as fh:
        for line in fh:
            line = line.rstrip("\r\n")
            t = XSIM_TIME_RE.match(line)
            if t and pending is not None:        # XSim prints the time on the next line
                pending["end_time_ns"] = t.group(1)
                pending = None
                continue
            m = METRIC_RE.search(line)
            if m:
                metric = (int(m.group(1)), int(m.group(2)))
                continue
            p = PASS_RE.search(line)
            if p and "ALL TESTS PASSED" not in line:
                row = {"test": p.group(1), "name": p.group(2), "seed": seed,
                       "version": "V1", "max_beats": beats,
                       "bytes": "", "cycles": "", "bytes_per_cycle": "",
                       "end_time_ns": "", "result": "PASS"}
                if metric:
                    row["bytes"], row["cycles"] = metric
                    row["bytes_per_cycle"] = f"{metric[0] / metric[1]:.3f}"
                    metric = None
                g = GHDL_TIME_RE.search(line)
                if g:
                    row["end_time_ns"] = g.group(1)
                else:
                    pending = row
                rows.append(row)
    fields = ["test", "name", "seed", "version", "max_beats", "bytes", "cycles",
              "bytes_per_cycle", "end_time_ns", "result"]
    with open(out, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)
    print(f"{len(rows)} tests -> {out}")


if __name__ == "__main__":
    main()
