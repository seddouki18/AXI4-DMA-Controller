# Create a portable Vivado GUI project from the checked-in source files.
# Run from the repository root:
#   vivado -mode batch -source scripts/create_vivado_project.tcl
# Then open build/vivado/AXI_DMA.xpr in Vivado.
#
# This script creates a project only. It does not run simulation, synthesis,
# implementation, or bitstream generation. For the reported non-project OOC
# build, use scripts/build_ooc.tcl instead.

set root [file normalize [file join [file dirname [info script]] ..]]
set project_dir [file join $root build vivado]
set project_file [file join $project_dir AXI_DMA.xpr]

if {[file exists $project_file]} {
    error "Project already exists: $project_file. Open it, or choose a fresh generated build directory before recreating it."
}

set rtl_files [list \
    [file join $root rtl dma_pkg.vhd] \
    [file join $root rtl dma_burst_planner.vhd] \
    [file join $root rtl dma_burst_buffer.vhd] \
    [file join $root rtl dma_axi_lite_regs.vhd] \
    [file join $root rtl dma_engine.vhd] \
    [file join $root rtl dma_top.vhd]]
set tb_files [list \
    [file join $root tb tb_dma_top.vhd] \
    [file join $root tb tb_dma_burst_planner.vhd]]
set constraints_file [file join $root constraints dma_ooc.xdc]

foreach source_file [concat $rtl_files $tb_files [list $constraints_file]] {
    if {![file isfile $source_file]} {
        error "Required project file is missing: $source_file"
    }
}

create_project AXI_DMA $project_dir -part xc7z020clg400-1
set_property target_language VHDL [current_project]
set_property simulator_language VHDL [current_project]

add_files -fileset sources_1 -norecurse $rtl_files
add_files -fileset sim_1 -norecurse $tb_files
foreach source_file [concat $rtl_files $tb_files] {
    set_property file_type {VHDL 2008} [get_files $source_file]
}
add_files -fileset constrs_1 -norecurse $constraints_file

set_property top dma_top [get_filesets sources_1]
set_property top tb_dma_top [get_filesets sim_1]
# Characterize the block alone; do not insert top-level I/O buffers.
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} \
    -value {-mode out_of_context} -objects [get_runs synth_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "PROJECT CREATED: $project_file"
puts "Simulation top: tb_dma_top; design top: dma_top; clock: 100 MHz."
puts "OOC block characterization only. System integration and board testing are separate steps."
