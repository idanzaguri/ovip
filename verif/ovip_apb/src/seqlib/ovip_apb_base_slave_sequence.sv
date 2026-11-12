`ifndef OVIP_APB_BASE_SLAVE_SEQUENCE__SV
`define OVIP_APB_BASE_SLAVE_SEQUENCE__SV

// Canonical base for completer-side sequences. Provides:
//   - A `forever` body() that reads requests off `response_req_port`, fills
//     in the response, and hands it to the slave driver in ZERO simulation
//     time (the driver needs the item on the SETUP edge to support
//     zero-wait-state completion -- do not insert delays in the hooks).
//   - A memory-backed read/write loopback against an `ovip_mem` (set the
//     `mem` handle before `start()`). Writes commit immediately (APB has no
//     separate response channel to defer against); reads return the current
//     memory content. Writes with SLVERR responses skip the memory update.
//   - Auto-SLVERR on monitor-flagged malformed requests (see
//     `tr.monitor_error`).
//
// Extension points (virtual hooks -- override one, leave the rest to the base):
//   - get_slverr(req)          -- inject SLVERR (defaults to 0).
//   - get_num_wait_states(req) -- per-transfer PREADY stretching; defaults to
//                                 a fresh draw from [min_ws, max_ws].
//   - populate_data_from_mem(req) / write_transaction_to_mem(req) -- where
//     read data comes from / write data goes. Override both to model a
//     register slave instead of a memory.
//   - body() -- full override if none of the above fits. Call
//     apply_default_wait_states() first, as the base body() does.
//
// Preconditions:
//   - The `mem` handle is OPTIONAL. If left null, a subclass MUST override
//     populate_data_from_mem and write_transaction_to_mem (otherwise the
//     base fatals with a clear message at the first request).
class ovip_apb_base_slave_sequence extends uvm_sequence#(ovip_apb_trans);

	// Wait-state range consumed per transfer by get_num_wait_states(). For
	// directed control set the knobs before start(): assign them, randomize
	// the sequence, or call set_wait_states() (or override the hook). A knob
	// left at WS_FROM_CFG, its initial value, takes cfg's default
	// (default_min_wait_states, default_max_wait_states) when body() starts.
	localparam int unsigned WS_FROM_CFG = 32'hFFFF_FFFF;
	rand int unsigned min_ws = WS_FROM_CFG;
	rand int unsigned max_ws = WS_FROM_CFG;

	// Handle to the backing memory for read fill / write capture. OPTIONAL --
	// see the class comment.
	ovip_mem mem;

	// A transfer outside the memory's valid ranges (ovip_mem::add_valid_range)
	// is answered PSLVERR and never touches the memory: a read returns 0, a
	// write is not committed. Reported as SLAVE_SEQ/OUT_OF_RANGE unless this
	// is cleared, for a test that aims outside on purpose. With no valid
	// range set the check is off and every address is in range. An agent
	// with no PSLVERR (cfg.pslverr_en = 0) does the same and shows OKAY.
	bit report_out_of_range = 1;

	`uvm_declare_p_sequencer(ovip_apb_slave_sequencer)
	`uvm_object_utils(ovip_apb_base_slave_sequence)

	constraint c_default_ranges {
		soft min_ws <= `OVIP_APB_WAIT_STATES_MAX;
		soft max_ws inside {[min_ws:`OVIP_APB_WAIT_STATES_MAX]};
	}

	function new(string name = "ovip_apb_base_slave_sequence");
		super.new(name);
	endfunction : new


	// Explicitly pin the wait-state range (skips the cfg defaults).
	virtual function void set_wait_states(int unsigned min_val, int unsigned max_val);
		min_ws = min_val;
		max_ws = max_val;
	endfunction : set_wait_states


	// Gives cfg's default to a knob that nobody set. body() calls it first,
	// so it also runs in a sequence started with call_pre_post = 0, as the
	// uvm_do macros start one. pre_body() and get_num_wait_states() call it
	// too, for a subclass with a body() of its own.
	virtual function void apply_default_wait_states();
		if(min_ws == WS_FROM_CFG) min_ws = p_sequencer.cfg.default_min_wait_states;
		if(max_ws == WS_FROM_CFG) max_ws = p_sequencer.cfg.default_max_wait_states;
	endfunction : apply_default_wait_states


	virtual task pre_body();
		apply_default_wait_states();
	endtask : pre_body


	// Per-transfer response code. Override to inject SLVERR; the base always
	// returns 0. The base body() still forces SLVERR when `req.monitor_error`
	// is set (malformed request), regardless of what this hook returns.
	virtual function bit get_slverr(ovip_apb_trans req);
		return 0;
	endfunction : get_slverr


	virtual function int unsigned get_num_wait_states(ovip_apb_trans req);
		apply_default_wait_states();
		return $urandom_range(max_ws, min_ws);
	endfunction : get_num_wait_states


	// The transfer's address, aligned down to the data bus width, for the
	// read/write helpers. Unaligned PADDR is UNPREDICTABLE per spec section
	// 2.1.1: the base aligns down and warns.
	protected virtual function ovip_apb_addr_t bus_aligned_addr(ovip_apb_trans req);
		int unsigned dw = p_sequencer.cfg.data_width;
		ovip_apb_addr_t bus_addr = (req.addr / dw) * dw;
		if(bus_addr != req.addr)
			`uvm_warning("OVIP_APB/SLAVE_SEQ",
				$sformatf("Unaligned PADDR 0x%0h for a %0d-byte data bus -- result is UNPREDICTABLE per spec section 2.1.1; aligning down to 0x%0h.",
					req.addr, dw, bus_addr))
		return bus_addr;
	endfunction : bus_aligned_addr


	// The transfer's data bytes, at its bus-aligned address, against the
	// memory's valid ranges. 1 with no memory or no range set.
	virtual function bit request_in_range(ovip_apb_trans req);
		int unsigned dw = p_sequencer.cfg.data_width;
		ovip_apb_addr_t bus_addr = (req.addr / dw) * dw;
		if(mem == null || mem.num_valid_ranges() == 0) return 1;
		return mem.is_valid(bus_addr, dw);
	endfunction : request_in_range


	// The cfg.data_width bytes of the transfer, at its bus-aligned address:
	// the bytes that request_in_range checks. The byte enables are req.strb.
	virtual function void write_transaction_to_mem(ovip_apb_trans req);
		ovip_bytestream data;
		ovip_bitstream  byte_enable;
		if(mem == null)
			`uvm_fatal("OVIP_APB/SLAVE_SEQ",
				"write_transaction_to_mem called with `mem == null`. Either assign `mem` before start(), or override write_transaction_to_mem in your subclass.")
		for(int ii = 0; ii < p_sequencer.cfg.data_width; ii++)
		begin
			data.push_back(req.wdata[ii*8 +: 8]);
			byte_enable.push_back(req.strb[ii]);
		end
		mem.write_bytestream(bus_aligned_addr(req), data, byte_enable);
	endfunction : write_transaction_to_mem


	// The same bytes, read into req.rdata.
	virtual function void populate_data_from_mem(ovip_apb_trans req);
		ovip_bytestream data;
		if(mem == null)
			`uvm_fatal("OVIP_APB/SLAVE_SEQ",
				"populate_data_from_mem called with `mem == null`. Either assign `mem` before start(), or override populate_data_from_mem in your subclass.")
		data = mem.read_bytestream(bus_aligned_addr(req), p_sequencer.cfg.data_width);
		req.rdata = '0;
		foreach(data[ii]) req.rdata[ii*8 +: 8] = data[ii];
	endfunction : populate_data_from_mem


	// High-level flow (one iteration of `forever`):
	//   1. Block on response_req_port until the monitor hands us a request
	//      (forwarded on the SETUP cycle).
	//   2. start_item(req), fill in slverr / num_wait_states / rdata, apply
	//      the write to memory (skipped on SLVERR), finish_item(req).
	//   3. finish_item must be reached in ZERO simulation time -- the slave
	//      driver is blocked on get_next_item at the SETUP edge.
	virtual task body();
		apply_default_wait_states();
		forever
		begin
			p_sequencer.response_req_port.get(req);
			start_item(req);

			req.slverr          = req.monitor_error ? 1'b1 : get_slverr(req);
			req.num_wait_states = get_num_wait_states(req);

			// outside the memory's valid ranges: PSLVERR, the memory untouched
			if(!req.slverr && !request_in_range(req))
			begin
				string dir    = "read";
				string answer = "answering OKAY (this agent has no PSLVERR)";
				if(req.write)                  dir    = "write";
				if(p_sequencer.cfg.pslverr_en) answer = "answering PSLVERR";
				if(report_out_of_range)
					`uvm_error("SLAVE_SEQ/OUT_OF_RANGE", $sformatf("%s: %s at 0x%0h touches an address outside the memory's %0d valid range(s): %s, memory untouched",
						p_sequencer.get_full_name(), dir, req.addr, mem.num_valid_ranges(), answer))
				req.slverr = 1'b1;
			end

			if(req.write)
			begin
				if(!req.slverr)
					write_transaction_to_mem(req);
			end
			else
			begin
				if(!req.slverr)
					populate_data_from_mem(req);
				else
					req.rdata = '0;
			end

			finish_item(req);
		end
	endtask : body

endclass : ovip_apb_base_slave_sequence

`endif
