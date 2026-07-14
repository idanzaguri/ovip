// -----------------------------------------------------------------------------
// ovip_ace.f -- compile filelist for the ovip_ace VIP (AMBA ACE + ACE-Lite).
//
// Prerequisite: set OVIP_ROOT to the repository root.
//     export OVIP_ROOT=/path/to/ovip
//
// Usage (any simulator):
//     vlog -sv -mfcu                     -f $OVIP_ROOT/verif/ovip_ace/ovip_ace.f    (Modelsim/Questa)
//     vcs  -sverilog -ntb_opts uvm-1.2   -f $OVIP_ROOT/verif/ovip_ace/ovip_ace.f    (VCS)
//     xrun -uvm -uvmhome CDNS-1.2 -sv    -f $OVIP_ROOT/verif/ovip_ace/ovip_ace.f    (Xcelium)
//
// Requires UVM 1.2 from your simulator's built-in library (no source needed).
//
// ovip_ace extends ovip_axi -- the AXI VIP is compiled in transitively below.
// If you are also compiling ovip_axi.f explicitly in the same step, drop the
// explicit reference to avoid compiling the AXI package twice.
//
// Optional compile-time overrides -- see verif/ovip_ace/README.md
// "Compile-Time Defines" for the full list:
//     +define+OVIP_ACE_MAX_ACADDR_WIDTH=64
//     +define+OVIP_ACE_MAX_CDDATA_WIDTH=1024
// -----------------------------------------------------------------------------

-f $OVIP_ROOT/verif/ovip_axi/ovip_axi.f

+incdir+$OVIP_ROOT/verif/ovip_ace/src
+incdir+$OVIP_ROOT/verif/ovip_ace/src/seqlib

$OVIP_ROOT/verif/ovip_ace/src/ovip_ace_pkg.sv
