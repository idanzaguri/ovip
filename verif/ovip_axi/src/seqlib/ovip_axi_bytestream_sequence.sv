`ifndef OVIP_AXI_BYTESTREAM_SEQUENCE__SV
`define OVIP_AXI_BYTESTREAM_SEQUENCE__SV

class ovip_axi_bytestream_sequence extends uvm_sequence#(ovip_axi_trans);

	ovip_axi_transaction_type_t tr_type = OVIP_AXI_WRITE_TRANS;

	ovip_axi_addr_t  addr  = 0;
	ovip_axi_id_t    id    = 0;
	ovip_axi_size_t  size  = OVIP_AXI_SIZE_4B;

	ovip_bytestream data;
	bit strb[$];
	int read_size;

	// Optional timing (0 = back-to-back, the default). When > 0, randomize per-beat write
	// data delays / the gap before the next transaction's address phase, in [0, max].
	int max_data_delay = 0;
	int max_addr_delay = 0;

	// Response FIFO depth. The pool is sent and then drained in a batch, so responses pile
	// up while in flight; this must be >= the number of AXI transactions the bytestream
	// splits into. Raise it for very large byte streams.
	int response_queue_depth = 100;

	protected bit auto_byte_lanes_alignment;
	protected int bus_width;
	protected int burst_size;

	// Variables initialized by the split_addr_range_to_axi_chunks function
	protected ovip_axi_addr_t axi_addr[$]; // Array of AXI addresses, split from the original range
	protected int unsigned axi_len[$]; // Array of AXI transaction lengths, split from the original range
	protected int unsigned tr_valid_bytes[$]; // Array of valid bytes for each AXI transaction

	protected int wr_data_ptr;

	`uvm_declare_p_sequencer(ovip_axi_base_sequencer)
	`uvm_object_utils(ovip_axi_bytestream_sequence)

	function new(string name = "ovip_axi_bytestream_sequence");
		super.new(name);
	endfunction

	virtual task pre_body();
		set_response_queue_depth(response_queue_depth);

		auto_byte_lanes_alignment = p_sequencer.cfg.auto_byte_lanes_alignment;
		burst_size = 2**size;
		bus_width = int'(p_sequencer.cfg.bus_width);

		if(tr_type == OVIP_AXI_WRITE_TRANS)
		begin
			int diff = data.size()-strb.size();
			repeat(diff) strb.push_back(1);
			wr_data_ptr = 0;
		end
		else
		begin
			data = {};
		end

	endtask : pre_body

	virtual function void split_addr_range_to_axi_chunks();

		ovip_axi_addr_t tr_addr = addr;
		int unsigned tr_size = ((tr_type == OVIP_AXI_WRITE_TRANS) ? data.size() : read_size);
		int max_bytes_per_transaction;
		int unalignment = tr_addr % burst_size; // Calculate misalignment to align address to burst size

		// Align address to burst boundary
		tr_addr -= unalignment;
		tr_size += unalignment;

		// Determine the maximum bytes per transaction based on size and length width
		max_bytes_per_transaction = (2**size) * (1<<p_sequencer.cfg.len_width);
		if(max_bytes_per_transaction > 'h1000) max_bytes_per_transaction = 'h1000;

		// Clear previous results
		axi_addr.delete();
		axi_len.delete();
		tr_valid_bytes.delete();

		// Split address range into AXI transactions
		while(tr_size)
		begin
			// Determine the size of the current transaction
			int num_bytes[$] = '{
				tr_size, // Remaining data size
				(max_bytes_per_transaction - (tr_addr & (max_bytes_per_transaction - 1))) // Maximum bytes per transaction, aligned to the burst size
			};
			if(num_bytes[0] > num_bytes[1]) num_bytes[0] = num_bytes[1];

			// Store transaction parameters
			tr_valid_bytes.push_back(num_bytes[0]);
			axi_addr.push_back(tr_addr);
			axi_len.push_back(int'($ceil(num_bytes[0] / real'(burst_size))) - 1);

			// Update address and size for the next transaction
			tr_addr += num_bytes[0];
			tr_size -= num_bytes[0];
		end

		// Adjust the first transaction to account for the initial alignment offset
		axi_addr[0] += unalignment;
		tr_valid_bytes[0] -= unalignment;

	endfunction : split_addr_range_to_axi_chunks


	virtual function void initialize_axi_write_trans_with_data(ovip_axi_trans tr);
		// Loop through each beat of the transaction
		for(int beat = 0; beat <= tr.len; beat++)
		begin
			int num_valid_bytes = burst_size;

			// Handle unaligned access on the first beat
			if(beat == 0) num_valid_bytes -= tr.addr % burst_size;

			// Handle the case where the number of valid bytes on the last beat might be less
			if(wr_data_ptr + num_valid_bytes >= data.size())
				num_valid_bytes = data.size() - wr_data_ptr;

			// Copy data and strobe values for the current beat
			for(int bb = 0; bb < num_valid_bytes; bb++, wr_data_ptr++)
			begin
				tr.data_beats[beat][bb*8 +: 8] = data[wr_data_ptr];
				tr.strb_beats[beat][bb] = strb[wr_data_ptr];
			end
		end

		// Handle byte lane alignment if required
		if(!auto_byte_lanes_alignment)
		begin
			tr.bus_width = p_sequencer.cfg.bus_width;
			tr.calculate_transfer_starting_byte_lane();

			// Adjust data and strobe beats
			foreach(tr.data_beats[ii])
			begin
				tr.data_beats[ii] <<= tr.transfer_starting_byte_lane[ii] * 8;
				tr.strb_beats[ii] <<= tr.transfer_starting_byte_lane[ii];
			end
		end
	endfunction : initialize_axi_write_trans_with_data


	virtual function void retrieve_data_from_axi_read_trans(ovip_axi_trans tr);
		// Align all data beats manually if port is not configured with auto_byte_lanes_alignment
		if (!auto_byte_lanes_alignment)
		begin
			tr.bus_width = p_sequencer.cfg.bus_width;
			tr.calculate_transfer_starting_byte_lane();

			// Adjust each data beat according to the calculated starting byte lane
			foreach (tr.data_beats[beat])
				tr.data_beats[beat] >>= tr.transfer_starting_byte_lane[beat] * 8;
		end

		// Collect data from each beat
		foreach (tr.data_beats[beat])
		begin
			int num_valid_bytes = burst_size;

			// Handle unaligned access on the first beat
			if (beat == 0) num_valid_bytes -= tr.addr % burst_size;

			// Handle the case where the number of valid bytes on the last beat might be less
			if(beat == tr.len && (data.size() + num_valid_bytes) >= read_size)
				num_valid_bytes = read_size - data.size();

			// Append bytes to the temporary data stream
			for (int bb = 0; bb < num_valid_bytes; bb++)
				data.push_back(tr.data_beats[beat][bb * 8 +: 8]);
		end
	endfunction : retrieve_data_from_axi_read_trans



	virtual task body();
		ovip_axi_trans tr_pool[$];
		split_addr_range_to_axi_chunks();

		foreach(axi_addr[ii])
		begin
			ovip_axi_trans tr = ovip_axi_trans::type_id::create($sformatf("tr_pool[%0d]",tr_pool.size()));
			tr_pool.push_back(tr);

			start_item(tr);
			tr.tr_type = tr_type;
			tr.burst   = OVIP_AXI_BURST_INCR;
			tr.size    = size;
			tr.id      = id;
			tr.addr    = axi_addr[ii];
			tr.len     = axi_len[ii];

			if(tr_type == OVIP_AXI_WRITE_TRANS)
			begin
				initialize_axi_write_trans_with_data(tr);
				if(max_data_delay > 0)
					repeat(tr.len+1) tr.data_delay.push_back($urandom_range(max_data_delay, 0));
			end

			tr.delay_until_next_addr = (max_addr_delay > 0) ? $urandom_range(max_addr_delay, 0) : 0;
			finish_item(tr);
		end


		foreach(tr_pool[ii])
		begin
			get_response(tr_pool[ii]);
			if(tr_type == OVIP_AXI_READ_TRANS)
			begin
				retrieve_data_from_axi_read_trans(tr_pool[ii]);
			end
		end
	endtask : body

endclass : ovip_axi_bytestream_sequence

`endif
