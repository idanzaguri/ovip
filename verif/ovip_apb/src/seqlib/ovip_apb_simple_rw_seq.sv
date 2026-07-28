`ifndef OVIP_APB_SIMPLE_RW_SEQ__SV
`define OVIP_APB_SIMPLE_RW_SEQ__SV

// Writes `num_transfers` random words inside [base_addr, base_addr +
// addr_window), then reads each address back and checks the data returned by
// the completer against what was written. Self-checking against a
// memory-backed completer (the base slave sequence); any SLVERR or data
// mismatch raises a uvm_error. Use it for generic round-trip smoke traffic.
class ovip_apb_simple_rw_seq extends ovip_apb_base_master_sequence;
	`uvm_object_utils(ovip_apb_simple_rw_seq)

	rand int num_transfers = 8;

	// Address window the traffic stays inside. Kept word-aligned per the
	// agent's data width via `data_width` below.
	ovip_apb_addr_t base_addr   = 0;
	int unsigned    addr_window = 256;

	// Bus width in bytes; must match the agent's cfg.data_width so generated
	// addresses stay aligned.
	int unsigned data_width = 4;

	// 0 = every transfer back-to-back; N = random gap in [0:N] after each.
	int unsigned max_gap = 4;

	constraint c_reasonable_count { soft num_transfers inside {[1:64]}; }

	function new(string name = "ovip_apb_simple_rw_seq");
		super.new(name);
	endfunction

	virtual task body();
		ovip_apb_addr_t addrs[$];
		ovip_apb_data_t written[ovip_apb_addr_t];

		// Distinct aligned addresses so the read-back check is unambiguous.
		int unsigned slots = addr_window / data_width;
		if(slots == 0)
			`uvm_fatal("APB_RW_SEQ", "addr_window smaller than one bus word")

		for(int ii = 0; ii < num_transfers; ii++)
		begin
			ovip_apb_trans tr = ovip_apb_trans::type_id::create($sformatf("wr_%0d", ii));
			ovip_apb_addr_t addr = base_addr + (($urandom_range(slots-1, 0)) * data_width);
			tr.addr  = addr;
			tr.write = 1;
			tr.wdata = {$urandom(), $urandom()} & ((ovip_apb_data_t'(1) << data_width*8) - 1);
			tr.strb  = (ovip_apb_strb_t'(1) << data_width) - 1;
			tr.prot  = '0;
			tr.delay_until_next_trans = max_gap ? $urandom_range(max_gap, 0) : 0;
			send(tr);
			if(tr.slverr)
				`uvm_error("APB_RW_SEQ", $sformatf("unexpected SLVERR on write to 0x%0h", addr))
			if(!written.exists(addr)) addrs.push_back(addr);
			written[addr] = tr.wdata; // last write wins on address reuse
		end

		foreach(addrs[ii])
		begin
			ovip_apb_data_t rdata;
			bit slverr;
			apb_read(addrs[ii], rdata, slverr);
			if(slverr)
				`uvm_error("APB_RW_SEQ", $sformatf("unexpected SLVERR on read from 0x%0h", addrs[ii]))
			else if(rdata !== written[addrs[ii]])
				`uvm_error("APB_RW_SEQ", $sformatf("read-back mismatch at 0x%0h: wrote 0x%0h, read 0x%0h",
					addrs[ii], written[addrs[ii]], rdata))
		end
	endtask
endclass

`endif
