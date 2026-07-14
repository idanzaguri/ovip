# Coherent-loopback example for the ovip_ace VIP.
#
# NOTE: ovip_ace is AI-generated and unverified. This example is known to
# COMPILE; a clean simulation run has not been confirmed by a human.
#
# Usage:
#   make              # default = modelsim
#   make SIM=modelsim
#   make SIM=vcs
#   make SIM=xcelium
#   make clean

SIM ?= modelsim

# Locate the VIP source roots from this directory.
COMMON_ROOT := $(abspath ../../../verif/ovip_common)
AXI_ROOT    := $(abspath ../../../verif/ovip_axi/src)
ACE_ROOT    := $(abspath ../../../verif/ovip_ace/src)
VIP_INC     := +incdir+$(COMMON_ROOT) +incdir+$(COMMON_ROOT)/mem \
               +incdir+$(AXI_ROOT) +incdir+$(AXI_ROOT)/seqlib \
               +incdir+$(ACE_ROOT) +incdir+$(ACE_ROOT)/seqlib

# Files compiled in order: shared utility packages, the AXI VIP, the ACE VIP
# (which extends AXI), then us.
SRCS := \
    $(COMMON_ROOT)/ovip_global_pkg.sv \
    $(COMMON_ROOT)/mem/ovip_mem_pkg.sv \
    $(AXI_ROOT)/ovip_axi_pkg.sv \
    $(ACE_ROOT)/ovip_ace_pkg.sv \
    coherent_loopback_example.sv

DEFS := +define+OVIP_AXI_MAX_DATA_WIDTH=64 +define+OVIP_AXI_MAX_STRB_WIDTH=8

# ----------------------------------------------------------------------------
ifeq ($(SIM),modelsim)
run: clean
	vlib work
	vlog -sv -mfcu $(VIP_INC) $(DEFS) $(SRCS)
	vsim -c -do "log -r /*; run -all; quit" tb_top

view:
	vsim -view vsim.wlf -do "add wave -r /*"
endif

ifeq ($(SIM),vcs)
run: clean
	vcs -full64 -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps \
	    $(VIP_INC) $(DEFS) -top tb_top $(SRCS) -o simv
	./simv
endif

ifeq ($(SIM),xcelium)
run: clean
	xrun -uvm -uvmhome CDNS-1.2 -sv -timescale 1ns/1ps \
	    $(VIP_INC) $(DEFS) $(SRCS)
endif

# ----------------------------------------------------------------------------
clean:
	rm -rf work transcript csrc simv simv.daidir ucli.key \
	       xcelium.d xrun.log xrun.history \
	       *.wlf *.vpd *.vcd vc_hdrs.h

.PHONY: run clean view
