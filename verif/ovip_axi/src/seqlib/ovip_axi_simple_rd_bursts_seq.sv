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

	virtual task body();
		tr_pool = new[num_trans];
		set_response_queue_depth(num_trans);
	
		while(addr.size() < num_trans)
		begin
			addr.push_back($urandom);
			addr[$] &= ((ovip_axi_addr_t'(1)<<p_sequencer.cfg.addr_width)-1);
		end
		while(size.size() < num_trans)
		begin
			size.push_back(ovip_axi_size_t'($clog2(p_sequencer.cfg.bus_width)));
		end
		while(len.size() < num_trans)
		begin
			/*
			int idx = len.size()-1;
			int burst_size = 1<<size[idx];
			int unsigned aligned_addr = addr[idx]-addr[idx]%burst_size;
			int max_burst_len_4k = (4096 - aligned_addr%4096)/burst_size;	
			int min_burst_len_4k = min_burst_len;	
			if(max_burst_len < max_burst_len_4k) max_burst_len_4k = max_burst_len;
			if(min_burst_len > max_burst_len_4k) min_burst_len_4k = max_burst_len_4k;
			len.push_back($urandom_range(max_burst_len_4k, min_burst_len_4k));
			`uvm_error("dd",$sformatf("0x%0x %0dB [%0d:%0d] [%0d:%0d]",aligned_addr%4096,burst_size,min_burst_len_4k,max_burst_len_4k,min_burst_len,max_burst_len))
			*/
			len.push_back($urandom_range(max_burst_len, min_burst_len));
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
				tr.id    = ii;
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

