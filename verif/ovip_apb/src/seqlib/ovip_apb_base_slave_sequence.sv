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
//   - body() -- full override if none of the above fits.
//
// Preconditions:
//   - The `mem` handle is OPTIONAL. If left null, a subclass MUST override
//     populate_data_from_mem and write_transaction_to_mem (otherwise the
//     base fatals with a clear message at the first request).
//   - cfg.data_width must not exceed the memory word size (one transfer
//     always fits inside one memory word; the APB data bus caps at 4 bytes
//     and ovip_mem's default word is 4 bytes, so the default just works).
class ovip_apb_base_slave_sequence extends uvm_sequence#(ovip_apb_trans);

	// Wait-state range consumed per transfer by get_num_wait_states().
	// Initialized from cfg's defaults at pre_body; override the knobs (or the
	// hook) before start() for directed control.
	rand int unsigned min_ws;
	rand int unsigned max_ws;
	protected bit ws_knobs_set = 0;

	// Handle to the backing memory for read fill / write capture. OPTIONAL --
	// see the class comment.
	ovip_mem mem;

	protected int memory_word_size;

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
		ws_knobs_set = 1;
	endfunction : set_wait_states


	virtual task pre_body();
		if(!ws_knobs_set)
		begin
			min_ws = p_sequencer.cfg.default_min_wait_states;
			max_ws = p_sequencer.cfg.default_max_wait_states;
		end
		if(mem != null)
		begin
			memory_word_size = mem.get_word_size();
			if(p_sequencer.cfg.data_width > memory_word_size)
				`uvm_fatal("OVIP_APB/SLAVE_SEQ",
					$sformatf("cfg.data_width (%0dB) exceeds the memory word size (%0dB) -- one APB transfer must fit inside one memory word.",
						p_sequencer.cfg.data_width, memory_word_size))
		end
	endtask : pre_body


	// Per-transfer response code. Override to inject SLVERR; the base always
	// returns 0. The base body() still forces SLVERR when `req.monitor_error`
	// is set (malformed request), regardless of what this hook returns.
	virtual function bit get_slverr(ovip_apb_trans req);
		return 0;
	endfunction : get_slverr


	virtual function int unsigned get_num_wait_states(ovip_apb_trans req);
		return $urandom_range(max_ws, min_ws);
	endfunction : get_num_wait_states


	// Address decomposition shared by the read/write helpers: the transfer's
	// bus-aligned address is split into the containing memory word and the
	// byte lane offset of the transfer inside that word. Unaligned PADDR is
	// UNPREDICTABLE per spec section 2.1.1 -- the base aligns down and warns.
	protected virtual function void decompose_addr(ovip_apb_trans req,
	                                               output longint unsigned word_addr,
	                                               output int unsigned lane);
		int unsigned dw = p_sequencer.cfg.data_width;
		ovip_apb_addr_t bus_addr = (req.addr / dw) * dw;
		if(bus_addr != req.addr)
			`uvm_warning("OVIP_APB/SLAVE_SEQ",
				$sformatf("Unaligned PADDR 0x%0h for a %0d-byte data bus -- result is UNPREDICTABLE per spec section 2.1.1; aligning down to 0x%0h.",
					req.addr, dw, bus_addr))
		word_addr = (longint'(bus_addr) / memory_word_size) * memory_word_size;
		lane      = bus_addr % memory_word_size;
	endfunction : decompose_addr


	virtual function void write_transaction_to_mem(ovip_apb_trans req);
		longint unsigned word_addr;
		int unsigned lane;
		if(mem == null)
			`uvm_fatal("OVIP_APB/SLAVE_SEQ",
				"write_transaction_to_mem called with `mem == null`. Either assign `mem` before start(), or override write_transaction_to_mem in your subclass.")
		decompose_addr(req, word_addr, lane);
		mem.write(word_addr, req.wdata << (lane * 8), req.strb << lane);
	endfunction : write_transaction_to_mem


	virtual function void populate_data_from_mem(ovip_apb_trans req);
		longint unsigned word_addr;
		int unsigned lane;
		if(mem == null)
			`uvm_fatal("OVIP_APB/SLAVE_SEQ",
				"populate_data_from_mem called with `mem == null`. Either assign `mem` before start(), or override populate_data_from_mem in your subclass.")
		decompose_addr(req, word_addr, lane);
		req.rdata = (mem.read(word_addr) >> (lane * 8))
		            & ((ovip_apb_data_t'(1) << p_sequencer.cfg.data_width*8) - 1);
	endfunction : populate_data_from_mem


	// High-level flow (one iteration of `forever`):
	//   1. Block on response_req_port until the monitor hands us a request
	//      (forwarded on the SETUP cycle).
	//   2. start_item(req), fill in slverr / num_wait_states / rdata, apply
	//      the write to memory (skipped on SLVERR), finish_item(req).
	//   3. finish_item must be reached in ZERO simulation time -- the slave
	//      driver is blocked on get_next_item at the SETUP edge.
	virtual task body();
		forever
		begin
			p_sequencer.response_req_port.get(req);
			start_item(req);

			req.slverr          = req.monitor_error ? 1'b1 : get_slverr(req);
			req.num_wait_states = get_num_wait_states(req);

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
