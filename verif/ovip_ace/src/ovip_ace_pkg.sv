`ifndef OVIP_ACE_PKG__SV
`define OVIP_ACE_PKG__SV

`include "ovip_axi_defines.sv"
`include "ovip_ace_defines.sv"
`include "ovip_ace_agent_if.sv"

package ovip_ace_pkg;
	import uvm_pkg::*;
	`include "uvm_macros.svh"

	import ovip_global_pkg::*;
	import ovip_axi_pkg::*;

	`include "ovip_ace_types.sv"
	`include "ovip_ace_agent_config.sv"
	`include "ovip_ace_trans.sv"
	`include "ovip_ace_monitor.sv"
	`include "ovip_ace_master_driver.sv"
	`include "ovip_ace_slave_driver.sv"
	`include "ovip_ace_agent.sv"
	`include "ovip_ace_scoreboard.sv"

	// Reusable sequence library -- generic sequences any user testbench can
	// subclass or instantiate directly. Test-specific sequences belong in the
	// user's own testbench package.
	`include "seqlib/ovip_ace_base_master_sequence.sv"
	`include "seqlib/ovip_ace_base_slave_sequence.sv"
endpackage : ovip_ace_pkg

`endif
