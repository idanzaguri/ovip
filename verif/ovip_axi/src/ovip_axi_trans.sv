`ifndef OVIP_AXI_TRANS__SV
`define OVIP_AXI_TRANS__SV

class ovip_axi_trans extends uvm_sequence_item;

	bit monitor_error;
	bit data_phase_started;

	rand ovip_axi_addr_t addr;                      // Address of the AXI transaction
	rand ovip_axi_id_t id;                          // ID of the AXI transaction
	rand ovip_axi_transaction_type_t tr_type;       // Type of AXI transaction (e.g., read, write)
	rand ovip_axi_resp_t resp;                      // Response of the AXI transaction (e.g., OKAY, ERROR)
	rand ovip_axi_data_t data_beats[$];             // Data beats of the AXI transaction
	rand ovip_axi_strb_t strb_beats[$];             // Strobe beats of the AXI transaction
	rand bit [7:0] len;                             // Length of the AXI transaction
	rand ovip_axi_size_t size;                      // Size of each beat in the AXI transaction
	rand ovip_axi_burst_t burst;                    // Burst type of the AXI transaction
	rand ovip_axi_user_t awuser;                    // User field for address phase
	rand ovip_axi_user_t wuser;                     // User field for write data phase
	rand ovip_axi_user_t buser;                     // User field for write response phase
	rand ovip_axi_user_t aruser;                    // User field for read address phase
	rand ovip_axi_user_t ruser;                     // User field for read data phase

	bit valid_address_phase;                   // Flag indicating whether the address phase of the transaction is valid
	bit got_last_beat;                         // Flag indicating whether the last beat of the transaction has been received
	bit transaction_finished;                  // Flag indicating whether the entire transaction has finished
	uvm_event#(uvm_object) completed_ev;       // Triggered by the monitor when the transaction completes (used by the timeout watcher)
	int burst_index;                           // Index of the current burst for the driver
	bit is_narrow_transfer;
	ovip_axi_bus_width_t bus_width;            // Width of the AXI bus (driver/monitor will set this field according to port configuration)
	int transfer_starting_byte_lane[];         // Per-beat starting byte lane (computed by calculate_transfer_starting_byte_lane)

	rand bit axlock;
	rand bit [3:0] axcache;
	rand bit [2:0] axprot;
	rand bit [3:0] axqos;
	rand bit [3:0] axregion;

	// When set, this flag allows for transactions that may not fully align with the specification.
	// It disables some checks performed before driving the transaction.
	bit trust_me_i_am_an_engineer;

	// All times are captured at sampling (i.e., valid && ready).
	time addr_phase_time;
	time data_phase_begin_time;
	time data_phase_time;
	time resp_phase_time;


	//
	// Timing
	//
	rand int data_delay[$];                    // Array to store delays between read/write data beats for slave/master agent
	rand int bresp_delay;                      // Delay for the write response phase
	rand int addr_phase_delay;                 // Delay for the address phase
	rand int delay_until_next_addr;            // Delay until the next address phase
	rand int delay_until_next_data;            // Delay until the next data phase


	// Event indicating the start of data transmission for the driver. Options include:
	//   - OVIP_AXI_DATA_START_EV_ADDR_DRIVEN: Data phase starts after address phase is driven.
	//   - OVIP_AXI_DATA_START_EV_ADDR_SAMPLED: Data phase starts after address phase is sampled.
	//   - OVIP_AXI_DATA_START_EV_BEFORE_ADDR: Data phase starts before address phase is driven.
	// The driver uses this event to determine when to add delay before driving the data phase.
	rand ovip_axi_data_start_event_t data_start_event;


	// Ready patterns are NOT rand: the struct holds a queue, which is awkward to
	// randomize portably; and an empty cycles[$] is a deliberate "don't override
	// the channel's current pattern" signal that conflicts with the natural
	// randomize() default. Set explicitly if you want to override the channel.
	ovip_axi_ready_pattern_t arready_pattern;
	ovip_axi_ready_pattern_t awready_pattern;
	ovip_axi_ready_pattern_t wready_pattern;
	ovip_axi_ready_pattern_t rready_pattern;
	ovip_axi_ready_pattern_t bready_pattern;

	// -----------------------------------------------------------------------
	// Constraints
	// -----------------------------------------------------------------------

	// Help the solver: pick the discriminators first, then derive sizes.
	constraint c_solve_order {
		solve tr_type before len;
		solve burst   before len;
		solve tr_type before data_beats;
		solve tr_type before strb_beats;
		solve len     before data_beats;
		solve len     before strb_beats;
	}

	// VIP-supported burst values.
	constraint c_burst_supported {
		burst != OVIP_AXI_BURST_RES;
	}

	// Spec: FIXED bursts carry at most 16 beats.
	constraint c_fixed_len_limit {
		burst == OVIP_AXI_BURST_FIXED -> len < 16;
	}

	// Spec: WRAP bursts carry exactly 2, 4, 8, or 16 beats (len+1).
	constraint c_wrap_len {
		burst == OVIP_AXI_BURST_WRAP -> len inside {1, 3, 7, 15};
	}

	// Spec: WRAP bursts require the start address to be aligned to burst_size.
	constraint c_wrap_addr_aligned {
		burst == OVIP_AXI_BURST_WRAP -> (addr & ((ovip_axi_addr_t'(1) << size) - 1)) == 0;
	}

	// data_beats / strb_beats sizes track the channel they belong to:
	//   writes : exactly len+1 entries (master populates).
	//   reads  : empty at submission time (slave populates).
	constraint c_data_beats_size {
		tr_type == OVIP_AXI_WRITE_TRANS -> data_beats.size() == len + 1;
		tr_type == OVIP_AXI_READ_TRANS  -> data_beats.size() == 0;
	}
	constraint c_strb_beats_size {
		tr_type == OVIP_AXI_WRITE_TRANS -> strb_beats.size() == len + 1;
		tr_type == OVIP_AXI_READ_TRANS  -> strb_beats.size() == 0;
	}

	// Delays cannot be negative (the drivers count them down with `repeat`).
	constraint c_delays_non_negative {
		bresp_delay           >= 0;
		addr_phase_delay      >= 0;
		delay_until_next_addr >= 0;
		delay_until_next_data >= 0;
		foreach(data_delay[i]) data_delay[i] >= 0;
	}


	// Bounded-random delay defaults: a bare randomize() picks delays in
	// [0, max] for each kind of delay; per-call `with { ... }` overrides any
	// of them. `len`, `size`, and `addr` are deliberately NOT capped --
	// users always pin those to their test's needs.
	constraint c_reasonable_delays_limit {
		soft bresp_delay           <= `OVIP_AXI_TRANS_WR_RESP_DELAY_MAX;
		soft addr_phase_delay      <= `OVIP_AXI_TRANS_ADDR_PHASE_DELAY_MAX;
		soft delay_until_next_addr <= `OVIP_AXI_TRANS_NEXT_ADDR_DELAY_MAX;
		soft delay_until_next_data <= `OVIP_AXI_TRANS_NEXT_DATA_DELAY_MAX;
		soft data_delay.size()     == len + 1;   // one delay per beat
		foreach(data_delay[i]) {
			tr_type == OVIP_AXI_READ_TRANS  -> soft data_delay[i] <= `OVIP_AXI_TRANS_RD_DATA_DELAY_MAX;
			tr_type == OVIP_AXI_WRITE_TRANS -> soft data_delay[i] <= `OVIP_AXI_TRANS_WR_DATA_DELAY_MAX;
		}
	}

	//`uvm_declare_p_sequencer(ovip_axi_base_sequencer)

	`uvm_object_utils(ovip_axi_trans)

	function new(string name = "ovip_axi_trans");
		super.new(name);
		init_state_variables();
		completed_ev = new("completed_ev");
	endfunction : new

	// Reset the driver-facing status/metadata fields to their defaults.
	virtual function void init_state_variables();
		burst_index = 0;
		got_last_beat = 0;
		valid_address_phase = 0;
		transaction_finished = 0;
		is_narrow_transfer = 0;
		data_phase_started = 0;
		monitor_error = 0;
	endfunction : init_state_variables

	virtual function void do_copy(uvm_object rhs);
		ovip_axi_trans tr;
		if(!$cast(tr, rhs)) `uvm_fatal("CAST_FAILED", "ovip_axi_trans::do_copy: rhs is not an ovip_axi_trans")
		super.do_copy(rhs);
		addr = tr.addr;
		id = tr.id;

		tr_type = tr.tr_type;
		resp = tr.resp;

		data_beats = tr.data_beats;
		strb_beats = tr.strb_beats;

		len = tr.len;
		size = tr.size;
		burst = tr.burst;
		awuser = tr.awuser;
		wuser = tr.wuser;
		buser = tr.buser;
		aruser = tr.aruser;
		ruser = tr.ruser;

		axlock = tr.axlock;
		axcache = tr.axcache;
		axprot = tr.axprot;
		axqos = tr.axqos;
		axregion = tr.axregion;

		valid_address_phase = tr.valid_address_phase;
		got_last_beat = tr.got_last_beat;
		transaction_finished = tr.transaction_finished;
		is_narrow_transfer = tr.is_narrow_transfer;
		monitor_error = tr.monitor_error;
		data_phase_started = tr.data_phase_started;

		burst_index = tr.burst_index;

		bus_width = tr.bus_width;

		trust_me_i_am_an_engineer = tr.trust_me_i_am_an_engineer;

		data_delay = tr.data_delay;
		bresp_delay = tr.bresp_delay;
		addr_phase_delay = tr.addr_phase_delay;
		data_start_event = tr.data_start_event;
		delay_until_next_addr = tr.delay_until_next_addr;
		delay_until_next_data = tr.delay_until_next_data;

		addr_phase_time       = tr.addr_phase_time;
		data_phase_begin_time = tr.data_phase_begin_time;
		data_phase_time       = tr.data_phase_time;
		resp_phase_time       = tr.resp_phase_time;

		//transfer_starting_byte_lane = tr.transfer_starting_byte_lane;

		arready_pattern = tr.arready_pattern;
		awready_pattern = tr.awready_pattern;
		wready_pattern  = tr.wready_pattern;
		rready_pattern  = tr.rready_pattern;
		bready_pattern  = tr.bready_pattern;

	endfunction : do_copy


	// Compare two ovip_axi_trans. Only fields that map to interface signals are
	// checked -- internal bookkeeping (burst_index, transaction_finished, ...),
	// observability timestamps, and slave-/master-side timing knobs (data_delay,
	// bresp_delay, ready patterns, ...) are intentionally ignored, since two
	// transactions can be functionally identical on the wire while differing in
	// any of those.
	virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
		ovip_axi_trans tr;
		if(!$cast(tr, rhs)) return 0;
		return super.do_compare(rhs, comparer)
			&& addr       == tr.addr
			&& id         == tr.id
			&& tr_type    == tr.tr_type
			&& resp       == tr.resp
			&& data_beats == tr.data_beats
			&& strb_beats == tr.strb_beats
			&& len        == tr.len
			&& size       == tr.size
			&& burst      == tr.burst
			&& awuser     == tr.awuser
			&& wuser      == tr.wuser
			&& buser      == tr.buser
			&& aruser     == tr.aruser
			&& ruser      == tr.ruser
			&& axlock     == tr.axlock
			&& axcache    == tr.axcache
			&& axprot     == tr.axprot
			&& axqos      == tr.axqos
			&& axregion   == tr.axregion;
	endfunction : do_compare


	// Per-field diff of the interface-signal mismatches between `this` (read as
	// "expected") and `rhs` (read as "actual"). Returns an empty string when
	// the two are equal under do_compare's policy. The scoreboard typically
	// calls this only after `compare()` returns 0 and wraps the result in its
	// own uvm_error. Same field policy as do_compare: internal bookkeeping,
	// observability timestamps, and timing knobs are intentionally skipped.
	virtual function string diff(ovip_axi_trans rhs);
		string s = "";
		if(addr       != rhs.addr      ) s = {s, $sformatf("  addr:       expected=0x%0h    actual=0x%0h\n",   addr,            rhs.addr)};
		if(id         != rhs.id        ) s = {s, $sformatf("  id:         expected=0x%0h    actual=0x%0h\n",   id,              rhs.id)};
		if(tr_type    != rhs.tr_type   ) s = {s, $sformatf("  tr_type:    expected=%s       actual=%s\n",      tr_type.name(),  rhs.tr_type.name())};
		if(resp       != rhs.resp      ) s = {s, $sformatf("  resp:       expected=%s       actual=%s\n",      resp.name(),     rhs.resp.name())};
		if(len        != rhs.len       ) s = {s, $sformatf("  len:        expected=%0d      actual=%0d\n",     len,             rhs.len)};
		if(size       != rhs.size      ) s = {s, $sformatf("  size:       expected=%s       actual=%s\n",      size.name(),     rhs.size.name())};
		if(burst      != rhs.burst     ) s = {s, $sformatf("  burst:      expected=%s       actual=%s\n",      burst.name(),    rhs.burst.name())};
		if(awuser     != rhs.awuser    ) s = {s, $sformatf("  awuser:     expected=0x%0h    actual=0x%0h\n",   awuser,          rhs.awuser)};
		if(wuser      != rhs.wuser     ) s = {s, $sformatf("  wuser:      expected=0x%0h    actual=0x%0h\n",   wuser,           rhs.wuser)};
		if(buser      != rhs.buser     ) s = {s, $sformatf("  buser:      expected=0x%0h    actual=0x%0h\n",   buser,           rhs.buser)};
		if(aruser     != rhs.aruser    ) s = {s, $sformatf("  aruser:     expected=0x%0h    actual=0x%0h\n",   aruser,          rhs.aruser)};
		if(ruser      != rhs.ruser     ) s = {s, $sformatf("  ruser:      expected=0x%0h    actual=0x%0h\n",   ruser,           rhs.ruser)};
		if(axlock     != rhs.axlock    ) s = {s, $sformatf("  axlock:     expected=%0b      actual=%0b\n",     axlock,          rhs.axlock)};
		if(axcache    != rhs.axcache   ) s = {s, $sformatf("  axcache:    expected=0x%0h    actual=0x%0h\n",   axcache,         rhs.axcache)};
		if(axprot     != rhs.axprot    ) s = {s, $sformatf("  axprot:     expected=0x%0h    actual=0x%0h\n",   axprot,          rhs.axprot)};
		if(axqos      != rhs.axqos     ) s = {s, $sformatf("  axqos:      expected=0x%0h    actual=0x%0h\n",   axqos,           rhs.axqos)};
		if(axregion   != rhs.axregion  ) s = {s, $sformatf("  axregion:   expected=0x%0h    actual=0x%0h\n",   axregion,        rhs.axregion)};
		if(data_beats != rhs.data_beats) s = {s, $sformatf("  data_beats: expected=%p       actual=%p\n",      data_beats,      rhs.data_beats)};
		if(strb_beats != rhs.strb_beats) s = {s, $sformatf("  strb_beats: expected=%p       actual=%p\n",      strb_beats,      rhs.strb_beats)};
		return s;
	endfunction : diff


	virtual function string convert2string();
		return $sformatf("(%s) %s, ID=0x%0x, ADDR=0x%0x, SIZE=%s, LEN=%0d(+1)", get_name(), tr_type.name(), id, addr, size.name(), len);
	endfunction : convert2string

	function void calculate_transfer_starting_byte_lane();
		int byte_lane_offset;
		int burst_size = 1<<size;
		if(transfer_starting_byte_lane.size() != len + 1)
			transfer_starting_byte_lane = new[len+1];
		byte_lane_offset = (addr%bus_width) & ~(burst_size-1);

		transfer_starting_byte_lane[0] = byte_lane_offset;
		// Calculate the number of inactive byte lanes in the first transfer due to unalignment
		transfer_starting_byte_lane[0] += (addr % burst_size);

		is_narrow_transfer = (burst_size != int'(bus_width));
		// For a non-narrow transfer (burst_size == bus_width) every beat fills the whole
		// data bus starting at byte lane 0, so there are no per-beat lane offsets to compute.
		// Only narrow transfers (and the unaligned first beat) need the per-beat calculation below.
		if(!is_narrow_transfer) return;

		if(burst == OVIP_AXI_BURST_FIXED)
		begin
			for(int ii=1; ii<=len; ii++)
				transfer_starting_byte_lane[ii] = transfer_starting_byte_lane[0];
			return;
		end

		if(burst == OVIP_AXI_BURST_WRAP)
		begin
			// WRAP: each beat advances by burst_size and the address wraps at
			// `total_size = burst_size * (len+1)` (a power of 2 by spec).
			// `wrap_low` is the start of the wrap window; beat addresses stay
			// in [wrap_low, wrap_low + total_size).
			int total_size = burst_size * (len + 1);
			int wrap_low   = addr & ~(total_size - 1);
			for(int ii=1; ii<=len; ii++)
			begin
				int beat_addr = wrap_low + ((addr - wrap_low + ii*burst_size) % total_size);
				transfer_starting_byte_lane[ii] = beat_addr % bus_width;
			end
			return;
		end

		// INCR: each beat advances by burst_size and the lane wraps at bus_width.
		for(int ii=1; ii<=len; ii++)
		begin
			byte_lane_offset += burst_size;
			if(byte_lane_offset == bus_width) byte_lane_offset = 0;
			transfer_starting_byte_lane[ii] = byte_lane_offset;
		end

	endfunction

	// assuming real strb (not right justified!!!!)
	virtual function bit check_strb(int start_beat, int end_beat, ref string err_msg[$]);
		int burst_size = 1<<size;

		int transfer_size, first_byte_lane, last_byte_lane;
		ovip_axi_strb_t strb_mask;

		err_msg = {};

		// Creating a mask for active strobes. For FIXED burst type, there is no need to recalculate for each transfer since it's identical.
		if(burst == OVIP_AXI_BURST_FIXED)
		begin
			transfer_size   = burst_size - addr%burst_size;
			first_byte_lane = transfer_starting_byte_lane[0];
			last_byte_lane  = first_byte_lane + transfer_size - 1;
			strb_mask = ~(((1<<transfer_size)-1)<<first_byte_lane);
		end

		for(int ii=start_beat; ii<=end_beat; ii++)
		begin
			if(burst == OVIP_AXI_BURST_INCR)
			begin
				transfer_size   = (ii==0)? (burst_size-addr%burst_size) : burst_size;
				first_byte_lane = transfer_starting_byte_lane[ii];
				last_byte_lane  = first_byte_lane + transfer_size - 1;
				strb_mask = ~(((1<<transfer_size)-1)<<first_byte_lane);
			end

			if(burst == OVIP_AXI_BURST_WRAP)
			begin
				// WRAP requires addr aligned to burst_size, so every beat is a
				// full burst_size transfer (no partial first beat).
				transfer_size   = burst_size;
				first_byte_lane = transfer_starting_byte_lane[ii];
				last_byte_lane  = first_byte_lane + transfer_size - 1;
				strb_mask = ~(((1<<transfer_size)-1)<<first_byte_lane);
			end

			if(|(strb_beats[ii] & strb_mask))
			begin
				err_msg.push_back(
					$sformatf("invalid wstrb on beat %0d. Active byte lanes are [%0d:%0d] while wstrb=%0b",
						ii, last_byte_lane, first_byte_lane, strb_beats[ii])
				);
			end
		end

		return (err_msg.size() == 0);
	endfunction : check_strb


	// Reshape `src` into `dst` according to `dst`'s burst size and bus width.
	// `src` is the input transaction; `dst` is filled in by this function.
	//
	// Caveat: may produce an invalid or incomplete `dst` if the source can't be
	// fully represented in the target format -- e.g. a source with 256 8-byte
	// transfers won't fit into a transaction with a 4-byte burst size.
	static function void reshape_axi_transaction(
		ovip_axi_trans src,
		ovip_axi_trans dst
	);
		bit is_write_trans = (src.tr_type == OVIP_AXI_WRITE_TRANS); // Determine if the transaction is a write transaction

		int src_burst_size = 1 << src.size; // Source burst size in bytes
		int dst_burst_size = 1 << dst.size; // Destination burst size in bytes for conversion

		int src_byte_offset = src.addr % src.bus_width; // Calculate the byte offset within the source bus width
		int dst_byte_offset = src.addr % dst.bus_width; // Calculate the byte offset within the target bus width

		int dst_beat_index = 0; // Initialize the destination beat index

		if(src.burst != OVIP_AXI_BURST_INCR)
			`uvm_fatal_context("OVIP_AXI/MISSING_FEATURE", $sformatf("%s reshape_axi_transaction: Only INCR burst type is supported.",src.burst.name()), uvm_root::get())

		dst.data_beats = {}; // Initialize the destination data beats array
		dst.strb_beats = {}; // Initialize the destination strobe beats array

		// Iterate over each beat in the source transaction
		//for (int beat = 0; beat <= src.len; beat++) begin
		for (int beat = 0; beat < src.data_beats.size(); beat++) begin
			// Process each byte within the current beat
			do begin
				// Map the current byte from the source beat to the target data beat
				dst.data_beats[dst_beat_index][dst_byte_offset * 8 +: 8] = src.data_beats[beat][src_byte_offset * 8 +: 8];
				// Map the corresponding strobe bit if it is a write transaction
				if (is_write_trans) dst.strb_beats[dst_beat_index][dst_byte_offset] = src.strb_beats[beat][src_byte_offset];

				// Increment the target byte offset
				if (++dst_byte_offset % dst_burst_size == 0) begin
					// Check if the target byte offset reaches the target bus width
					if (dst_byte_offset == dst.bus_width)
						dst_byte_offset = 0; // Reset the target byte offset

					dst_beat_index++; // Move to the next destination beat
				end

				// Increment the source byte offset
				if (++src_byte_offset == src.bus_width)
					src_byte_offset = 0; // Reset the source byte offset

				// Continue until the end of the current source burst size
			end while (src_byte_offset % src_burst_size);
		end

	endfunction : reshape_axi_transaction

endclass : ovip_axi_trans
`endif
