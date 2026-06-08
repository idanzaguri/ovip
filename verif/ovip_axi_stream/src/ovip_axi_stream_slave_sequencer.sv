`ifndef OVIP_AXI_STREAM_SLAVE_SEQUENCER__SV
`define OVIP_AXI_STREAM_SLAVE_SEQUENCER__SV

// Sequencer for the receiver-side slave sequence. The slave sequence pulls
// monitor-captured packets off `response_req_port` (connected to the
// monitor's response_req_port) and uses them to update the slave driver's
// TREADY pattern or to inject errors. There is no item-port traffic to the
// slave driver, since the driver is pattern-driven, not item-driven.
class ovip_axi_stream_slave_sequencer extends uvm_sequencer#(ovip_axi_stream_trans);

	uvm_blocking_get_port#(ovip_axi_stream_trans) response_req_port;

	// Handle to the slave driver, set by the agent at connect_phase so the
	// slave sequence can push new ready patterns through the driver's
	// `put_tready_pattern(...)` helper.
	ovip_axi_stream_slave_driver slave_drv;

	`uvm_component_utils(ovip_axi_stream_slave_sequencer)

	function new(string name = "ovip_axi_stream_slave_sequencer", uvm_component parent);
		super.new(name, parent);
		response_req_port = new("response_req_port", this);
	endfunction : new

endclass : ovip_axi_stream_slave_sequencer

`endif
