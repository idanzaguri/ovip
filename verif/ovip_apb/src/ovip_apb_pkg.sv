`ifndef OVIP_APB_PKG__SV
`define OVIP_APB_PKG__SV

`include "ovip_apb_defines.sv"
`include "ovip_apb_macros.sv"
`include "ovip_apb_agent_if.sv"

package ovip_apb_pkg;
	import uvm_pkg::*;
	`include "uvm_macros.svh"

	import ovip_global_pkg::*;
	import ovip_mem_pkg::*;

	`include "ovip_apb_types.sv"
	`include "ovip_apb_agent_config.sv"
	`include "ovip_apb_trans.sv"
	`include "ovip_apb_monitor.sv"
	`include "ovip_apb_master_driver.sv"
	`include "ovip_apb_slave_driver.sv"
	`include "ovip_apb_slave_sequencer.sv"
	`include "ovip_apb_trans_logger.sv"
	`include "ovip_apb_scoreboard.sv"
	// Reusable sequence library -- generic sequences that any user testbench
	// can subclass or instantiate directly. Test-specific sequences belong in
	// the user's own testbench package.
	`include "seqlib/ovip_apb_base_master_sequence.sv"
	`include "seqlib/ovip_apb_base_slave_sequence.sv"
	`include "seqlib/ovip_apb_simple_rw_seq.sv"
	`include "ovip_apb_agent.sv"
endpackage : ovip_apb_pkg

`endif
