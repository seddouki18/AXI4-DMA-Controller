# Vivado project

The reusable project definition is [scripts/create_vivado_project.tcl](../scripts/create_vivado_project.tcl). It creates `build/vivado/AXI_DMA.xpr` from the checked-in RTL, testbenches, and OOC constraints. Generated project state, caches, simulator executables, and routed checkpoints do not need to be committed.

From the repository root:

```sh
vivado -mode batch -source scripts/create_vivado_project.tcl
```

Open the generated `.xpr` in Vivado. The design top is `dma_top`; the default simulation top is `tb_dma_top`. The original workstation-generated `.xpr` is not used as the portable build definition.

To reproduce the recorded non-project implementation flow instead, run:

```sh
vivado -mode batch -source scripts/build_ooc.tcl
```

See [the complete reproduction guide](../docs/REPRODUCING.md) for simulation, regression, mutation testing, output paths, and the limits of OOC timing.
