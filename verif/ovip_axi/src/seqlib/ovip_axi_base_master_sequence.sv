`ifndef OVIP_AXI_BASE_MASTER_SEQUENCE__SV
`define OVIP_AXI_BASE_MASTER_SEQUENCE__SV

// Convenience base for master-side stimulus sequences.
//
// The ovip_axi_master_driver uses the UVM "get/put" model: it pulls items off
// the sequencer via `seq_item_port.get(req)` and pushes the completed
// transaction back via `seq_item_port.put(rsp)` only after the bus side has
// finished. With that model, `start_item`/`finish_item` returns as soon as the
// driver *accepts* the item -- not when the bus transaction completes. A bare
// `seq.start(...)` then returns long before any real bus traffic is done.
//
// This base hides that bookkeeping behind two tasks:
//   - send(tr)             -- start_item + finish_item, and tracks the trans.
//   - wait_for_responses() -- blocks until the driver has put() back every
//                             trans we sent (i.e. every bus transaction has
//                             actually completed). Call this at the end of
//                             body() before returning.
//
// Use case for raw start_item/finish_item: when you need fine control over
// per-item arbitration priority or layering, write the trans-handling loop
// yourself and call get_response per item, like simple_wr_bursts_seq does.

class ovip_axi_base_master_sequence extends uvm_sequence#(ovip_axi_trans);

	protected ovip_axi_trans tr_pool[$];

	`uvm_object_utils(ovip_axi_base_master_sequence)

	function new(string name = "ovip_axi_base_master_sequence");
		super.new(name);
		// Unbounded response queue -- the driver pushes responses asynchronously
		// while we keep issuing items. The default depth (8) would block the
		// driver after the 8th in-flight item, serializing the bus.
		set_response_queue_depth(-1);
	endfunction

	// Send a single transaction to the driver. Returns when the driver has
	// accepted the item, NOT when the bus transaction completes. Call
	// wait_for_responses() at the end of body() to actually wait for the bus
	// side to finish.
	virtual task send(ovip_axi_trans tr);
		tr_pool.push_back(tr);
		start_item(tr);
		finish_item(tr);
	endtask : send

	// Block until the driver has put() back a response for every transaction
	// we've send()-ed so far. After this returns, every in-flight read has
	// delivered its data and every in-flight write has its BRESP, so body()
	// can safely return without leaving traffic on the bus.
	virtual task wait_for_responses();
		ovip_axi_trans rsp;
		foreach(tr_pool[ii]) get_response(rsp);
		tr_pool.delete();
	endtask : wait_for_responses

endclass : ovip_axi_base_master_sequence

`endif
