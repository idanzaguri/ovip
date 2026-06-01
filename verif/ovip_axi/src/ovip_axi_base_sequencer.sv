`ifndef OVIP_AXI_BASE_SEQUENCER__SV
`define OVIP_AXI_BASE_SEQUENCER__SV

typedef class ovip_axi_trans;
class ovip_axi_base_sequencer extends uvm_sequencer#(ovip_axi_trans);

	ovip_axi_agent_config cfg;
	virtual ovip_axi_agent_if vif;

	`uvm_component_utils(ovip_axi_base_sequencer)

	function new(string name = "ovip_axi_base_sequencer", uvm_component parent);
		super.new(name, parent);
	endfunction

endclass : ovip_axi_base_sequencer

`endif

