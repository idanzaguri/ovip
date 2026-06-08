# Response-timing example for the ovip_axi VIP.

SIM ?= modelsim

COMMON_ROOT := $(abspath ../../../verif/ovip_common)
VIP_ROOT    := $(abspath ../../../verif/ovip_axi/src)
VIP_INC     := +incdir+$(COMMON_ROOT) +incdir+$(COMMON_ROOT)/mem \
               +incdir+$(VIP_ROOT) +incdir+$(VIP_ROOT)/seqlib

SRCS := \
    $(COMMON_ROOT)/ovip_global_pkg.sv \
    $(COMMON_ROOT)/mem/ovip_mem_pkg.sv \
    $(VIP_ROOT)/ovip_axi_pkg.sv \
    timing_example.sv

DEFS := +define+OVIP_AXI_MAX_DATA_WIDTH=64 +define+OVIP_AXI_MAX_STRB_WIDTH=8

ifeq ($(SIM),modelsim)
run: clean
	vlib work
	vlog -sv -mfcu $(VIP_INC) $(DEFS) $(SRCS)
	vsim -c -do "log -r /*; run -all; quit" tb_top

# Open the waveform in vsim. Requires `make run` first to produce vsim.wlf.
view:
	vsim -view vsim.wlf -do "add wave -r /*"
endif

ifeq ($(SIM),vcs)
# Add `-debug_access+all` to compile and `+vcs+vcdpluson` to runtime for VPD waves;
# view with `dve -vpd vcdplus.vpd`.
run: clean
	vcs -full64 -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps \
	    $(VIP_INC) $(DEFS) -top tb_top $(SRCS) -o simv
	./simv
endif

ifeq ($(SIM),xcelium)
# Add `-access +rwc` and a probe tcl for SimVision waves.
run: clean
	xrun -uvm -uvmhome CDNS-1.2 -sv -timescale 1ns/1ps \
	    $(VIP_INC) $(DEFS) $(SRCS)
endif

clean:
	rm -rf work transcript csrc simv simv.daidir ucli.key \
	       xcelium.d xrun.log xrun.history \
	       *.wlf *.vpd *.vcd vc_hdrs.h

.PHONY: run clean view
