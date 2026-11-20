# ============================================================================
#  build_ooc.tcl - out-of-context synthesis and implementation of dma_top (V1)
#
#  Non-project mode. Run from any folder:
#      vivado -mode batch -source scripts/build_ooc.tcl
#  or double-click scripts\run_build.bat on Windows.
#
#  This is a characterization of the DMA block alone (OOC), not the timing
#  closure of a complete SoC. See constraints/BOUNDARY_ASSUMPTIONS.md.
# ============================================================================
set part xc7z020clg400-1
set top  dma_top

set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
file mkdir reports build

set rtl_files [list \
  rtl/dma_pkg.vhd \
  rtl/dma_burst_planner.vhd \
  rtl/dma_burst_buffer.vhd \
  rtl/dma_axi_lite_regs.vhd \
  rtl/dma_engine.vhd \
  rtl/dma_top.vhd]
foreach f $rtl_files { read_vhdl -vhdl2008 $f }
read_xdc constraints/dma_ooc.xdc

synth_design -top $top -part $part -mode out_of_context
report_utilization -file reports/utilization_synth.rpt

opt_design
place_design
phys_opt_design
route_design

report_utilization -file reports/utilization.rpt
report_utilization -hierarchical -file reports/utilization_hier.rpt
report_timing_summary -report_unconstrained -max_paths 10 -file reports/timing_summary.rpt
report_timing -max_paths 10 -file reports/critical_paths.rpt
report_clocks -file reports/clocks.rpt
report_drc -file reports/drc.rpt
report_methodology -file reports/methodology.rpt
write_checkpoint -force build/dma_routed.dcp

set fh [open reports/tool_version.txt w]
puts $fh [version]
puts $fh "part: $part (speed grade -1)"
puts $fh "top: $top, synth_design -mode out_of_context"
puts $fh "constraints: constraints/dma_ooc.xdc (aclk 10.000 ns = 100 MHz)"
close $fh

puts "BUILD DONE: reports written to $root/reports"
