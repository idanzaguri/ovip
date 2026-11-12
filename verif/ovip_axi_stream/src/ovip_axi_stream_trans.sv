`ifndef OVIP_AXI_STREAM_TRANS__SV
`define OVIP_AXI_STREAM_TRANS__SV

// One ovip_axi_stream_trans represents one AXI-Stream *packet* (a run of
// transfers between two consecutive TLAST assertions, or a single transfer if
// TLAST is asserted on every beat). The per-beat fields are queues whose
// indices are the beat number; TLAST is implicit -- it is asserted on the
// last entry of `data_beats` and deasserted on every earlier entry.
class ovip_axi_stream_trans extends uvm_sequence_item;

	// ------------------------------------------------------------------------
	// Interface-signal payload (per-beat queues, packet-scope scalars).
	// ------------------------------------------------------------------------

	// Per-beat TDATA / byte qualifiers / per-byte TUSER. The wire-level slice
	// of each entry that is actually live is the bottom `bus_width` bytes
	// (and, for TUSER, the bottom `bus_width * tuser_bits_per_byte` bits).
	rand ovip_axi_stream_data_t data_beats[$];
	rand ovip_axi_stream_keep_t keep_beats[$];
	rand ovip_axi_stream_strb_t strb_beats[$];
	rand ovip_axi_stream_user_t user_beats[$];

	// Packet-scope identifiers. Spec section 2.6: TID and TDEST must be stable
	// across every transfer of a packet, so they live at the packet (trans)
	// scope here rather than per-beat.
	rand ovip_axi_stream_id_t   id;
	rand ovip_axi_stream_dest_t dest;

	// AXI5-Stream wake-up signal. The transmitter is permitted to drive
	// TWAKEUP before TVALID; once both go HIGH, TWAKEUP must remain asserted
	// until TREADY (spec section 2.3).
	rand bit wakeup;

	// ------------------------------------------------------------------------
	// Driver/monitor state (not part of the wire payload).
	// ------------------------------------------------------------------------

	bit transaction_finished;
	bit got_last_beat;
	bit monitor_error;
	int burst_index;

	// Snapshot of the agent's bus width in bytes (= cfg.tdata_width). Only
	// the monitor fills it, from cfg, so per-beat decoders can iterate only
	// over the live byte lanes. The drivers do not read or set it.
	int bus_width;

	// Snapshot of the per-byte TUSER size (= cfg.tuser_bits_per_byte). Only
	// the monitor fills it. Used by get_tuser_for_byte().
	int tuser_bits_per_byte;

	// Timestamps, filled by the monitor from $realtime. tvalid_assert_time
	// and first_beat_time are both the time of the first handshake (TVALID
	// and TREADY HIGH) of the packet, not of the TVALID rise. last_beat_time
	// is the time of the last handshake of the packet.
	realtime tvalid_assert_time;
	realtime first_beat_time;
	realtime last_beat_time;

	// ------------------------------------------------------------------------
	// Timing knobs (rand, soft-bounded).
	// ------------------------------------------------------------------------

	// Per-beat gap, in clocks, inserted AFTER each beat (the entry for the
	// last beat is unused). When non-empty this is authoritative; the random
	// min/max fallback applies to any beat not covered.
	rand int unsigned delay_between_beats[$];
	rand int unsigned min_delay_between_beats;
	rand int unsigned max_delay_between_beats;

	// Gap, in clocks, the driver inserts after this transaction before
	// fetching the next item.
	rand int unsigned delay_until_next_trans;

	// ------------------------------------------------------------------------
	// Constraints.
	// ------------------------------------------------------------------------

	constraint c_solve_order {
		solve data_beats before keep_beats;
		solve data_beats before strb_beats;
		solve data_beats before user_beats;
		solve data_beats before delay_between_beats;
	}

	// At least one beat per packet (a zero-beat trans makes no wire-level
	// sense). All per-beat queues track data_beats in size.
	constraint c_beat_count_consistency {
		soft data_beats.size() inside {[1:64]};
		soft keep_beats.size() == data_beats.size();
		soft strb_beats.size() == data_beats.size();
		soft user_beats.size() == data_beats.size();
		soft delay_between_beats.size() == data_beats.size();
	}

	// No TSTRB bit is set where the TKEEP bit of the same beat is clear: TKEEP
	// LOW with TSTRB HIGH is the reserved combination (spec section 2.5.3,
	// Table 2-3).
	constraint c_no_reserved_byte_qualifier {
		foreach(strb_beats[i])
			if(i < keep_beats.size())
				(strb_beats[i] & ~keep_beats[i]) == 0;
	}

	// Non-negative timing knobs (the driver counts them down with `repeat`).
	constraint c_delays_non_negative {
		min_delay_between_beats <= max_delay_between_beats;
		foreach(delay_between_beats[i]) delay_between_beats[i] >= 0;
		delay_until_next_trans >= 0;
	}

	// Soft caps on the default random distribution.
	constraint c_reasonable_delays_limit {
		soft max_delay_between_beats <= `OVIP_AXI_STREAM_DELAY_BETWEEN_BEATS_MAX;
		soft delay_until_next_trans  <= `OVIP_AXI_STREAM_DELAY_UNTIL_NEXT_TRANS_MAX;
		foreach(delay_between_beats[i])
			soft delay_between_beats[i] <= `OVIP_AXI_STREAM_DELAY_BETWEEN_BEATS_MAX;
	}

	`uvm_object_utils(ovip_axi_stream_trans)

	function new(string name = "ovip_axi_stream_trans");
		super.new(name);
	endfunction : new


	// ------------------------------------------------------------------------
	// Helpers.
	// ------------------------------------------------------------------------

	// Returns just the *valid* bytes of the packet as a flat byte stream,
	// filtering out null bytes (TKEEP = 0) and, by default, position bytes
	// (TKEEP = 1, TSTRB = 0). Set `include_position_bytes` to keep them.
	//
	// Defaults when the per-byte qualifier queues are absent follow the spec:
	//   - TKEEP absent  -> every byte is transported (keep_beats[*][b] == 1)
	//   - TSTRB absent  -> data/position == TKEEP (spec section 3.1.2)
	//
	// `bus_width` (in bytes) must be set before calling. The monitor sets it
	// from cfg.tdata_width on the packets it publishes. On an item that a
	// sequence builds, the sequence sets it.
	virtual function ovip_bytestream get_data_bytes(bit include_position_bytes = 0);
		ovip_bytestream result;
		if(bus_width == 0)
			`uvm_warning("AXIS_TRANS/GET_DATA_BYTES", "bus_width=0; returning empty bytestream. Set bus_width before calling get_data_bytes().")
		foreach(data_beats[i])
		begin
			for(int b = 0; b < bus_width; b++)
			begin
				bit is_kept = (keep_beats.size() > i) ? keep_beats[i][b] : 1'b1;
				bit is_data = (strb_beats.size() > i) ? strb_beats[i][b] : is_kept;
				if(!is_kept) continue;                              // null byte
				if(!is_data && !include_position_bytes) continue;   // position byte
				result.push_back(data_beats[i][b*8 +: 8]);
			end
		end
		return result;
	endfunction : get_data_bytes


	// Returns the per-byte TUSER slice for byte `byte_idx` of beat `beat_idx`.
	// Per spec section 2.9: TUSER[(x*m + m-1):(x*m)] for byte x with m bits per
	// byte. Returns 0 when TUSER is absent (out-of-range beat_idx or
	// tuser_bits_per_byte == 0).
	virtual function ovip_axi_stream_user_t get_tuser_for_byte(int beat_idx, int byte_idx);
		ovip_axi_stream_user_t result;
		if(beat_idx >= user_beats.size() || tuser_bits_per_byte == 0) return 0;
		for(int b = 0; b < tuser_bits_per_byte; b++)
			result[b] = user_beats[beat_idx][byte_idx * tuser_bits_per_byte + b];
		return result;
	endfunction : get_tuser_for_byte


	// ------------------------------------------------------------------------
	// UVM hooks.
	// ------------------------------------------------------------------------

	virtual function void do_copy(uvm_object rhs);
		ovip_axi_stream_trans tr;
		if(!$cast(tr, rhs)) `uvm_fatal("CAST_FAILED", "ovip_axi_stream_trans::do_copy: rhs is not an ovip_axi_stream_trans")
		super.do_copy(rhs);
		data_beats              = tr.data_beats;
		keep_beats              = tr.keep_beats;
		strb_beats              = tr.strb_beats;
		user_beats              = tr.user_beats;
		id                      = tr.id;
		dest                    = tr.dest;
		wakeup                  = tr.wakeup;
		transaction_finished    = tr.transaction_finished;
		got_last_beat           = tr.got_last_beat;
		monitor_error           = tr.monitor_error;
		burst_index             = tr.burst_index;
		bus_width               = tr.bus_width;
		tuser_bits_per_byte     = tr.tuser_bits_per_byte;
		tvalid_assert_time      = tr.tvalid_assert_time;
		first_beat_time         = tr.first_beat_time;
		last_beat_time          = tr.last_beat_time;
		delay_between_beats     = tr.delay_between_beats;
		min_delay_between_beats = tr.min_delay_between_beats;
		max_delay_between_beats = tr.max_delay_between_beats;
		delay_until_next_trans  = tr.delay_until_next_trans;
	endfunction : do_copy


	// Compare two trans on the interface-signal fields only -- internal
	// bookkeeping (burst_index, transaction_finished, ...), observability
	// timestamps, and timing knobs are intentionally ignored, since two
	// transactions can be functionally identical on the wire while differing
	// in any of those.
	//
	// keep_beats, strb_beats and user_beats are compared only when both sides
	// filled them. The monitor fills each of them only when its signal is on
	// the interface, and a sequence may fill a queue for a signal that is
	// absent or leave out one that is present, so a queue that is empty on one
	// side says nothing. `wakeup` is a bit and has no empty value: the monitor
	// leaves it 0 without TWAKEUP, so leave it 0 in an expected item then.
	virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
		ovip_axi_stream_trans tr;
		if(!$cast(tr, rhs)) return 0;
		return super.do_compare(rhs, comparer)
			&& data_beats == tr.data_beats
			&& (keep_beats.size() == 0 || tr.keep_beats.size() == 0 || keep_beats == tr.keep_beats)
			&& (strb_beats.size() == 0 || tr.strb_beats.size() == 0 || strb_beats == tr.strb_beats)
			&& (user_beats.size() == 0 || tr.user_beats.size() == 0 || user_beats == tr.user_beats)
			&& id         == tr.id
			&& dest       == tr.dest
			&& wakeup     == tr.wakeup;
	endfunction : do_compare


	// Per-field diff of the interface-signal mismatches between `this` (read
	// as "expected") and `rhs` (read as "actual"). Empty string when the two
	// are equal under do_compare's policy. Scoreboards typically call this
	// after `compare()` returns 0 and wrap the result in their own uvm_error.
	virtual function string diff(ovip_axi_stream_trans rhs);
		string s = "";
		if(id         != rhs.id        ) s = {s, $sformatf("  id:         expected=0x%0h   actual=0x%0h\n",  id,        rhs.id)};
		if(dest       != rhs.dest      ) s = {s, $sformatf("  dest:       expected=0x%0h   actual=0x%0h\n",  dest,      rhs.dest)};
		if(wakeup     != rhs.wakeup    ) s = {s, $sformatf("  wakeup:     expected=%0b     actual=%0b\n",    wakeup,    rhs.wakeup)};
		if(data_beats != rhs.data_beats) s = {s, $sformatf("  data_beats: expected=%p      actual=%p\n",     data_beats, rhs.data_beats)};
		if(keep_beats.size() && rhs.keep_beats.size() && keep_beats != rhs.keep_beats)
		                                 s = {s, $sformatf("  keep_beats: expected=%p      actual=%p\n",     keep_beats, rhs.keep_beats)};
		if(strb_beats.size() && rhs.strb_beats.size() && strb_beats != rhs.strb_beats)
		                                 s = {s, $sformatf("  strb_beats: expected=%p      actual=%p\n",     strb_beats, rhs.strb_beats)};
		if(user_beats.size() && rhs.user_beats.size() && user_beats != rhs.user_beats)
		                                 s = {s, $sformatf("  user_beats: expected=%p      actual=%p\n",     user_beats, rhs.user_beats)};
		return s;
	endfunction : diff


	virtual function string convert2string();
		return $sformatf("(%s) AXIS packet, ID=0x%0h, DEST=0x%0h, %0d beats",
			get_name(), id, dest, data_beats.size());
	endfunction : convert2string

endclass : ovip_axi_stream_trans

`endif
