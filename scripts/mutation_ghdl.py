#!/usr/bin/env python3
"""Mutation check of the testbench with GHDL (Linux).

Each mutant injects one realistic RTL bug. The testbench must stop with an
assertion failure for every mutant; a mutant that still reaches
"ALL TESTS PASSED" is a hole in the verification.

Usage (from the repository root):  python3 scripts/mutation_ghdl.py
Output: reports/mutation_ghdl.csv
"""
import csv
import os
import re
import shutil
import subprocess
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RTL = ["dma_pkg", "dma_burst_planner", "dma_burst_buffer",
       "dma_axi_lite_regs", "dma_engine", "dma_top"]

# (label, file, original text, mutated text)
MUTANTS = [
    ("Ignore unexpected RID", "dma_engine.vhd",
     "if s.rlast/=expect_last or s.rid/=\"0\" then",
     "if s.rlast/=expect_last then"),
    ("Ignore unexpected BID", "dma_engine.vhd",
     "if s.bid/=\"0\" then ec<=to_unsigned(6,32);",
     "if false then ec<=to_unsigned(6,32);"),
    ("Accept a missing RLAST", "dma_engine.vhd",
     "if s.rlast/=expect_last or s.rid/=\"0\" then",
     "if (s.rlast='1' and expect_last='0') or s.rid/=\"0\" then"),
    ("Bursts half the planned size", "dma_engine.vhd",
     "nbeats<=planned;",
     "nbeats<=(planned+1)/2;"),
    ("RAM prefetch ignores WREADY (WDATA changes in a stall)", "dma_engine.vhd",
     "if s.wready='1' and wi<nbeats-1 then ram_re<='1';",
     "if wi<nbeats-1 then ram_re<='1';"),
    ("DONE without waiting for BVALID", "dma_engine.vhd",
     "          when B_RESP =>\n            if s.bvalid='1' then",
     "          when B_RESP =>\n            if true then"),
    ("No 4 KiB split on the source side", "dma_burst_planner.vhd",
     "    if n>sr then n:=sr; end if;\n", ""),
    ("SLVERR reported as DECERR on R", "dma_engine.vhd",
     "if s.rresp=\"10\" then e:=to_unsigned(2,32);",
     "if s.rresp=\"10\" then e:=to_unsigned(3,32);"),
    ("Segment written after an R error", "dma_engine.vhd",
     "if e/=0 then error_event<='1';state<=IDLE;",
     "if false then error_event<='1';state<=IDLE;"),
    ("ARVALID withdrawn after a long wait", "dma_engine.vhd",
     "      when AR_REQ => v.arvalid:='1';",
     "      when AR_REQ => if cycles<500 then v.arvalid:='1'; end if;"),
    ("START accepted while BUSY", "dma_axi_lite_regs.vhd",
     "if busy='1' or (masked(0)='1' and masked(1)='1') then resp_v:=\"10\";",
     "if (masked(0)='1' and masked(1)='1') then resp_v:=\"10\";"),
    ("Overlapping source and destination accepted", "dma_pkg.vhd",
     "(se<=resize(unsigned(dst),33) or de<=resize(unsigned(src),33))",
     "true"),
]


def run(cmd, cwd, timeout=300):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)


def main():
    rows = []
    for label, fname, old, new in MUTANTS:
        work = tempfile.mkdtemp(prefix="mut_")
        try:
            os.mkdir(os.path.join(work, "rtl"))
            for f in RTL:
                shutil.copy(os.path.join(ROOT, "rtl", f + ".vhd"), os.path.join(work, "rtl"))
            path = os.path.join(work, "rtl", fname)
            src = open(path).read()
            if src.count(old) != 1:
                rows.append((label, fname, "PATTERN NOT FOUND", ""))
                continue
            open(path, "w").write(src.replace(old, new))
            files = [os.path.join("rtl", f + ".vhd") for f in RTL]
            files.append(os.path.join(ROOT, "tb", "tb_dma_top.vhd"))
            if run(["ghdl", "-a", "--std=08"] + files, work).returncode or \
               run(["ghdl", "-e", "--std=08", "tb_dma_top"], work).returncode:
                rows.append((label, fname, "BUILD ERROR", ""))
                continue
            try:
                out = run(["ghdl", "-r", "--std=08", "tb_dma_top"], work).stdout
            except subprocess.TimeoutExpired:
                rows.append((label, fname, "DETECTED", "timeout"))
                continue
            if "ALL TESTS PASSED" in out:
                rows.append((label, fname, "NOT DETECTED", ""))
            else:
                last = re.findall(r"PASS (\d+) ", out)
                fail = re.search(r"\((?:assertion|report) failure\): (.*)", out)
                where = f"test {int(last[-1]) + 1}" if last else "test 1"
                msg = fail.group(1).strip() if fail else "simulation stopped"
                rows.append((label, fname, "DETECTED", f"{where}: {msg}"))
        finally:
            shutil.rmtree(work, ignore_errors=True)
        print(f"{rows[-1][2]:13s} {label}")
    os.makedirs(os.path.join(ROOT, "reports"), exist_ok=True)
    out_csv = os.path.join(ROOT, "reports", "mutation_ghdl.csv")
    with open(out_csv, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["mutant", "file", "result", "first_failure"])
        w.writerows(rows)
    detected = sum(r[2] == "DETECTED" for r in rows)
    print(f"{detected}/{len(rows)} mutants detected -> {out_csv}")


if __name__ == "__main__":
    main()
