# ============================================================================
#  dma_ooc.xdc - out-of-context characterization of dma_top (V1)
#  Same content as the GUI project constraint file (vivado\...\timing.xdc).
# ============================================================================

# Single clock domain. 100 MHz reference for the first characterization.
# For a separate campaign at another frequency, change the period here.
# Do not define two clocks on the same port.
create_clock -period 10.000 -name aclk [get_ports aclk]

# OOC only: aclk is assumed to arrive from a global clock buffer of the
# integrating design. Without this, Vivado warns that the clock source of an
# OOC clock port is unknown (HD.CLK_SRC).
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports aclk]

# No set_input_delay / set_output_delay on purpose.
# The AXI ports are internal to an SoC; their budget comes from the
# integration. See BOUNDARY_ASSUMPTIONS.md.
