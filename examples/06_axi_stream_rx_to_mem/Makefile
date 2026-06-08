# AXI-Stream rx -> ovip_mem example.

SIM ?= modelsim

COMMON_ROOT := $(abspath ../../verif/ovip_common)
VIP_ROOT    := $(abspath ../../verif/ovip_axi_stream/src)
VIP_INC     := +incdir+$(COMMON_ROOT) +incdir+$(COMMON_ROOT)/mem \
               +incdir+$(VIP_ROOT) +incdir+$(VIP_ROOT)/seqlib

SRCS := \
    $(COMMON_ROOT)/ovip_global_pkg.sv \
    $(COMMON_ROOT)/mem/ovip_mem_pkg.sv \
    $(VIP_ROOT)/ovip_axi_stream_pkg.sv \
    rx_to_mem_example.sv

ifeq ($(SIM),modelsim)
run: clean
	vlib work
	vlog -sv -mfcu $(VIP_INC) $(SRCS)
	vsim -c -do "log -r /*; run -all; quit" tb_top

view:
	vsim -view vsim.wlf -do "add wave -r /*"
endif

ifeq ($(SIM),vcs)
run: clean
	vcs -full64 -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps \
	    $(VIP_INC) -top tb_top $(SRCS) -o simv
	./simv
endif

ifeq ($(SIM),xcelium)
run: clean
	xrun -uvm -uvmhome CDNS-1.2 -sv -timescale 1ns/1ps \
	    $(VIP_INC) $(SRCS)
endif

clean:
	rm -rf work transcript csrc simv simv.daidir ucli.key \
	       xcelium.d xrun.log xrun.history \
	       *.wlf *.vpd *.vcd vc_hdrs.h

.PHONY: run clean view
