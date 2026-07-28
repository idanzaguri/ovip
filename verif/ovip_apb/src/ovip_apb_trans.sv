`ifndef OVIP_APB_TRANS__SV
`define OVIP_APB_TRANS__SV

// One ovip_apb_trans represents one APB transfer: a single SETUP cycle
// followed by one or more ACCESS cycles (extended by the completer holding
// PREADY LOW). APB is non-pipelined with exactly one transfer in flight, so
// there are no beat queues -- every field is a scalar.
//
// The same class is used on both sides of the bus:
//   - Requester sequences randomize the request fields (addr/write/wdata/
//     strb/prot) plus the requester timing knob (delay_until_next_trans);
//     the master driver fills rdata/slverr back in at completion so `send()`
//     doubles as a blocking read.
//   - Completer sequences receive a monitor-built request through the
//     response_req_port and fill in the response fields (rdata/slverr) plus
//     the completer timing knob (num_wait_states).
//   - The monitor builds its own instance per observed transfer, filling
//     everything including the observed num_wait_states and timestamps.
class ovip_apb_trans extends uvm_sequence_item;

	// ------------------------------------------------------------------------
	// Interface-signal payload.
	// ------------------------------------------------------------------------

	rand ovip_apb_addr_t addr;
	rand bit             write;
	rand ovip_apb_data_t wdata;
	rand ovip_apb_strb_t strb;
	rand ovip_apb_prot_t prot;

	// Response fields. Driven by the completer; sampled back into the request
	// object by the master driver so requester sequences see them after send().
	rand ovip_apb_data_t rdata;
	rand bit             slverr;

	// ------------------------------------------------------------------------
	// Timing knobs (rand, soft-bounded).
	// ------------------------------------------------------------------------

	// Completer: number of ACCESS cycles with PREADY LOW before completion.
	// Also filled by the monitor with the *observed* wait-state count.
	rand int unsigned num_wait_states;

	// Requester: idle cycles the master driver inserts after this transfer
	// before fetching the next item. 0 = back-to-back (IDLE is skipped and
	// the bus moves straight to the next SETUP when an item is ready).
	rand int unsigned delay_until_next_trans;

	// ------------------------------------------------------------------------
	// Driver/monitor state (not part of the wire payload).
	// ------------------------------------------------------------------------

	bit transaction_finished;
	bit monitor_error;

	// Snapshot of the agent's bus width in bytes (= cfg.data_width), filled
	// by the monitor / drivers from cfg so printers can show only live bytes.
	int bus_width;

	// Observability timestamps: SETUP-cycle sample time and completion
	// (PSEL && PENABLE && PREADY) sample time.
	time setup_time;
	time complete_time;

	// ------------------------------------------------------------------------
	// Constraints.
	// ------------------------------------------------------------------------

	// Spec section 3.2 (figure 3-3): PSTRB must not be active during a read
	// transfer.
	constraint c_read_no_strb {
		!write -> strb == 0;
	}

	// Soft caps on the default random distribution.
	constraint c_reasonable_delays_limit {
		soft num_wait_states        <= `OVIP_APB_WAIT_STATES_MAX;
		soft delay_until_next_trans <= `OVIP_APB_DELAY_UNTIL_NEXT_TRANS_MAX;
	}

	// Response fields default clean; completer sequences override.
	constraint c_default_response {
		soft slverr == 0;
	}

	`uvm_object_utils(ovip_apb_trans)

	function new(string name = "ovip_apb_trans");
		super.new(name);
	endfunction : new


	// ------------------------------------------------------------------------
	// UVM hooks.
	// ------------------------------------------------------------------------

	virtual function void do_copy(uvm_object rhs);
		ovip_apb_trans tr;
		if(!$cast(tr, rhs)) `uvm_fatal("CAST_FAILED", "ovip_apb_trans::do_copy: rhs is not an ovip_apb_trans")
		super.do_copy(rhs);
		addr                   = tr.addr;
		write                  = tr.write;
		wdata                  = tr.wdata;
		strb                   = tr.strb;
		prot                   = tr.prot;
		rdata                  = tr.rdata;
		slverr                 = tr.slverr;
		num_wait_states        = tr.num_wait_states;
		delay_until_next_trans = tr.delay_until_next_trans;
		transaction_finished   = tr.transaction_finished;
		monitor_error          = tr.monitor_error;
		bus_width              = tr.bus_width;
		setup_time             = tr.setup_time;
		complete_time          = tr.complete_time;
	endfunction : do_copy


	// Compare two trans on the interface-signal fields only -- internal
	// bookkeeping, timestamps, and timing knobs are intentionally ignored,
	// since two transfers can be functionally identical on the wire while
	// differing in any of those. Write-only fields (wdata/strb) are compared
	// only for writes and read-only fields (rdata) only for reads, matching
	// the spec's signal-validity rules (Appendix A).
	virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
		ovip_apb_trans tr;
		if(!$cast(tr, rhs)) return 0;
		return super.do_compare(rhs, comparer)
			&& addr   == tr.addr
			&& write  == tr.write
			&& prot   == tr.prot
			&& slverr == tr.slverr
			&& (!write || (wdata == tr.wdata && strb == tr.strb))
			&& ( write ||  rdata == tr.rdata);
	endfunction : do_compare


	// Per-field diff of the interface-signal mismatches between `this` (read
	// as "expected") and `rhs` (read as "actual"). Empty string when the two
	// are equal under do_compare's policy. Scoreboards typically call this
	// after `compare()` returns 0 and wrap the result in their own uvm_error.
	virtual function string diff(ovip_apb_trans rhs);
		string s = "";
		if(addr   != rhs.addr  ) s = {s, $sformatf("  addr:   expected=0x%0h   actual=0x%0h\n", addr,   rhs.addr)};
		if(write  != rhs.write ) s = {s, $sformatf("  write:  expected=%0b     actual=%0b\n",   write,  rhs.write)};
		if(prot   != rhs.prot  ) s = {s, $sformatf("  prot:   expected=0x%0h   actual=0x%0h\n", prot,   rhs.prot)};
		if(slverr != rhs.slverr) s = {s, $sformatf("  slverr: expected=%0b     actual=%0b\n",   slverr, rhs.slverr)};
		if(write && wdata != rhs.wdata) s = {s, $sformatf("  wdata:  expected=0x%0h   actual=0x%0h\n", wdata, rhs.wdata)};
		if(write && strb  != rhs.strb ) s = {s, $sformatf("  strb:   expected=0x%0h   actual=0x%0h\n", strb,  rhs.strb)};
		if(!write && rdata != rhs.rdata) s = {s, $sformatf("  rdata:  expected=0x%0h   actual=0x%0h\n", rdata, rhs.rdata)};
		return s;
	endfunction : diff


	virtual function string convert2string();
		return $sformatf("(%s) APB %s addr=0x%0h data=0x%0h strb=0x%0h prot=%0h resp=%s waits=%0d",
			get_name(), write ? "WRITE" : "READ", addr, write ? wdata : rdata, strb, prot,
			slverr ? "SLVERR" : "OKAY", num_wait_states);
	endfunction : convert2string


	// ------------------------------------------------------------------------
	// Transaction-logger hooks (see ovip_apb_trans_logger).
	// ------------------------------------------------------------------------

	virtual function string log_header();
		return $sformatf("%-5s %-10s %-10s %-4s %-4s %-6s %-5s %-11s",
			"dir", "addr", "data", "strb", "prot", "resp", "waits", "setup_time");
	endfunction : log_header


	virtual function string log_line();
		return $sformatf("%-5s %-10s %-10s %-4s %-4s %-6s %-50d %-11s",
			write ? "WR" : "RD",
			$sformatf("%0h", addr),
			$sformatf("%0h", write ? wdata : rdata),
			$sformatf("%0h", strb),
			$sformatf("%0h", prot),
			slverr ? "SLVERR" : "OKAY",
			num_wait_states,
			$sformatf("%0t", setup_time));
	endfunction : log_line

endclass : ovip_apb_trans

`endif
