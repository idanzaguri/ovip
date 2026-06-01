// -----------------------------------------------------------------------------
// ovip_axi.f -- compile filelist for the ovip_axi VIP.
//
// Prerequisite: set OVIP_ROOT to the repository root.
//     export OVIP_ROOT=/path/to/ovip
//
// Usage (any simulator):
//     vlog -sv -mfcu                     -f $OVIP_ROOT/verif/ovip_axi/ovip_axi.f    (Modelsim/Questa)
//     vcs  -sverilog -ntb_opts uvm-1.2   -f $OVIP_ROOT/verif/ovip_axi/ovip_axi.f    (VCS)
//     xrun -uvm -uvmhome CDNS-1.2 -sv    -f $OVIP_ROOT/verif/ovip_axi/ovip_axi.f    (Xcelium)
//
// Requires UVM 1.2 from your simulator's built-in library (no source needed).
//
// Optional compile-time overrides -- see verif/ovip_axi/README.md
// "Compile-Time Defines" for the full list:
//     +define+OVIP_AXI_MAX_DATA_WIDTH=2048
//     +define+OVIP_AXI_MAX_ID_WIDTH=16
//     +define+OVIP_AXI_DISABLE_XZ_AND_SIGNALS_STABILITY_CHECKS
// -----------------------------------------------------------------------------

+incdir+$OVIP_ROOT/verif/ovip_common
+incdir+$OVIP_ROOT/verif/ovip_common/mem
+incdir+$OVIP_ROOT/verif/ovip_axi/src
+incdir+$OVIP_ROOT/verif/ovip_axi/src/seqlib

$OVIP_ROOT/verif/ovip_common/ovip_global_pkg.sv
$OVIP_ROOT/verif/ovip_common/mem/ovip_mem_pkg.sv
$OVIP_ROOT/verif/ovip_axi/src/ovip_axi_pkg.sv
