#!/bin/bash
# ============================================================================
#  regress_ghdl.sh - seed / MAX_BURST_BEATS regression with GHDL (Linux)
#
#  Usage (from the repository root):
#     scripts/regress_ghdl.sh                 # default 62-run campaign
#     scripts/regress_ghdl.sh 1:256 7:16      # explicit SEED:MAX_BEATS list
#
#  Output: build/ghdl/sim_s<seed>_b<beats>.log and reports/regression_ghdl.csv
#  A run counts as PASS only if its log contains "ALL TESTS PASSED".
#  Tested with GHDL 4.1.0 (mcode backend), option --std=08.
# ============================================================================
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$ROOT/build/ghdl
CSV=$ROOT/reports/regression_ghdl.csv
mkdir -p "$WORK" "$ROOT/reports"
cd "$WORK"

RTL="dma_pkg dma_burst_planner dma_burst_buffer dma_axi_lite_regs dma_engine dma_top"
for f in $RTL; do ghdl -a --std=08 "$ROOT/rtl/$f.vhd" || exit 1; done
ghdl -a --std=08 "$ROOT/tb/tb_dma_top.vhd" || exit 1
ghdl -e --std=08 tb_dma_top || exit 1

if [ $# -gt 0 ]; then CONFIGS="$*"; else
  CONFIGS=""
  for s in $(seq 1 50); do CONFIGS="$CONFIGS $s:256"; done
  for s in 1 2 3 4 5; do CONFIGS="$CONFIGS $s:16 $s:64"; done
  CONFIGS="$CONFIGS 1:1 2:1"
fi

echo "seed,max_beats,result,tests,end_time_ns" > "$CSV"
npass=0; nfail=0
for C in $CONFIGS; do
  S=${C%%:*}; B=${C##*:}; L=$WORK/sim_s${S}_b${B}.log
  ghdl -r --std=08 tb_dma_top -gG_SEED=$S -gG_MAX_BEATS=$B > "$L" 2>&1
  if grep -q "ALL TESTS PASSED" "$L"; then
    N=$(grep "ALL TESTS PASSED" "$L" | sed -E 's/.*count=([0-9]+).*/\1/')
    T=$(grep "ALL TESTS PASSED" "$L" | sed -E 's/.*@([0-9]+)ns.*/\1/')
    echo "$S,$B,PASS,$N,$T" >> "$CSV"; npass=$((npass+1))
  else
    echo "$S,$B,FAIL,0," >> "$CSV"; nfail=$((nfail+1))
    echo "FAIL seed=$S max_beats=$B:"; grep -E "failure|error" "$L" | head -3
  fi
done
echo "PASS=$npass FAIL=$nfail  ->  $CSV"
[ $nfail -eq 0 ]
