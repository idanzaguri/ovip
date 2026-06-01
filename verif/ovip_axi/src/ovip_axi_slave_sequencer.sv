`ifndef OVIP_AXI_SLAVE_SEQUENCER__SV
`define OVIP_AXI_SLAVE_SEQUENCER__SV

//`uvm_blocking_get_imp_decl (_rsp_req)

class ovip_axi_slave_sequencer extends ovip_axi_base_sequencer;

	uvm_blocking_get_port#(ovip_axi_trans) response_req_port;

	`uvm_component_utils(ovip_axi_slave_sequencer)

	function new(string name = "ovip_axi_slave_sequencer", uvm_component parent);
		super.new(name, parent);
		response_req_port = new("response_req_port", this);
	endfunction

	extern virtual function void build_phase(uvm_phase phase);

endclass : ovip_axi_slave_sequencer

function void ovip_axi_slave_sequencer::build_phase(uvm_phase phase);
	super.build_phase(phase);
endfunction : build_phase
`endif
