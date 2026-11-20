# Reproducing the project

[Back to the project](../README.md) · [Verification](VERIFICATION.md) · [Results](RESULTS.md)

The repository includes the six RTL modules, both testbenches, simulation and build scripts, constraints, and the supplied reference reports. Generated Vivado caches and simulator executables are not needed: the scripts rebuild their outputs from the checked-in sources.

The reference tool versions are **Vivado 2018.2** and **GHDL 4.1.0**. Python 3 is used to export test metrics and run mutation checks. The target part is **`xc7z020clg400-1`** and the reference clock period is **10 ns / 100 MHz**. See [the recorded build version](../reports/tool_version.txt).

## 1. Get the sources

```sh
git clone https://github.com/seddouki18/AXI4-DMA-Controller.git
cd AXI4-DMA-Controller
```

All commands below start from this repository root unless a step explicitly changes directory. Reruns write generated results into `build/`, `sim_cmd/`, or `sim_reg/` and can replace the corresponding files in `reports/`. The checked-in reports remain available in Git history.

## 2. Run the full XSim suite on Windows

The Windows batch files load Vivado from `C:\Xilinx\Vivado\2018.2\settings64.bat`. Edit that line in the batch files if your installation is elsewhere.

In a Windows Command Prompt:

```bat
scripts\run_sim.bat
```

The script compiles the RTL and `tb/tb_dma_top.vhd` as VHDL-2008, elaborates the `tbsim` snapshot, and runs it to completion. It reports success only when `sim_cmd\sim.log` contains:

```text
ALL TESTS PASSED count=87 max_beats=256 seed=1
```

The supplied reference log is [reports/xsim_reference.log](../reports/xsim_reference.log). `scripts\run_sim.bat` recreates `sim_cmd/` at the start, so keep personal waveform changes elsewhere.

### Open the waveforms

After running the simulation:

```bat
call C:\Xilinx\Vivado\2018.2\settings64.bat
cd sim_cmd
xsim tbsim -gui
```

Add the AXI signals and relevant engine signals, then choose **Run All**. The [copy walkthrough](WALKTHROUGH.md) explains the reference waveform regions: nominal copy around 2,245–2,425 ns, 4 KiB splitting around 23,005–23,615 ns, and last-beat backpressure around 1,466,105–1,466,245 ns. These absolute times apply to seed 1 and a maximum burst length of 256 beats.

### Run the XSim regression

Return to the repository root and run:

```bat
scripts\run_regression.bat
```

This script runs 11 configurations: seeds 1–6 at 256 beats, seed 1 at 1 beat, seeds 1 and 2 at 16 beats, and seeds 1 and 3 at 64 beats. It creates `reports\regression_xsim.csv`, with individual logs under `sim_reg/`. This is a separate campaign from the 62-run GHDL campaign below.

## 3. Run GHDL simulation on Linux

Install GHDL and ensure `ghdl` is on `PATH`. The supplied Linux workflow was tested with GHDL 4.1.0 using its mcode backend and `--std=08`. Use `bash` explicitly so the script works even if an archive download did not preserve executable permissions.

For one complete reference-suite run:

```sh
bash scripts/regress_ghdl.sh 1:256
```

The generated log is `build/ghdl/sim_s1_b256.log`. Expect the same 87-test final verdict shown above. The script also creates `reports/regression_ghdl.csv` for the configurations requested in that invocation.

For the full 62-run campaign:

```sh
bash scripts/regress_ghdl.sh
```

The default campaign contains 50 seeds at 256 beats, five seeds each at 16 and 64 beats, and two seeds at 1 beat. Inspect the final `PASS=62 FAIL=0` message and the generated CSV. The supplied [reference regression CSV](../reports/regression_ghdl.csv) records the original campaign.

For a custom configuration list:

```sh
bash scripts/regress_ghdl.sh 1:256 7:16 2:1
```

Export a per-test CSV after the reference run:

```sh
python3 scripts/log_to_csv.py build/ghdl/sim_s1_b256.log reports/tests_seed1_b256.csv 1 256
```

### Run the standalone burst-planner sweep

`tb_dma_burst_planner.vhd` is a separate, smaller testbench. It checks 8,192 source/destination/length combinations plus command validation. It is not part of the top-level suite's 87-test count.

```sh
mkdir -p build/planner
cd build/planner
ghdl -a --std=08 ../../rtl/dma_pkg.vhd ../../rtl/dma_burst_planner.vhd ../../tb/tb_dma_burst_planner.vhd
ghdl -e --std=08 tb_dma_burst_planner
ghdl -r --std=08 tb_dma_burst_planner
cd ../..
```

The expected final note is `PLANNER TESTS PASSED cases=8192 plus command validation`.

### Run the mutation checks

```sh
python3 scripts/mutation_ghdl.py
```

The script copies the RTL into temporary directories, injects one bug per copy, and runs the top-level testbench. It does not edit the checked-in RTL. Results are written to `reports/mutation_ghdl.csv`.

Check both the printed summary **`12/12 mutants detected`** and all 12 CSV rows. The current script prints failures such as `BUILD ERROR` or `NOT DETECTED` without making its own process exit status nonzero, so the process exit code alone is not a mutation-test verdict. See [the supplied mutation results](../reports/mutation_ghdl.csv).

## 4. Rebuild the FPGA implementation

On Windows:

```bat
scripts\run_build.bat
```

Alternatively, with Vivado already on `PATH` on Windows or Linux:

```sh
vivado -mode batch -source scripts/build_ooc.tcl
```

The Tcl script locates the repository from its own location. It reads the RTL and `constraints/dma_ooc.xdc`, runs **out-of-context synthesis**, optimization, placement, physical optimization, and routing. It writes:

| Output | Purpose |
|---|---|
| `reports/utilization_synth.rpt` | Resource use after synthesis |
| `reports/utilization.rpt` and `utilization_hier.rpt` | Resource use after implementation |
| `reports/timing_summary.rpt` | Setup/hold summary and unconstrained paths |
| `reports/critical_paths.rpt` | Longest internal paths |
| `reports/clocks.rpt` | Clock information |
| `reports/drc.rpt` and `methodology.rpt` | Design and methodology checks |
| `reports/tool_version.txt` | Tool version, device, and build mode |
| `build/dma_routed.dcp` | Routed checkpoint for inspection in Vivado |

The batch wrapper additionally records `reports/vivado_build.log`; its success marker is **`BUILD DONE`**. A direct Tcl invocation also prints that marker. Review the actual reports rather than treating completion as a timing verdict.

This is characterization of the DMA block alone. AXI port paths have no input/output delay constraints and are excluded from the timing conclusion. A complete SoC must be timed after integration. See [boundary assumptions](../constraints/BOUNDARY_ASSUMPTIONS.md).

## 5. Create a fresh Vivado GUI project

The supplied archive contains a workstation-generated `.xpr` file and caches. For a clean checkout, the new project-creation script builds a fresh GUI project using the repository's source paths:

```sh
vivado -mode batch -source scripts/create_vivado_project.tcl
```

Open `build/vivado/AXI_DMA.xpr` in Vivado. The script sets:

- device `xc7z020clg400-1`;
- all RTL and testbench files to **VHDL 2008**;
- design top `dma_top` and simulation top `tb_dma_top`;
- the checked-in 100 MHz OOC constraint file;
- synthesis option `-mode out_of_context`.

It creates the project but does not launch a run. To simulate, choose **Run Behavioral Simulation**, then **Run All**. To inspect the block's placement, run synthesis and implementation through routing, then open the implemented design and its **Device** window. This standalone OOC design is not a board-ready bitstream project.

The script leaves an existing generated project intact and reports its path rather than overwriting it. Open that project directly on later visits. For the published resource/timing workflow, use `build_ooc.tcl`: it explicitly includes `phys_opt_design` before routing.

The OOC project option follows [AMD's documented block-characterization flow](https://adaptivesupport.amd.com/s/article/59168?language=en_US). The new GUI-project generator has been checked for Tcl syntax and source-path consistency; it still requires a local Vivado run to validate creation in that tool version.

## What was checked for publication

Source files, scripts, constraints, and reference reports are supplied. The publication checks reparsed the original XSim log and matched all 87 test names, verdicts, copy sizes, and cycle counts against the supplied per-test CSV. All documentation links and all 29 image references were checked, and the supplied RTL, testbenches, and original scripts were preserved byte-for-byte. Shell and Python script syntax were also checked. Vivado and GHDL are not installed in the publication environment, so the hardware simulations and implementation were not rerun here. Original Vivado screenshots and raw reports describe the author's recorded runs; creating this documentation does not itself rerun Vivado or establish board-level behavior.
