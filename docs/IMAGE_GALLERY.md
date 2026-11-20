# Image gallery

[Project overview](../README.md) · [Architecture](ARCHITECTURE.md) · [Waveform walkthrough](WALKTHROUGH.md) · [Results](RESULTS.md)

All 27 figures from the prepared image archive are retained here, together with the final implemented-device view and additional pulse-width and power captures: **30 images in total**. The README highlights the key results; the detailed pages explain the remaining figures.

Native tool screenshots record selected project runs. Explanatory diagrams and redrawn chronograms help interpret those runs and are labeled accordingly. Original French labels are preserved in some images; the captions below explain their meaning in English.

The timing and placement images characterize the isolated DMA block. They do not establish complete-system timing or measurements on a physical board.

## Architecture and concepts

### System architecture

![System architecture](images/architecture/architecture.png)

**Explanatory diagram.** Software programs the AXI4-Lite registers; the engine moves data through AXI4 using the planner and burst RAM.

### CPU copy versus DMA copy

![CPU copy versus DMA copy](images/architecture/cpu-vs-dma.png)

**Explanatory diagram.** The processor sets up a transfer instead of executing every read and write itself.

### The five AXI4 channels

![The five AXI4 channels](images/architecture/axi4-channels.png)

**Explanatory diagram.** AR/R carry read requests and responses; AW/W/B carry write requests, data, and completion responses.

### VALID and READY

![VALID and READY](images/architecture/valid-ready-handshake.png)

**Explanatory diagram.** A transfer occurs at a rising clock edge when both are high. While waiting, VALID and its payload stay stable.

### Transfer-engine state machine

![Transfer-engine state machine](images/architecture/engine-fsm.png)

**Explanatory diagram.** The engine plans, reads, prefetches, writes, and waits for B. Protocol violations enter FAULT.

### Data path through the buffer

![Data path through the buffer](images/architecture/datapath.png)

**Explanatory diagram.** Read words enter the burst RAM; its synchronous output supplies write data.

### V1 scheduling and planned V2 overlap

![V1 scheduling and planned V2 overlap](images/architecture/store-and-forward.png)

**Explanatory diagram.** V1 separates reading from writing. The V2 overlap shown for comparison is planned, not implemented.

### Source and destination page boundaries

![Source and destination page boundaries](images/architecture/4k-splitting.png)

**Explanatory diagram.** The planner limits each burst by the room left before either 4 KiB boundary.

### Control and status bits

![Control and status bits](images/architecture/control-status-registers.png)

**Explanatory diagram.** START launches a checked command; status records BUSY, sticky DONE and ERROR; IRQ_EN enables the level interrupt.

### Self-checking testbench

![Self-checking testbench](images/architecture/testbench.png)

**Explanatory diagram.** The AXI4-Lite driver, behavioral memory, scoreboard, and monitors exercise and check the DMA.

## Copy walkthrough

### Programming a copy

![Programming a copy](images/waveforms/axi-lite-programming.png)

**Redrawn simulation chronogram.** SRC, DST, LEN, and START are written over AXI4-Lite, demonstrating separate address and data arrivals.

### A 16-byte copy, cycle by cycle

![A 16-byte copy, cycle by cycle](images/waveforms/16-byte-copy.png)

**Redrawn simulation chronogram.** Four source words are read and buffered, then written; completion follows the final B response.

### Nominal copy in XSim

![Nominal copy in XSim](images/waveforms/xsim-nominal-copy.png)

**Native XSim capture.** Native tool capture of the same store-and-forward sequence in the reference simulation.

### Three bursts at offset page boundaries

![Three bursts at offset page boundaries](images/waveforms/4k-three-bursts.png)

**Redrawn simulation chronogram.** Copying 128 bytes from 0x1FF0 to 0x8FF8 requires segments of 2, 2, and 28 words.

### 4 KiB splitting in XSim

![4 KiB splitting in XSim](images/waveforms/xsim-4k-boundaries.png)

**Native XSim capture.** The native waveform shows both address channels advancing through the three planned segments.

### Boundary split with clock and counters

![Boundary split with clock and counters](images/waveforms/xsim-4k-boundaries-clock.png)

**Native XSim capture.** A second native view adds the clock and internal counting context to the boundary case.

### Backpressure on the final word

![Backpressure on the final word](images/waveforms/last-beat-stall.png)

**Redrawn simulation chronogram.** The last word, WVALID, and WLAST are held until WREADY allows the beat to complete.

### Last-beat backpressure in XSim

![Last-beat backpressure in XSim](images/waveforms/xsim-last-beat-stall.png)

**Native XSim capture.** The native test-80 capture records the five-cycle WREADY pause and stable pending write beat.

### Draining a read after an error

![Draining a read after an error](images/waveforms/read-error-drain.png)

**Redrawn simulation chronogram.** The DMA receives the rest of an erroneous read burst and does not issue a write for that segment.

### Malformed read response and FAULT

![Malformed read response and FAULT](images/waveforms/protocol-fault.png)

**Redrawn simulation chronogram.** An unexpected RLAST leads to FAULT and requires coordinated external reset.

## Simulation evidence

### 87 reference tests passed

![87 reference tests passed](images/simulation/xsim-87-tests-passed.png)

**Native XSim console.** The XSim console reports count=87, max_beats=256, seed=1, ending at 1,521,975 ns.

## FPGA implementation evidence

### Implemented DMA in the device

![Implemented DMA in the device](images/implementation/dma-device-view.png)

**Native Vivado capture.** The final requested image shows the implemented design open on xc7z020clg400-1 with Implementation Complete visible.

### Resource summary

![Resource summary](images/implementation/resource-summary.png)

**Native Vivado crop.** 604 LUTs, 378 flip-flops, and 0.50 block-RAM tiles are shown. One RAMB18 occupies half of a 36 Kb tile.

### Utilization in its tool context

![Utilization in its tool context](images/implementation/resource-full-view.png)

**Native Vivado capture.** The full view includes the hierarchy and the isolated Zynq design warning about the absent PS7 block.

### Setup slack summary

![Setup slack summary](images/implementation/timing-summary.png)

**Native Vivado crop.** WNS is +1.261 ns with no failing setup endpoints in the constrained internal-path scope.

### Full setup timing view

![Full setup timing view](images/implementation/timing-setup.png)

**Native Vivado capture.** The complete setup view supplies tool and device context for the positive slack result.

### Hold timing view

![Hold timing view](images/implementation/timing-hold.png)

**Native Vivado capture.** WHS is +0.083 ns and there are no failing hold endpoints in the reported scope.

### Pulse-width timing

![Pulse-width timing](images/implementation/timing-pulse-width.png)

**Native Vivado capture.** The additional selected capture shows +4.500 ns pulse-width slack and zero failing checks.

### Scripted OOC build completed

![Scripted OOC build completed](images/implementation/batch-build-complete.png)

**Native Vivado console.** The console records out-of-context synthesis, the 10 ns clock, a routed checkpoint, and BUILD DONE.

### Power estimate from the GUI implementation run

![Vivado GUI power summary](images/implementation/power-summary.png)

**Native Vivado capture.** Total on-chip power is estimated at 0.109 W with Medium confidence. The archived GUI-run report separates 0.006 W dynamic power from 0.103 W device static power; no simulation activity file was supplied. This is a tool estimate, not a board measurement. See [the power report](../reports/power_gui_reference.rpt).
