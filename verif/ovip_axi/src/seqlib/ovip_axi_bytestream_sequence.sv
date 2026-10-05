`ifndef OVIP_AXI_BYTESTREAM_SEQUENCE__SV
`define OVIP_AXI_BYTESTREAM_SEQUENCE__SV

// A byte stream on the bus, in either direction.
//
// Write: `data` (one strobe per byte in `strb`, all on by default) lands at
// `addr`. Read: `read_size` bytes from `addr` come back in `data`. The
// sequence splits the stream into bursts of `size` bytes per beat, up to
// `max_len`+1 beats each:
//   INCR  -- the stream runs up the address from `addr`. An unaligned start
//            uses partial byte lanes on the first beat. No burst crosses
//            4 KiB.
//   FIXED -- every beat is on `addr` and its byte lanes, so the stream is a
//            packet into (or out of) one data register: beat k carries bytes
//            k*size .. k*size+size-1 of it (fewer when `addr` is unaligned).
//            A burst has at most 16 beats (AXI4).
// On an AXI4-Lite port every burst is one beat of the bus width.
//
// After body() returns, `trans` holds the bursts in order with what the
// driver put back: `resp` (BRESP, or the worst RRESP), `resp_beats` on a
// read. worst_resp() and all_okay() sum them up.
//
// The bursts are sent back to back and then drained, so the driver pipelines
// them up to the agent's outstanding limit. They share `id`, which keeps the
// responses in order.

class ovip_axi_bytestream_sequence extends ovip_axi_base_master_sequence;

	ovip_axi_transaction_type_t tr_type = OVIP_AXI_WRITE_TRANS;
	ovip_axi_burst_t burst = OVIP_AXI_BURST_INCR;   // INCR or FIXED; WRAP is refused

	ovip_axi_addr_t addr = 0;
	ovip_axi_id_t   id   = 0;

	// AxSIZE as log2 of the bytes per beat. -1 (the default) is the bus width.
	// An ovip_axi_size_t value assigns to it directly.
	int size = -1;

	// The largest AxLEN of one burst. -1 (the default) is what the port
	// allows: 2^len_width - 1, at most 255, at most 15 on FIXED, 0 on Lite.
	// A smaller value caps the bursts, for a slave or a fabric that takes less.
	int max_len = -1;

	ovip_bytestream data;
	bit strb[$];
	int read_size;

	// Optional timing (0 = back-to-back, the default). When > 0, randomize per-beat write
	// data delays / the gap before the next transaction's address phase, in [0, max].
	int max_data_delay = 0;
	int max_addr_delay = 0;

	// Where a write's data starts against its address (see the README's timing
	// section), and with BEFORE_ADDR how long the address waits, random in
	// [0, max] per burst. Ready patterns the master drives on R and B, applied
	// to every burst when their `cycles` is not empty (empty keeps the driver's).
	ovip_axi_data_start_event_t data_start_event = OVIP_AXI_DATA_START_EV_ADDR_DRIVEN;
	int max_addr_phase_delay = 0;
	ovip_axi_ready_pattern_t rready_pattern;
	ovip_axi_ready_pattern_t bready_pattern;

	// The bursts the stream split into, in order, as the driver put them back.
	ovip_axi_trans trans[$];

	protected bit auto_byte_lanes_alignment;
	protected int bus_width;
	protected int burst_size;   // bytes per beat
	protected int len_cap;      // the largest AxLEN this run uses

	// Variables initialized by the split functions
	protected ovip_axi_addr_t axi_addr[$]; // Array of AXI addresses, one per burst
	protected int unsigned axi_len[$];     // Array of AXI transaction lengths, one per burst

	protected int wr_data_ptr;

	`uvm_declare_p_sequencer(ovip_axi_base_sequencer)
	`uvm_object_utils(ovip_axi_bytestream_sequence)

	function new(string name = "ovip_axi_bytestream_sequence");
		super.new(name);   // the base leaves the response queue unbounded
	endfunction

	virtual task pre_body();
		auto_byte_lanes_alignment = p_sequencer.cfg.auto_byte_lanes_alignment;
		bus_width = int'(p_sequencer.cfg.bus_width);

		if(p_sequencer.cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE)
		begin
			// one beat of the bus width per transaction; AWBURST is not a Lite pin
			size    = $clog2(bus_width);
			burst   = OVIP_AXI_BURST_INCR;
			len_cap = 0;
		end
		else
		begin
			if(size < 0) size = $clog2(bus_width);
			len_cap = (1 << p_sequencer.cfg.len_width) - 1;
			if(len_cap > 255) len_cap = 255;
			if(burst == OVIP_AXI_BURST_FIXED && len_cap > 15) len_cap = 15;
			if(max_len >= 0 && max_len < len_cap) len_cap = max_len;
		end
		burst_size = 1 << size;

		if(burst == OVIP_AXI_BURST_WRAP)
			`uvm_fatal("OVIP_AXI/BYTESTREAM", "a WRAP burst is not a byte stream; use INCR or FIXED")
		if(burst_size > bus_width)
			`uvm_fatal("OVIP_AXI/BYTESTREAM", $sformatf("size %0d (%0d bytes per beat) is wider than the bus (%0d bytes)", size, burst_size, bus_width))

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
		trans.delete();
	endtask : pre_body


	// INCR: the stream from `addr` upward, cut at 4 KiB and at len_cap+1 beats
	virtual function void split_incr();
		ovip_axi_addr_t tr_addr = addr;
		int unsigned tr_size = ((tr_type == OVIP_AXI_WRITE_TRANS) ? data.size() : read_size);
		int unsigned burst_bytes = burst_size * (len_cap + 1);
		int unalignment = tr_addr % burst_size;

		// Align the start down to the beat; the first beat carries fewer bytes
		tr_addr -= unalignment;
		tr_size += unalignment;

		while(tr_size)
		begin
			int unsigned num_bytes = tr_size;
			int unsigned to_4k = 'h1000 - (tr_addr & 'hfff);   // tr_addr is beat aligned, so this is whole beats
			if(num_bytes > to_4k)       num_bytes = to_4k;
			if(num_bytes > burst_bytes) num_bytes = burst_bytes;

			axi_addr.push_back(tr_addr);
			axi_len.push_back(int'($ceil(num_bytes / real'(burst_size))) - 1);

			tr_addr += num_bytes;
			tr_size -= num_bytes;
		end

		// The first burst starts where the stream starts
		axi_addr[0] += unalignment;
	endfunction : split_incr


	// FIXED: every beat on `addr`; a beat carries the bytes from addr's lane to the end of the beat
	virtual function void split_fixed();
		int unsigned tr_size = ((tr_type == OVIP_AXI_WRITE_TRANS) ? data.size() : read_size);
		int bytes_per_beat = burst_size - (addr % burst_size);
		int unsigned beats = (tr_size + bytes_per_beat - 1) / bytes_per_beat;

		while(beats)
		begin
			int unsigned n = (beats > len_cap + 1) ? len_cap + 1 : beats;
			axi_addr.push_back(addr);
			axi_len.push_back(n - 1);
			beats -= n;
		end
	endfunction : split_fixed


	virtual function void split_addr_range_to_axi_chunks();
		axi_addr.delete();
		axi_len.delete();
		if(burst == OVIP_AXI_BURST_FIXED) split_fixed();
		else                              split_incr();
	endfunction : split_addr_range_to_axi_chunks


	// The bytes of a beat that are in the stream: a full beat, less the lanes
	// below `addr` on the first beat of an INCR burst and on every FIXED beat
	protected function int valid_bytes_in_beat(ovip_axi_trans tr, int beat);
		if(beat == 0 || burst == OVIP_AXI_BURST_FIXED) return burst_size - (tr.addr % burst_size);
		return burst_size;
	endfunction : valid_bytes_in_beat


	virtual function void initialize_axi_write_trans_with_data(ovip_axi_trans tr);
		// Loop through each beat of the transaction
		for(int beat = 0; beat <= tr.len; beat++)
		begin
			int num_valid_bytes = valid_bytes_in_beat(tr, beat);

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
			int num_valid_bytes = valid_bytes_in_beat(tr, beat);

			// Handle the case where the number of valid bytes on the last beat might be less
			if(beat == tr.len && (data.size() + num_valid_bytes) >= read_size)
				num_valid_bytes = read_size - data.size();

			// Append bytes to the temporary data stream
			for (int bb = 0; bb < num_valid_bytes; bb++)
				data.push_back(tr.data_beats[beat][bb * 8 +: 8]);
		end
	endfunction : retrieve_data_from_axi_read_trans


	// The worst response over the bursts (DECERR over SLVERR over EXOKAY over OKAY)
	function ovip_axi_resp_t worst_resp();
		ovip_axi_resp_t r = OVIP_AXI_RESP_OKAY;
		foreach(trans[ii]) r = ovip_axi_trans::worst_resp(r, trans[ii].resp);
		return r;
	endfunction : worst_resp

	function bit all_okay();
		return worst_resp() == OVIP_AXI_RESP_OKAY;
	endfunction : all_okay


	virtual task body();
		ovip_axi_trans rsp;
		split_addr_range_to_axi_chunks();

		foreach(axi_addr[ii])
		begin
			ovip_axi_trans tr = ovip_axi_trans::type_id::create($sformatf("trans[%0d]",trans.size()));
			trans.push_back(tr);

			start_item(tr);
			tr.tr_type = tr_type;
			tr.burst   = burst;
			tr.size    = ovip_axi_size_t'(size);
			tr.id      = id;
			tr.addr    = axi_addr[ii];
			tr.len     = axi_len[ii];

			if(tr_type == OVIP_AXI_WRITE_TRANS)
			begin
				initialize_axi_write_trans_with_data(tr);
				if(max_data_delay > 0)
					repeat(tr.len+1) tr.data_delay.push_back($urandom_range(max_data_delay, 0));
				tr.data_start_event = data_start_event;
				tr.addr_phase_delay = (max_addr_phase_delay > 0) ? $urandom_range(max_addr_phase_delay, 0) : 0;
			end

			tr.delay_until_next_addr = (max_addr_delay > 0) ? $urandom_range(max_addr_delay, 0) : 0;
			if(rready_pattern.cycles.size()) tr.rready_pattern = rready_pattern;
			if(bready_pattern.cycles.size()) tr.bready_pattern = bready_pattern;
			finish_item(tr);
		end

		// One id, so the responses come back in order. The driver puts the
		// same object back, with the read data and the responses on it.
		foreach(trans[ii])
		begin
			get_response(rsp);
			trans[ii] = rsp;
			if(tr_type == OVIP_AXI_READ_TRANS)
				retrieve_data_from_axi_read_trans(trans[ii]);
		end
	endtask : body

endclass : ovip_axi_bytestream_sequence

`endif
