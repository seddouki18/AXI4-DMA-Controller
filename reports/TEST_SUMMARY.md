# Test summary and coverage (V1)

## Results

| Campaign | Simulator | Configurations | Result | Evidence |
|---|---|---|---|---|
| Full suite, seed 1, MAX_BURST_BEATS = 256 | Vivado 2018.2 XSim | 1 | 87 / 87 tests PASS, end at 1 521 975 ns | `scripts/run_sim.bat`, [archived XSim log](xsim_reference.log) |
| Same suite | GHDL 4.1.0 | 1 | 87 / 87 PASS, same end time | `tests_seed1_b256.csv` |
| Seed and burst-size campaign | GHDL 4.1.0 | 62 runs: seeds 1 to 50 at 256 beats, seeds 1 to 5 at 16 and 64 beats, seeds 1 and 2 at 1 beat | 62 / 62 PASS | `regression_ghdl.csv` |
| Mutation check (12 injected RTL bugs) | GHDL 4.1.0 | 12 mutants | 12 / 12 detected | `mutation_ghdl.csv` |

A run is PASS only when its log contains `ALL TESTS PASSED`. Any assertion stops the run with
severity failure. The seed changes the random stalls of the memory model and the 40 random
commands (size, source and destination).

## Checks active in every test

| Checker | What it enforces |
|---|---|
| Memory model (scoreboard) | After each copy, **all 32 768 words** of memory are compared: the destination range must hold the source pattern and every other word must be unchanged (no write outside the destination). |
| Memory model (protocol) | AxSIZE = 2, INCR, ID = 0; 4-byte aligned; no burst crosses 4 KiB; burst length <= MAX_BURST_BEATS; one read and one write outstanding at most; WSTRB = 1111; WLAST exactly on the last beat; no W before AW. |
| Stability monitor | AR, AW and W payloads stable while VALID and not READY; same for the slave R and B channels and the AXI4-Lite B and R channels. |
| Command checks | Number of bursts equals the guide's planner formula; R, W and B beat counts; BYTES_COMMITTED = LEN. |
| Terminal check | DONE xor ERROR as expected, correct LAST_ERROR, and the AXI side idle at DONE (no DONE before the last B). |
| Progress watchdog | Fails with a diagnostic if the DMA offers or waits for 1000 cycles without any handshake, except in the E07 tests where the hang is expected. |
| Global watchdog | Stops the simulation after 50 ms. |

## Coverage of the guide's test list

| Guide ID | Scenario | Tests (number in the log) |
|---|---|---|
| T01 | Reset, register map, no master VALID | 1, 75 |
| T02 | 4 bytes: 1 R, 1 W, LAST on first beat, 1 B | 5 |
| T03 | 1024 aligned bytes: one 256-beat burst | 8 |
| T04 | 1028 bytes: bursts of 256 then 1 | 9 |
| T05 | 1020, 2048, 4096, 8192 bytes (and 32 KiB) | 7, 76, 77, 14, 13 |
| T06 | Source boundary at 0x1FF0 | 10 |
| T07 | Destination boundary at 0x8FF8 | 11 |
| T08 | Two offset boundaries, split 2, 2, 28 | 12 ([boundary waveform](../docs/images/waveforms/xsim-4k-boundaries.png)) |
| T09 | Delayed ARREADY / AWREADY, stable payload | 14 to 77 (random stalls), 73, 85 |
| T10 | WREADY low on first, middle, last beat | 78, 79, 80 ([last-beat waveform](../docs/images/waveforms/xsim-last-beat-stall.png)) |
| T11 | RVALID gaps, late BVALID, no DONE before B | 14 to 77 (random stalls), 62, 87 |
| T12 | Simultaneous random stalls, random seed | 14, 15 to 54 (40 random commands), 62-run seed campaign |
| T13 | AXI4-Lite AW before W and W before AW | 2, and every SRC / DST write (skew +2 / -2) |
| T14 | Partial WSTRB and WSTRB = 0 | 2 |
| T15 | Length 0, length not a multiple of 4 | 55, 56 |
| T16 | Unaligned addresses, address overflow | 57, 58, 59, 60 |
| T17 | Overlapping source and destination | 61 |
| T18 | START or reconfiguration while BUSY | 62 |
| T19 | Successive commands without reset | 5 to 61 run back to back; status cleared at each START |
| T20 | SOFT_RESET idle (accepted) and while BUSY (refused) | 4, 62 |
| E01 | RRESP SLVERR on first, middle, last beat | 63, 64, 65 |
| E02 | RRESP DECERR; BRESP SLVERR and DECERR | 66, 67, 68; 69, 70 |
| E03 | Read error during a write | V2 only (needs read/write overlap) |
| E04 | B error while ARVALID is blocked | V2 only (V1 never issues AR before the B of the previous burst) |
| E05 | Early, late or missing RLAST; unexpected RID / BID | 72 (early), 81 (missing), 82 (RID), 83 (BID), 84 (restart) |
| E06 | Global reset with an active transaction | 73, 74 |
| E07 | Slave stops responding | 85 (AR), 86 (W mid-burst), 87 (B) |

Extra tests: 3 (unknown offset, write to a read-only register, START with SOFT_RESET),
71 (unexpected EXOKAY on R).

## Mutation check

Each mutant injects one bug into the RTL; the testbench must fail. All 12 are detected.

| Injected bug | Detected in test | First failing check |
|---|---|---|
| Ignore an unexpected RID | 82 | Expected ERROR only |
| Ignore an unexpected BID | 83 | Expected ERROR only |
| Accept a missing RLAST | 81 | Expected ERROR only |
| Bursts half the planned size | 6 | Unexpected number of bursts |
| RAM prefetch ignores WREADY (WDATA changes in a stall) | 14 | W changed while stalled |
| DONE without waiting for BVALID | 5 | Terminal before AXI completion |
| No 4 KiB split on the source side | 10 | AR alignment / 4 KB boundary |
| SLVERR reported as DECERR on R | 63 | Bad error code |
| Segment written after an R error | 63 | Expected ERROR only |
| ARVALID withdrawn after a long wait | 9 | E07 watchdog: no AXI handshake for 1000 cycles |
| START accepted while BUSY | 62 | Wrong AXI-Lite BRESP |
| Overlapping source and destination accepted | 61 | Wrong AXI-Lite BRESP |

## Tools and parameters

| Item | Value |
|---|---|
| Vivado | v2018.2 (64-bit), SW Build 2258646, Windows 10; XSim for simulation |
| Part | xc7z020clg400-1 (Zynq-7000, speed grade -1) |
| GHDL | 4.1.0, `--std=08`, Linux |
| Language | VHDL-2008 (RTL and testbench) |
| Testbench generics | `G_SEED` (default 1), `G_MAX_BEATS` (default 256) |
| Memory model | 32 768 words; first R beat 1 cycle after AR; BVALID 7 cycles after the last W beat (handshake on the 8th); optional random stalls on every READY / VALID of the slave |
| Clock in simulation | 100 MHz (10 ns) |
