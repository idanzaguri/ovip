// Canonical base for slave-side sequences. Provides:
//   - A `forever` body() that reads requests off `response_req_port`, fills in
//     a response, and hands it back to the driver in zero simulation time
//     (see README "Writing Sequences" for the zero-time rule).
//   - A memory-backed read/write loopback against an `ovip_mem` (set the `mem`
//     handle on the sequence before `start()`).
//   - Auto-SLVERR on monitor-flagged malformed requests (4K-cross, bad burst
//     type, WSTRB/LAST/AWLEN mismatches -- see `tr.monitor_error`).
//   - Mid-test reset survival: the post-bresp memory-update watcher races the
//     wait with `!aresetn` so it doesn't leak processes across a reset.
//
// Extension points (virtual hooks -- override one, leave the rest to the base):
//   - get_response_code(req) -- inject SLVERR/DECERR (defaults to OKAY).
//   - get_bresp_delay()      -- per-transaction BRESP timing.
//   - set_read_trans_delays(req) -- per-beat / per-transaction read data timing.
//   - populate_data_from_mem(req) -- where read data comes from.
//   - write_transaction_to_mem(req) -- where write data goes.
//   - body() -- full override if none of the above fits.
//
// Preconditions:
//   - The `mem` handle is OPTIONAL. If assigned, the base does full
//     memory-backed read/write loopback for you. If left null, a subclass
//     MUST override `populate_data_from_mem` and `write_transaction_to_mem`
//     (otherwise the base fatals with a clear message at the first request).
//   - For FIXED and WRAP bursts, `burst_size <= memory_word_size` (one beat
//     per memory word -- enforced by uvm_fatal in the write/read helpers).

class ovip_axi_base_slave_sequence extends uvm_sequence#(ovip_axi_trans);

	// BRESP latency range, in cycles. The base picks a fresh value per
	// transaction via get_bresp_delay(); override either the knobs or the hook.
	rand int min_bresp_delay;
	rand int max_bresp_delay;

	// Back-to-back read-response probability, 0..100 (percent). When the random
	// draw hits, the entire read burst is collapsed to "delay before first beat,
	// zero between beats" -- simulating a fast slave that streams a full burst
	// once it starts.
	rand int b2b_rd_resp_prob;

	// Read-data per-beat latency range, in cycles. See `rdelay_per_beat` for
	// how the range is consumed per burst.
	rand int min_rdata_delay;
	rand int max_rdata_delay;

	// 1 = draw a fresh delay from [min_rdata_delay, max_rdata_delay] for each
	// beat. 0 = draw once per transaction and split evenly across beats (the
	// final delay carries the rounding remainder).
	rand bit rdelay_per_beat;


	// Handle to the backing memory for read fill / write capture. OPTIONAL:
	// leave null if the subclass overrides `populate_data_from_mem` and
	// `write_transaction_to_mem` to handle reads/writes its own way (register
	// slave, traffic-shaping stub, etc.). When non-null, the base does full
	// memory-backed loopback automatically.
	ovip_mem mem;

	// Controls *when* a write commits to memory:
	//   1 (default) = defer until BRESP is sampled by the master (i.e.,
	//                 `tr.transaction_finished` fires). Models a slave that
	//                 only commits the line after response handshake.
	//                 A subsequent read to the same address that races BRESP
	//                 will see the OLD value.
	//   0           = update memory immediately, right after the request
	//                 arrives (which itself happens after WLAST is sampled).
	//                 Models a simple write-on-WLAST slave. Subsequent reads
	//                 to the same address see the NEW value immediately.
	//                 Also cheaper in simulation -- no fork-join_none watcher.
	// Both modes correctly skip the memory write on SLVERR/DECERR responses.
	bit wr_mem_update_on_bresp = 1;
	protected int memory_word_size;
	protected ovip_axi_trans virt_mem_trans;


	`uvm_declare_p_sequencer(ovip_axi_slave_sequencer)
	`uvm_object_utils(ovip_axi_base_slave_sequence)


	// Default ranges used when (and only when) a test explicitly calls
	// `seq.randomize() with { ... };` -- this is for the constrained-random
	// path on full-featured simulators. Modelsim Starter FPGA (no randomize()
	// engine) ignores this block entirely; the base sequence stays functional
	// via the manual `$urandom_range` init in `new()` below.
	constraint c_default_ranges {
		soft min_bresp_delay  inside {[0:30]};
		soft max_bresp_delay  inside {[min_bresp_delay:30]};
		soft b2b_rd_resp_prob inside {[0:100]};
		soft min_rdata_delay  inside {[0:30]};
		soft max_rdata_delay  inside {[min_rdata_delay:30]};
		soft rdelay_per_beat  == 0;
	}

	function new(string name = "ovip_axi_base_slave_sequence");
		super.new(name);
		// Initialize via $urandom_range so the sequence is functional on
		// every simulator (no randomize() license required). Tests on
		// full-featured simulators may call `seq.randomize() with { ... };`
		// before `start()` to override these.
		b2b_rd_resp_prob = $urandom_range(0, 100);
		min_rdata_delay  = $urandom_range(30, 0);
		max_rdata_delay  = $urandom_range(30, min_rdata_delay);
		min_bresp_delay  = $urandom_range(30, 0);
		max_bresp_delay  = $urandom_range(30, min_bresp_delay);
		rdelay_per_beat  = 0;
	endfunction

	// Initialize the memory-backing scaffolding *only if* `mem` was assigned.
	// Leaving `mem` null is supported -- a subclass that wants a non-memory
	// backing (register slave, traffic-shaping stub, ...) skips memory setup
	// here and overrides `populate_data_from_mem` / `write_transaction_to_mem`
	// with its own read/write logic.
	virtual task pre_body();
		if(mem == null) return;
		memory_word_size = mem.get_word_size();
		virt_mem_trans = ovip_axi_trans::type_id::create("virt_mem_trans");
		virt_mem_trans.size      = ovip_axi_size_t'($clog2(memory_word_size));
		virt_mem_trans.bus_width = ovip_axi_bus_width_t'(memory_word_size);
	endtask : pre_body
	
	function void write_incr_burst_transaction_to_mem(ovip_axi_trans tr);
		int burst_size = 1<<tr.size;
		virt_mem_trans.addr = tr.addr - (tr.addr % memory_word_size); // aligned address to memory sturcture

		if(p_sequencer.cfg.auto_byte_lanes_alignment)
		begin
			ovip_axi_data_t first_wdata_beat = tr.data_beats[0];
			ovip_axi_strb_t first_wstrb_beat = tr.strb_beats[0];
			ovip_axi_bus_width_t original_bus_width = tr.bus_width;
			int unalignment = tr.addr % burst_size;
			tr.bus_width = ovip_axi_bus_width_t'(burst_size);
			tr.data_beats[0] <<= unalignment*8;
			tr.strb_beats[0] <<= unalignment;
			ovip_axi_trans::reshape_axi_transaction(tr, virt_mem_trans);

			tr.bus_width = original_bus_width;
			tr.data_beats[0] = first_wdata_beat;
			tr.strb_beats[0] = first_wstrb_beat;
		end
		else
		begin
			ovip_axi_trans::reshape_axi_transaction(tr, virt_mem_trans);
		end

		foreach(virt_mem_trans.data_beats[ii])
		begin
			mem.write(virt_mem_trans.addr, virt_mem_trans.data_beats[ii], virt_mem_trans.strb_beats[ii]);
			if(tr.burst == OVIP_AXI_BURST_INCR)
				virt_mem_trans.addr += memory_word_size;
		end
	endfunction : write_incr_burst_transaction_to_mem


	// WRAP: each beat goes to a different memory address inside the wrap
	// window, and the address wraps when it crosses the upper boundary.
	// Precondition: burst_size <= memory_word_size (one beat fits one word).
	function void write_wrap_burst_transaction_to_mem(ovip_axi_trans tr);
		int burst_size = 1 << tr.size;
		int total_size = burst_size * (tr.len + 1);
		ovip_axi_addr_t wrap_low = tr.addr & ~(total_size - 1);

		if(burst_size > memory_word_size)
			`uvm_fatal("OVIP_AXI/SLAVE_SEQ/MISSING_FEATURE",
				$sformatf("write_transaction_to_mem: For WRAP bursts, the burst size (%0dB) must not exceed the memory line size (%0dB).",
					burst_size, memory_word_size))

		for(int ii = 0; ii <= tr.len; ii++)
		begin
			ovip_axi_addr_t beat_addr = wrap_low + ((tr.addr - wrap_low + ii*burst_size) % total_size);
			ovip_axi_addr_t mem_addr  = beat_addr - (beat_addr % memory_word_size);
			int unsigned    word_lane = beat_addr % memory_word_size;
			ovip_axi_data_t wdata;
			ovip_axi_strb_t wstrb;

			if(p_sequencer.cfg.auto_byte_lanes_alignment)
			begin
				wdata = tr.data_beats[ii] << (word_lane * 8);
				wstrb = tr.strb_beats[ii] << word_lane;
			end
			else
			begin
				int unsigned bus_lane = beat_addr % tr.bus_width;
				wdata = (tr.data_beats[ii] >> (bus_lane * 8)) << (word_lane * 8);
				wstrb = (tr.strb_beats[ii] >> bus_lane) << word_lane;
			end

			mem.write(mem_addr, wdata, wstrb);
		end
	endfunction : write_wrap_burst_transaction_to_mem


	function void write_fixed_burst_transaction_to_mem(ovip_axi_trans tr);
		int burst_size = 1<<tr.size;
		virt_mem_trans.addr = tr.addr - (tr.addr % memory_word_size); // aligned address to memory sturcture

		if(burst_size > memory_word_size)
			`uvm_fatal("OVIP_AXI/SLAVE_SEQ/MISSING_FEATURE",
				$sformatf("write_transaction_to_mem: For FIXED bursts, the burst size (%0dB) must not exceed the memory line size (%0dB).",
					burst_size, memory_word_size))

		if(p_sequencer.cfg.auto_byte_lanes_alignment)
		begin
			int unalignment = tr.addr % burst_size;
			foreach(tr.data_beats[ii])
			begin
				ovip_axi_data_t wdata = tr.data_beats[ii] << unalignment*8;
				ovip_axi_strb_t wstrb = tr.strb_beats[ii] << unalignment;
				mem.write(virt_mem_trans.addr, wdata, wstrb);
			end
		end
		else
		begin
			int byte_lane_offset = (tr.addr%tr.bus_width) & ~(burst_size-1);
			foreach(tr.data_beats[ii])
			begin
				ovip_axi_data_t wdata = tr.data_beats[ii] >> byte_lane_offset*8;
				ovip_axi_strb_t wstrb = tr.strb_beats[ii] >> byte_lane_offset;
				mem.write(virt_mem_trans.addr, wdata, wstrb);
			end
		
		end
	endfunction : write_fixed_burst_transaction_to_mem


	task write_transaction_to_mem(ovip_axi_trans tr);
		if(mem == null)
			`uvm_fatal("OVIP_AXI/SLAVE_SEQ",
				"write_transaction_to_mem called with `mem == null`. Either assign `mem` before start(), or override write_transaction_to_mem in your subclass.")
		// Do not update the model in case of a bad transaction.
		if (tr.resp inside {OVIP_AXI_RESP_SLVERR, OVIP_AXI_RESP_DECERR}) begin
			`uvm_warning("OVIP_AXI/BAD_WR_RESP", "Received a write response with an error! Skipping memory update.")
			return;
		end

		if(tr.burst == OVIP_AXI_BURST_INCR)
		begin
			write_incr_burst_transaction_to_mem(tr);
			return;
		end

		if(tr.burst == OVIP_AXI_BURST_FIXED)
		begin
			write_fixed_burst_transaction_to_mem(tr);
			return;
		end

		if(tr.burst == OVIP_AXI_BURST_WRAP)
		begin
			write_wrap_burst_transaction_to_mem(tr);
			return;
		end

	endtask : write_transaction_to_mem


	// FIXED bursts re-read the same memory address for every beat. The beat
	// data lives somewhere inside the memory word starting at addr - addr%word;
	// we read the word, shift+mask down to the active byte range, then shift
	// up into the byte lane the master will drive (when auto-alignment is off).
	// Precondition: burst_size <= memory_word_size (one beat fits in one word).
	task populate_data_from_mem_fixed(ovip_axi_trans tr);
		int burst_size       = 1 << tr.size;
		int unalignment      = tr.addr % memory_word_size;
		ovip_axi_addr_t memory_addr = tr.addr - unalignment;
		int num_byte_per_transfer = burst_size - (tr.addr % burst_size);
		ovip_axi_data_t rdata_mask = (ovip_axi_data_t'(1) << (num_byte_per_transfer * 8)) - 1;
		int unsigned byte_lane_offset_bits = 0;

		if(burst_size > memory_word_size)
			`uvm_fatal("OVIP_AXI/SLAVE_SEQ/MISSING_FEATURE",
				$sformatf("populate_data_from_mem: For FIXED bursts, the burst size (%0dB) cannot exceed the memory line size (%0dB)",
					burst_size, memory_word_size))

		// With auto-alignment off the user expects rdata to arrive in the
		// byte lane the master is actually driving on the bus. With auto-
		// alignment on the byte-lane shift is applied later (by the driver).
		if(!p_sequencer.cfg.auto_byte_lanes_alignment)
		begin
			int unsigned lane = (tr.addr % tr.bus_width) & ~(burst_size - 1);
			lane += tr.addr % burst_size;
			byte_lane_offset_bits = lane * 8;
		end

		for(int ii = 0; ii <= tr.len; ii++)
		begin
			ovip_axi_data_t rdata = mem.read(memory_addr);
			rdata >>= unalignment * 8;       // drop bytes below the start of the beat
			rdata &= rdata_mask;             // mask bytes above the active range
			rdata <<= byte_lane_offset_bits; // place into the bus byte lane
			tr.data_beats.push_back(rdata);
		end
	endtask : populate_data_from_mem_fixed


	// INCR bursts walk memory linearly. Read enough memory words to cover the
	// AXI burst into a temp transaction sized at the memory word, then reshape
	// down to the transaction's beat size, trim the tail beats produced by the
	// round-up read, and (with auto-alignment) shift each beat to its starting
	// byte lane.
	task populate_data_from_mem_incr(ovip_axi_trans tr);
		int burst_size       = 1 << tr.size;
		int unalignment      = tr.addr % memory_word_size;
		ovip_axi_addr_t memory_addr = tr.addr - unalignment;
		int num_required_bytes;
		int num_memory_word_reads;

		virt_mem_trans.addr       = tr.addr;
		virt_mem_trans.tr_type    = OVIP_AXI_READ_TRANS;
		virt_mem_trans.burst      = OVIP_AXI_BURST_INCR;
		virt_mem_trans.data_beats = {};

		// Total bytes the AXI burst covers, minus the head bytes that fall
		// before the start address inside the first beat (those bytes aren't
		// part of the transaction). Round up to whole memory words, including
		// the head unalignment that sits at the very front of the first word.
		// NOTE: num_memory_word_reads is a plain int, NOT bounded by the 8-bit
		// AXI len -- the reshape below keys off data_beats.size() rather than
		// virt_mem_trans.len.
		num_required_bytes    = (1 + tr.len) * burst_size - (tr.addr % burst_size);
		num_memory_word_reads = int'($ceil((num_required_bytes + unalignment) / real'(memory_word_size)));

		for(int ii = 0; ii < num_memory_word_reads; ii++)
		begin
			virt_mem_trans.data_beats.push_back(mem.read(memory_addr));
			memory_addr += memory_word_size;
		end

		// Zero out byte lanes below the start address in the first memory word.
		// Those bytes were read but are outside the transaction; without this,
		// reshape would carry their (real but irrelevant) content into the
		// first AXI beat.
		if(unalignment)
			virt_mem_trans.data_beats[0] &= ~((ovip_axi_data_t'(1) << (unalignment * 8)) - 1);

		// Reshape from memory_word_size beats to tr.size beats, then trim any
		// extra tail beats produced by the round-up.
		ovip_axi_trans::reshape_axi_transaction(virt_mem_trans, tr);
		tr.data_beats = tr.data_beats[0 : tr.len];

		// With auto-alignment the driver expects each beat pre-shifted to its
		// starting byte lane; without it the data stays in its natural lane.
		if(p_sequencer.cfg.auto_byte_lanes_alignment)
		begin
			tr.calculate_transfer_starting_byte_lane();
			foreach(tr.data_beats[ii])
				tr.data_beats[ii] >>= tr.transfer_starting_byte_lane[ii] * 8;
		end
	endtask : populate_data_from_mem_incr


	// WRAP bursts walk memory beat by beat, with the address wrapping when it
	// crosses the upper boundary of the wrap window (`[wrap_low, wrap_low +
	// total_size)`). Read one memory word per beat, extract the burst_size
	// bytes at the beat's offset within the word, and place into the lane the
	// driver/master expects (lane 0 with auto-alignment, the bus byte lane
	// otherwise). Precondition: burst_size <= memory_word_size.
	task populate_data_from_mem_wrap(ovip_axi_trans tr);
		int burst_size = 1 << tr.size;
		int total_size = burst_size * (tr.len + 1);
		ovip_axi_addr_t wrap_low = tr.addr & ~(total_size - 1);
		ovip_axi_data_t rdata_mask = (ovip_axi_data_t'(1) << (burst_size * 8)) - 1;

		if(burst_size > memory_word_size)
			`uvm_fatal("OVIP_AXI/SLAVE_SEQ/MISSING_FEATURE",
				$sformatf("populate_data_from_mem: For WRAP bursts, the burst size (%0dB) cannot exceed the memory line size (%0dB)",
					burst_size, memory_word_size))

		for(int ii = 0; ii <= tr.len; ii++)
		begin
			ovip_axi_addr_t beat_addr = wrap_low + ((tr.addr - wrap_low + ii*burst_size) % total_size);
			ovip_axi_addr_t mem_addr  = beat_addr - (beat_addr % memory_word_size);
			int unsigned    word_lane = beat_addr % memory_word_size;
			ovip_axi_data_t rdata     = mem.read(mem_addr);

			rdata >>= word_lane * 8;     // drop bytes below the beat's start in the word
			rdata &= rdata_mask;         // keep only burst_size bytes

			if(!p_sequencer.cfg.auto_byte_lanes_alignment)
			begin
				int unsigned bus_lane = beat_addr % tr.bus_width;
				rdata <<= bus_lane * 8;
			end

			tr.data_beats.push_back(rdata);
		end
	endtask : populate_data_from_mem_wrap


	task populate_data_from_mem(ovip_axi_trans tr);
		if(mem == null)
			`uvm_fatal("OVIP_AXI/SLAVE_SEQ",
				"populate_data_from_mem called with `mem == null`. Either assign `mem` before start(), or override populate_data_from_mem in your subclass.")
		case(tr.burst)
			OVIP_AXI_BURST_FIXED: populate_data_from_mem_fixed(tr);
			OVIP_AXI_BURST_INCR : populate_data_from_mem_incr(tr);
			OVIP_AXI_BURST_WRAP : populate_data_from_mem_wrap(tr);
			default:
				`uvm_fatal("OVIP_AXI/BAD_BURST", $sformatf("populate_data_from_mem: unsupported burst type %s", tr.burst.name()))
		endcase
	endtask : populate_data_from_mem



	// Per-transaction response code. Override to inject SLVERR/DECERR; the
	// base always returns OKAY. The base body() will *still* force SLVERR
	// when `tr.monitor_error` is set (malformed request), regardless of what
	// this hook returns -- that path runs before the hook.
	virtual function ovip_axi_resp_t get_response_code(ovip_axi_trans tr);
		return OVIP_AXI_RESP_OKAY;
	endfunction : get_response_code


	virtual function int get_bresp_delay();
		return $urandom_range(max_bresp_delay, min_bresp_delay);
	endfunction : get_bresp_delay

	virtual function void set_read_trans_delays(ovip_axi_trans tr);
		int rd_delay = $urandom_range(max_rdata_delay, min_rdata_delay);
		bit b2b_rd_resp = ($urandom_range(99,0) < b2b_rd_resp_prob);
		if(b2b_rd_resp)
		begin
			tr.data_delay.push_back(rd_delay);
			repeat(tr.len) tr.data_delay.push_back(0);
		end
		else
		begin
			if(rdelay_per_beat)
			begin
				tr.data_delay.push_back(rd_delay);
				repeat(tr.len)
				begin
					rd_delay = $urandom_range(max_rdata_delay, min_rdata_delay);
					tr.data_delay.push_back(rd_delay);
				end
			end
			else
			begin
				int delay = rd_delay/(tr.len+1);
				tr.data_delay.push_back(rd_delay - tr.len*delay); // initial delay
				repeat(tr.len)
					tr.data_delay.push_back(delay);
			end
		end
	endfunction : set_read_trans_delays

	// High-level flow (one iteration of `forever`):
	//   1. Block on response_req_port until the monitor hands us a request.
	//   2. start_item(req) on this sequence.
	//   3. If the monitor flagged the request as malformed -> SLVERR, no
	//      memory side-effects, finish_item, restart.
	//   4. Otherwise, call get_response_code() and fill in either the read
	//      data (populate_data_from_mem + set_read_trans_delays) or the
	//      write bookkeeping (bresp_delay; mem update happens after BRESP,
	//      gated by a reset-aware fork so it doesn't leak across mid-test reset).
	//   5. finish_item(req) -- this must be reached in ZERO simulation time
	//      from the start_item above. Do not insert delays here.
	virtual task body();
		forever
		begin
			p_sequencer.response_req_port.get(req);
			start_item(req);

			// monitor_error is set by the monitor on malformed *requests* (bad burst/size,
			// 4K cross, reserved burst, bad WSTRB, xLAST/AWLEN mismatch) -> respond SLVERR.
			// (Response-construction problems are caught separately by the slave driver's
			// check_trans_validity fatal.)
			if(req.monitor_error)
			begin
				req.resp = OVIP_AXI_RESP_SLVERR;
				if(req.tr_type == OVIP_AXI_READ_TRANS)
					repeat(req.len+1) req.data_beats.push_back(0);
				else
					req.bresp_delay = 0;
				finish_item(req);
				continue;
			end

			req.resp = get_response_code(req);

			if(req.tr_type == OVIP_AXI_READ_TRANS)
			begin
				populate_data_from_mem(req);
				set_read_trans_delays(req);
			end
			else
			begin
				req.bresp_delay = get_bresp_delay();
				if(wr_mem_update_on_bresp)
				begin
					// Defer the memory update until BRESP is sampled. Race the
					// wait with reset: on mid-test reset the driver is killed
					// before bresp, so transaction_finished never fires --
					// without the reset race these watcher threads leak forever.
					fork
						begin
							ovip_axi_trans _req = req;
							fork
								wait(_req.transaction_finished);
								@(p_sequencer.vif.monitor_cb iff !p_sequencer.vif.monitor_cb.aresetn);
							join_any
							disable fork;
							if(_req.transaction_finished)
								write_transaction_to_mem(_req);
						end
					join_none
				end
				else
				begin
					// Immediate commit. write_transaction_to_mem checks tr.resp
					// and skips the update on SLVERR/DECERR, so it's safe to
					// call before BRESP fires.
					write_transaction_to_mem(req);
				end
			end

			finish_item(req);
		end
	endtask : body
endclass : ovip_axi_base_slave_sequence


