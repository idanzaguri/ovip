`ifndef OVIP_APB_SLAVE_SEQUENCER__SV
`define OVIP_APB_SLAVE_SEQUENCER__SV

// Sequencer for the completer-side slave sequence. The slave sequence pulls
// monitor-captured requests off `response_req_port` (connected to the
// monitor's response_req_port), fills in the response fields, and sends the
// item down the normal seq_item path to the slave driver -- all in zero
// simulation time so the driver can complete with zero wait states.
class ovip_apb_slave_sequencer extends uvm_sequencer#(ovip_apb_trans);

	uvm_blocking_get_port#(ovip_apb_trans) response_req_port;

	// Set by the agent at connect_phase for slave-sequence convenience
	// (cfg for width math, slave_drv for direct pokes if a test needs them).
	ovip_apb_agent_config cfg;
	ovip_apb_slave_driver slave_drv;

	`uvm_component_utils(ovip_apb_slave_sequencer)

	function new(string name = "ovip_apb_slave_sequencer", uvm_component parent);
		super.new(name, parent);
		response_req_port = new("response_req_port", this);
	endfunction : new

endclass : ovip_apb_slave_sequencer

`endif
