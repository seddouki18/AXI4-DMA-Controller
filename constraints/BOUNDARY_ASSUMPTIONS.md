# Boundary assumptions for the OOC characterization

The synthesis and implementation in `reports/` characterize the DMA block alone, in
out-of-context (OOC) mode, on `xc7z020clg400-1`. They are **not** the timing closure of a
complete SoC.

## What is constrained

| Item | Value | Where |
|---|---|---|
| Clock | `aclk`, period 10.000 ns (100 MHz), one clock domain, no CDC | `dma_ooc.xdc` |
| Clock source | Global buffer (`HD.CLK_SRC BUFGCTRL_X0Y0`), as in an integrating design | `dma_ooc.xdc` |
| Register-to-register paths | Fully timed by the clock constraint | `reports/timing_summary.rpt` |

## What is not constrained, and why

The block's ports (AXI4 master, AXI4-Lite slave, `aresetn`, `irq`) have **no**
`set_input_delay` / `set_output_delay`. In a Zynq or any SoC these AXI interfaces stay inside
the FPGA: they connect to an interconnect, a BRAM controller or the PS ports in the same
clock domain. Their timing budget comes from that integration, not from an external chip.
Putting invented delays on every port would give numbers that mean nothing.

As a result:

- Paths from input ports to registers and from registers to output ports appear as
  **unconstrained** in `timing_summary.rpt` (`-report_unconstrained` lists them).
- They are **excluded from the timing conclusion**. WNS/WHS in the README cover
  register-to-register paths only.

## Port behaviour that an integrator must know

| Port group | Structure | Integration note |
|---|---|---|
| AXI4 master outputs (`m_axi_*` VALID, address, length, `WDATA`, `WLAST`, READY) | Decoded from registered FSM state and the registered RAM output | Clock-to-out from flip-flops or BRAM, plus a reset gate (see below) |
| AXI4 master inputs (`m_axi_*READY`, `RVALID`, `RDATA`, `BVALID`, responses, IDs) | Go into FSM registers and RAM enables in the same cycle | Input-to-register paths; `WREADY` also drives the RAM read enable |
| AXI4-Lite outputs | `AWREADY`, `WREADY`, `ARREADY`, `BVALID`, `RVALID` come from internal flags | Same reset gate |
| `aresetn` | Gates every VALID/READY output **combinationally** (VALID never asserted in reset) | Must be synchronous to `aclk`, for example from a `proc_sys_reset` block |
| `irq` | `IRQ_EN and (DONE or ERROR)`, from registers | Level interrupt |

There is no combinational data path from an input port to an output port. The only
port-to-port combinational path is the `aresetn` gate on VALID/READY outputs, which is
intended.

## To sign the timing in a real system

1. Integrate the DMA with its slaves (for example an AXI BRAM controller and an
   interconnect) in one design, on the same `aclk`.
2. Constrain the system clock there. The AXI paths then become internal
   register-to-register paths and are timed normally.
3. Only if the DMA really faces another chip through pins would a boundary contract with
   `set_input_delay` / `set_output_delay` values be needed. That is not the case here.
