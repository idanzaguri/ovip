// -----------------------------------------------------------------------------
// ovip_apb.f -- compile filelist for the ovip_apb VIP.
//
// Prerequisite: set OVIP_ROOT to the repository root.
//     export OVIP_ROOT=/path/to/ovip
//
// Usage (any simulator):
//     vlog -sv -mfcu                     -f $OVIP_ROOT/verif/ovip_apb/ovip_apb.f    (Modelsim/Questa)
//     vcs  -sverilog -ntb_opts uvm-1.2   -f $OVIP_ROOT/verif/ovip_apb/ovip_apb.f    (VCS)
//     xrun -uvm -uvmhome CDNS-1.2 -sv    -f $OVIP_ROOT/verif/ovip_apb/ovip_apb.f    (Xcelium)
//
// Requires UVM 1.2 from your simulator's built-in library (no source needed).
//
// Optional compile-time overrides -- see verif/ovip_apb/README.md
// "Compile-Time Defines" for the full list:
//     +define+OVIP_APB_MAX_ADDR_WIDTH=16
// -----------------------------------------------------------------------------

+incdir+$OVIP_ROOT/verif/ovip_common
+incdir+$OVIP_ROOT/verif/ovip_common/mem
+incdir+$OVIP_ROOT/verif/ovip_apb/src
+incdir+$OVIP_ROOT/verif/ovip_apb/src/seqlib

$OVIP_ROOT/verif/ovip_common/ovip_global_pkg.sv
$OVIP_ROOT/verif/ovip_common/mem/ovip_mem_pkg.sv
$OVIP_ROOT/verif/ovip_apb/src/ovip_apb_pkg.sv
