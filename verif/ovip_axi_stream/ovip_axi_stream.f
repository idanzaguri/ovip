// -----------------------------------------------------------------------------
// ovip_axi_stream.f -- compile filelist for the ovip_axi_stream VIP.
//
// Prerequisite: set OVIP_ROOT to the repository root.
//     export OVIP_ROOT=/path/to/ovip
//
// Usage (any simulator):
//     vlog -sv -mfcu                     -f $OVIP_ROOT/verif/ovip_axi_stream/ovip_axi_stream.f    (Modelsim/Questa)
//     vcs  -sverilog -ntb_opts uvm-1.2   -f $OVIP_ROOT/verif/ovip_axi_stream/ovip_axi_stream.f    (VCS)
//     xrun -uvm -uvmhome CDNS-1.2 -sv    -f $OVIP_ROOT/verif/ovip_axi_stream/ovip_axi_stream.f    (Xcelium)
//     verilator --binary --timing +define+UVM_NO_DPI +incdir+$UVM_HOME/src $UVM_HOME/src/uvm_pkg.sv -f $OVIP_ROOT/verif/ovip_axi_stream/ovip_axi_stream.f ...   (Verilator)
//
// Requires UVM 1.2 from your simulator's built-in library (no source needed).
// Verilator has none: UVM_HOME is a UVM 1.2 source tree.
//
// Optional compile-time overrides -- see verif/ovip_axi_stream/README.md
// "Compile-Time Defines" for the full list:
//     +define+OVIP_AXI_STREAM_MAX_DATA_WIDTH=2048
//     +define+OVIP_AXI_STREAM_MAX_USER_WIDTH=2048
// -----------------------------------------------------------------------------

+incdir+$OVIP_ROOT/verif/ovip_common
+incdir+$OVIP_ROOT/verif/ovip_common/mem
+incdir+$OVIP_ROOT/verif/ovip_axi_stream/src
+incdir+$OVIP_ROOT/verif/ovip_axi_stream/src/seqlib

$OVIP_ROOT/verif/ovip_common/ovip_global_pkg.sv
$OVIP_ROOT/verif/ovip_common/mem/ovip_mem_pkg.sv
$OVIP_ROOT/verif/ovip_axi_stream/src/ovip_axi_stream_pkg.sv
