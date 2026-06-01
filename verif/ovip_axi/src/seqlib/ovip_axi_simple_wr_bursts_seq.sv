
class ovip_axi_simple_wr_bursts_seq extends uvm_sequence#(ovip_axi_trans);

	int num_trans = 1;
	int min_burst_len = 0;
	int max_burst_len = 0;

	int min_delay_between_beats = 0;
	int max_delay_between_beats = 1;

	int min_initial_delay_between_beats = -1;
	int max_initial_delay_between_beats = -1;

	ovip_axi_burst_t burst = OVIP_AXI_BURST_INCR;
	ovip_axi_data_start_event_t data_start_event = OVIP_AXI_DATA_START_EV_ADDR_DRIVEN;

	ovip_axi_id_t id[$];
	ovip_axi_addr_t addr[$];
	int len[$];
	ovip_axi_size_t size[$];

	ovip_axi_trans tr_pool[];

	`uvm_declare_p_sequencer(ovip_axi_base_sequencer)
	`uvm_object_utils(ovip_axi_simple_wr_bursts_seq)

	function new(string name = "ovip_axi_simple_wr_bursts_seq");
		super.new(name);
	endfunction

	virtual task body();
		tr_pool = new[num_trans];

		set_response_queue_depth(num_trans);

		if(!p_sequencer.cfg.auto_byte_lanes_alignment)
			`uvm_fatal("BAD_USE", "ovip_axi_simple_wr_bursts_seq need auto_byte_lanes_alignment=1 in order to drive good strb")

		while(addr.size() < num_trans)
		begin
			addr.push_back($urandom);
		end
		while(len.size() < num_trans)
		begin
			len.push_back($urandom_range(max_burst_len, min_burst_len));
		end
		while(size.size() < num_trans)
		begin
			size.push_back(ovip_axi_size_t'($clog2(p_sequencer.cfg.bus_width)));
		end
		for(int ii=0; id.size()<num_trans; ii++)
		begin
			id.push_back(ii);
		end

	 //uvm_root::get().finish_on_completion = 0;	
		foreach(tr_pool[idx])
		begin
			int ii = idx;
			begin
				ovip_axi_trans tr;
				tr_pool[ii] = ovip_axi_trans::type_id::create($sformatf("tr_pool[%0d]",ii));
				tr = tr_pool[ii];

				start_item(tr);
				tr.tr_type = OVIP_AXI_WRITE_TRANS;
				tr.id    = id[ii] & ((ovip_axi_id_t'(1)<<p_sequencer.cfg.wr_id_width)-1);
				tr.addr  = addr[ii];
				tr.len   = len[ii];
				tr.size  = size[ii];

				tr.awuser = ii & ((ovip_axi_user_t'(1)<<p_sequencer.cfg.awuser_width)-1);
				tr.burst = burst;
				tr.data_start_event = data_start_event;

				// alignment
				//tr.addr <<= p_sequencer.cfg.bus_width;

				tr.addr &= ((ovip_axi_addr_t'(1)<<p_sequencer.cfg.addr_width)-1);

				repeat(tr.len+1)
				begin
					int burst_size = 1<<tr.size;
					ovip_axi_strb_t wstrb;
					ovip_axi_data_t wdata;

					repeat(4) begin wstrb <<= 32; wstrb |= $urandom; end
					repeat(32) begin wdata <<= 32; wdata |= $urandom; end
					tr.strb_beats.push_back(wstrb & ((ovip_axi_strb_t'(1)<<burst_size)-1));
					tr.data_beats.push_back(wdata & ((ovip_axi_data_t'(1)<<(burst_size*8))-1));

					// fixing bad strb on first beat on case of unaligned access
					// (for FIXED burst type it applys for all transfers)
					// BTW, this sequence assume auto_byte_lanes_alignment
					if((tr.strb_beats.size() == 1 || burst==OVIP_AXI_BURST_FIXED) && tr.addr%burst_size != 0)
					begin
						tr.strb_beats[$] >>= burst_size-(tr.addr%burst_size);
					end

					if(tr.data_delay.size()==0 && min_initial_delay_between_beats != -1)
						tr.data_delay.push_back($urandom_range(max_initial_delay_between_beats,min_initial_delay_between_beats));
					else
						tr.data_delay.push_back($urandom_range(max_delay_between_beats,min_delay_between_beats));
				end

				finish_item(tr);
			end
		end

		foreach(tr_pool[ii])
		begin
			get_response(tr_pool[ii]);
		end

	endtask : body
endclass

