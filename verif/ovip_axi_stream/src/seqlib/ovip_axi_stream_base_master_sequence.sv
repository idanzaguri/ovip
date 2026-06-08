`ifndef OVIP_AXI_STREAM_BASE_MASTER_SEQUENCE__SV
`define OVIP_AXI_STREAM_BASE_MASTER_SEQUENCE__SV

// Canonical base for transmitter-side sequences. The master driver uses
// get_next_item / item_done, so `send(tr)` (= start_item + finish_item)
// blocks until the wire-level packet has been driven completely. Subclasses
// override `body()` to build and send their packets.
class ovip_axi_stream_base_master_sequence extends uvm_sequence#(ovip_axi_stream_trans);
	`uvm_object_utils(ovip_axi_stream_base_master_sequence)

	function new(string name = "ovip_axi_stream_base_master_sequence");
		super.new(name);
	endfunction : new

	virtual task send(ovip_axi_stream_trans tr);
		start_item(tr);
		finish_item(tr);
	endtask : send

endclass : ovip_axi_stream_base_master_sequence

`endif
