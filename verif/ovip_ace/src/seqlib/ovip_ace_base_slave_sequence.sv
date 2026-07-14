`ifndef OVIP_ACE_BASE_SLAVE_SEQUENCE__SV
`define OVIP_ACE_BASE_SLAVE_SEQUENCE__SV

// Canonical base for ACE slave/interconnect-side responders. Inherits the whole
// memory-backed loopback (read fill / write capture, per-transaction response
// timing, SLVERR on malformed requests) from ovip_axi_base_slave_sequence.
//
// The one ACE-specific adjustment is the write-commit timing: the AXI base
// defers the memory update until BRESP is sampled, and that deferred path
// dereferences p_sequencer.vif. On an ACE agent that AXI-typed handle is left
// null (the ACE interface is a distinct virtual type -- see ovip_ace_agent), so
// we switch to immediate commit (wr_mem_update_on_bresp = 0), which never
// touches vif.
//
// R-channel IsShared / PassDirty default to 0 (a Shared-Clean style response).
// Override fill_ace_read_response() to model a slave that returns dirty or
// exclusive data.

class ovip_ace_base_slave_sequence extends ovip_axi_base_slave_sequence;

	`uvm_object_utils(ovip_ace_base_slave_sequence)

	function new(string name = "ovip_ace_base_slave_sequence");
		super.new(name);
		// Commit writes on WLAST rather than on BRESP -- see class header.
		wr_mem_update_on_bresp = 0;
	endfunction

	// Hook: set RRESP[3:2] (IsShared / PassDirty) on a read response. Default is
	// a clean, non-shared line. The req is an ovip_ace_trans thanks to the
	// agent's factory override.
	virtual function void fill_ace_read_response(ovip_ace_trans req);
		req.is_shared  = 1'b0;
		req.pass_dirty = 1'b0;
	endfunction : fill_ace_read_response

	// Extend the AXI read path to stamp the ACE response bits, then defer to the
	// inherited memory fill.
	virtual task populate_data_from_mem(ovip_axi_trans tr);
		ovip_ace_trans ace_tr;
		if($cast(ace_tr, tr)) fill_ace_read_response(ace_tr);
		super.populate_data_from_mem(tr);
	endtask : populate_data_from_mem

endclass : ovip_ace_base_slave_sequence

`endif
