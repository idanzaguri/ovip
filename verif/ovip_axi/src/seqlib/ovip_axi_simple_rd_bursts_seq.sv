class ovip_axi_simple_rd_bursts_seq extends uvm_sequence#(ovip_axi_trans);

	int num_trans = 1;
	int min_burst_len = 0;
	int max_burst_len = 0;

	int min_delay_between_req = 0;
	int max_delay_between_req = 1;

	ovip_axi_burst_t burst = OVIP_AXI_BURST_INCR;	
	ovip_axi_trans tr_pool[];
	ovip_axi_addr_t addr[$];
	int len[$];
	ovip_axi_size_t size[$];

	`uvm_declare_p_sequencer(ovip_axi_base_sequencer)
	`uvm_object_utils(ovip_axi_simple_rd_bursts_seq)

	function new(string name = "ovip_axi_simple_rd_bursts_seq");
		super.new(name);
	endfunction

	// A random address for a burst of len+1 beats of 2**size bytes, inside
	// addr_width: an INCR burst stays inside its 4KB page, a WRAP burst
	// starts aligned to its beat size.
	protected function ovip_axi_addr_t random_addr(int len, ovip_axi_size_t size);
		ovip_axi_addr_t  a     = $urandom & ((ovip_axi_addr_t'(1)<<p_sequencer.cfg.addr_width)-1);
		longint unsigned beat  = longint'(1) << size;
		longint unsigned total = (len + 1) * beat;
		if(burst == OVIP_AXI_BURST_WRAP)
			a -= a % beat;
		else if(burst == OVIP_AXI_BURST_INCR)
		begin
			longint unsigned page_off = (a & 'hFFF) & ~(beat - 1);   // where the first beat's container starts in the page
			if(total > 'h1000)
			begin
				`uvm_warning("BAD_USE", $sformatf("an INCR burst of %0d beats of %0dB does not fit in a 4KB page", len + 1, beat))
				a -= page_off;
			end
			else if(page_off + total > 'h1000)
				a -= page_off + total - 'h1000;
		end
		return a;
	endfunction : random_addr

	virtual task body();
		tr_pool = new[num_trans];
		set_response_queue_depth(num_trans);
	
		while(size.size() < num_trans)
		begin
			size.push_back(ovip_axi_size_t'($clog2(p_sequencer.cfg.bus_width)));
		end
		while(len.size() < num_trans)
		begin
			len.push_back($urandom_range(max_burst_len, min_burst_len));
		end
		while(addr.size() < num_trans)
		begin
			addr.push_back(random_addr(len[addr.size()], size[addr.size()]));
		end


		foreach(tr_pool[idx])
		begin
			int ii = idx;
			begin
				ovip_axi_trans tr;
				tr_pool[ii] = ovip_axi_trans::type_id::create($sformatf("tr_pool[%0d]",ii));
				tr = tr_pool[ii];
				start_item(tr);
				tr.tr_type = OVIP_AXI_READ_TRANS;
				tr.burst = burst;
				tr.addr  = addr[ii];
				tr.size  = size[ii];
				tr.len   = len[ii];
				tr.id    = ii & ((ovip_axi_id_t'(1)<<p_sequencer.cfg.rd_id_width)-1);
				tr.delay_until_next_addr = $urandom_range(max_delay_between_req, min_delay_between_req);
				finish_item(tr);
			end
		end

		foreach(tr_pool[ii])
		begin
			get_response(tr_pool[ii]);
		end

	endtask : body
endclass

