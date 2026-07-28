`ifndef OVIP_APB_BASE_MASTER_SEQUENCE__SV
`define OVIP_APB_BASE_MASTER_SEQUENCE__SV

// Canonical base for requester-side sequences. The master driver uses
// get_next_item / item_done, so `send(tr)` (= start_item + finish_item)
// blocks until the wire-level transfer has completed -- and because the
// driver samples PRDATA/PSLVERR back into the item, `tr.rdata` / `tr.slverr`
// are valid as soon as send() returns. The `apb_write` / `apb_read` helpers
// wrap that round trip for directed sequences.
class ovip_apb_base_master_sequence extends uvm_sequence#(ovip_apb_trans);
	`uvm_object_utils(ovip_apb_base_master_sequence)

	function new(string name = "ovip_apb_base_master_sequence");
		super.new(name);
	endfunction : new

	virtual task send(ovip_apb_trans tr);
		start_item(tr);
		finish_item(tr);
	endtask : send


	// Blocking write. `strb` defaults to all-ones (full-word write); only the
	// low data_width bits are used by the driver. Returns the completer's
	// error response.
	virtual task apb_write(ovip_apb_addr_t addr, ovip_apb_data_t data,
	                       ovip_apb_strb_t strb = '1, ovip_apb_prot_t prot = '0,
	                       output bit slverr);
		ovip_apb_trans tr = ovip_apb_trans::type_id::create("wr_tr");
		tr.addr   = addr;
		tr.write  = 1;
		tr.wdata  = data;
		tr.strb   = strb;
		tr.prot   = prot;
		tr.delay_until_next_trans = 0;
		send(tr);
		slverr = tr.slverr;
	endtask : apb_write


	// Blocking read. Returns the read data and the completer's error response.
	virtual task apb_read(ovip_apb_addr_t addr, output ovip_apb_data_t data,
	                      output bit slverr, input ovip_apb_prot_t prot = '0);
		ovip_apb_trans tr = ovip_apb_trans::type_id::create("rd_tr");
		tr.addr   = addr;
		tr.write  = 0;
		tr.strb   = 0;
		tr.prot   = prot;
		tr.delay_until_next_trans = 0;
		send(tr);
		data   = tr.rdata;
		slverr = tr.slverr;
	endtask : apb_read

endclass : ovip_apb_base_master_sequence

`endif
