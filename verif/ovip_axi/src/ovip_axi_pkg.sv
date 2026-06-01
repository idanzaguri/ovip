`ifndef OVIP_AXI_PKG__SV
`define OVIP_AXI_PKG__SV

`include "ovip_axi_defines.sv"
`include "ovip_axi_macros.sv"
`include "ovip_axi_agent_if.sv"

package ovip_axi_pkg;
	import uvm_pkg::*;
	`include "uvm_macros.svh"

	import ovip_global_pkg::*;
	import ovip_mem_pkg::*;

	`include "ovip_axi_types.sv"

	`include "ovip_axi_agent_config.sv"
	`include "ovip_axi_base_sequencer.sv"
	`include "ovip_axi_trans.sv"
	`include "ovip_axi_out_of_order_queue.sv"
	`include "ovip_axi_monitor.sv"

	`include "ovip_axi_base_driver.sv"
	`include "ovip_axi_slave_driver.sv"
	`include "ovip_axi_master_driver.sv"

	`include "ovip_axi_slave_sequencer.sv"
	`include "ovip_axi_agent.sv"
	`include "ovip_axi_scoreboard.sv"

	// Reusable sequence library -- generic sequences that any user testbench
	// can subclass or instantiate directly. Test-specific sequences belong
	// in the user's own testbench package.
	`include "seqlib/ovip_axi_base_master_sequence.sv"
	`include "seqlib/ovip_axi_base_slave_sequence.sv"
	`include "seqlib/ovip_axi_simple_wr_bursts_seq.sv"
	`include "seqlib/ovip_axi_simple_rd_bursts_seq.sv"
	`include "seqlib/ovip_axi_bytestream_sequence.sv"

endpackage : ovip_axi_pkg

`endif
