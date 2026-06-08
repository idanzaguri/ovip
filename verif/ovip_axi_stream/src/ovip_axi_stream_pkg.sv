`ifndef OVIP_AXI_STREAM_PKG__SV
`define OVIP_AXI_STREAM_PKG__SV

`include "ovip_axi_stream_defines.sv"
`include "ovip_axi_stream_macros.sv"
`include "ovip_axi_stream_agent_if.sv"

package ovip_axi_stream_pkg;
	import uvm_pkg::*;
	`include "uvm_macros.svh"

	import ovip_global_pkg::*;
	import ovip_mem_pkg::*;

	`include "ovip_axi_stream_types.sv"
	`include "ovip_axi_stream_agent_config.sv"
	`include "ovip_axi_stream_trans.sv"
	`include "ovip_axi_stream_monitor.sv"
	`include "ovip_axi_stream_master_driver.sv"
	`include "ovip_axi_stream_slave_driver.sv"
	`include "ovip_axi_stream_slave_sequencer.sv"
	// Reusable sequence library -- generic sequences that any user testbench
	// can subclass or instantiate directly. Test-specific sequences belong in
	// the user's own testbench package.
	`include "ovip_axi_stream_scoreboard.sv"
	`include "seqlib/ovip_axi_stream_base_master_sequence.sv"
	`include "seqlib/ovip_axi_stream_base_slave_sequence.sv"
	`include "seqlib/ovip_axi_stream_simple_packet_seq.sv"
	`include "ovip_axi_stream_agent.sv"
endpackage : ovip_axi_stream_pkg

`endif
