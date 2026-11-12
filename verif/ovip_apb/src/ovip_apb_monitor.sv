`ifndef OVIP_APB_MONITOR__SV
`define OVIP_APB_MONITOR__SV

// APB bus monitor. Tracks the IDLE / SETUP / ACCESS operating states, builds
// one ovip_apb_trans per transfer, publishes it on `analysis_port` at
// completion (and on `analysis_port_cont` at the SETUP cycle), and runs the
// protocol checks inline:
//   - XZ on PSEL every cycle; XZ on the request payload while PSEL is HIGH;
//     XZ on PREADY during ACCESS; XZ on the response payload at completion
//     (per the signal-validity rules of Appendix A)
//   - SETUP lasts exactly one cycle: PENABLE must be LOW on the SETUP cycle
//     and HIGH on the following cycle (spec section 4.1)
//   - a transfer starts with a SETUP cycle: PSEL and PENABLE must not both
//     be HIGH while no transfer is in progress (spec section 4.1)
//   - PENABLE must be deasserted at the end of the transfer (spec section 3.1)
//   - PSEL must not drop before the transfer completes
//   - PADDR/PWRITE/PWDATA/PSTRB/PPROT stable from SETUP through completion
//     while PREADY extends the transfer (spec section 3.1.2)
//   - PSTRB must be all-LOW during a read transfer (spec section 3.2)
// The X/Z and stability checks of PWDATA cover the lanes whose PSTRB bit is
// HIGH (Appendix A.1: the active write data lanes only), and every lane of
// an agent with no PSTRB. cfg.check_undefined_data_lanes makes them cover
// every lane inside the data width.
//
// Completer support: on the SETUP cycle the monitor forwards a copy of the
// request through `response_req_port` so the slave sequence can build the
// response in zero time (active COMPLETER agents only).
class ovip_apb_monitor extends uvm_monitor;

	virtual ovip_apb_agent_if vif;
	ovip_apb_agent_config     cfg;

	uvm_analysis_port#(ovip_apb_trans) analysis_port_cont;
	uvm_analysis_port#(ovip_apb_trans) analysis_port;

	// Blocking-get port the completer-side slave sequence taps to fetch
	// newly-monitored requests. Mirrors the ovip_axi / ovip_axi_stream
	// convention.
	uvm_blocking_get_imp#(ovip_apb_trans, ovip_apb_monitor) response_req_port;
	protected ovip_apb_trans pending_rsp_req[$];

	// Per-agent prefix on the APB_MON message ID. Empty by default; set from
	// cfg.agent_tag in build_phase.
	string MESSAGE_TAG;

	protected ovip_apb_addr_t ADDR_MASK;
	protected ovip_apb_data_t DATA_MASK;
	protected ovip_apb_strb_t STRB_MASK;

	// PWDATA, PADDR and PSTRB as sampled on the SETUP cycle, with their X
	// and Z bits, for the stability check (the item holds 0 in their place).
	protected logic [`OVIP_APB_MAX_DATA_WIDTH-1:0] setup_pwdata;
	protected logic [`OVIP_APB_MAX_ADDR_WIDTH-1:0] setup_paddr;
	protected logic [`OVIP_APB_MAX_STRB_WIDTH-1:0] setup_pstrb;

	`uvm_component_utils(ovip_apb_monitor)

	function new(string name = "ovip_apb_monitor", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	extern virtual function void build_phase(uvm_phase phase);
	extern virtual task          run_phase(uvm_phase phase);

	extern virtual task rst_monitor();

	// Per-cycle XZ checks per the Appendix A validity rules.
	extern virtual task          xz_select_check();
	extern virtual function void check_request_payload_xz();
	extern virtual function void check_response_payload_xz(bit is_write);
	extern protected virtual function ovip_apb_data_t checked_pwdata_lanes(ovip_apb_strb_t strb);

	// Bus tracker + supporting helpers.
	extern virtual task          bus_monitor();
	extern virtual task          track_transfer(output bit at_setup);
	extern virtual function ovip_apb_trans sample_request();
	extern virtual function void check_read_strb(ovip_apb_trans tr);
	extern virtual function bit  request_stable(ovip_apb_trans tr);
	extern virtual function void close_and_publish(ovip_apb_trans tr);

	// Completer-side req-port hooks (match ovip_axi / ovip_axi_stream).
	extern virtual task          get(output ovip_apb_trans tr);
	extern virtual function void send_rsp_req(ovip_apb_trans tr);

endclass : ovip_apb_monitor


function void ovip_apb_monitor::build_phase(uvm_phase phase);
	super.build_phase(phase);

	if(!uvm_config_db#(virtual ovip_apb_agent_if)::get(this, "", "vif", vif))
		`uvm_fatal("MISSING_VIF", $sformatf("Missing virtual interface - %s.vif", get_full_name()))

	if(!uvm_config_db#(ovip_apb_agent_config)::get(this, "", "cfg", cfg))
		`uvm_fatal("MISSING_CFG", $sformatf("Missing agent config - %s.cfg", get_full_name()))

	MESSAGE_TAG = (cfg.agent_tag == "") ? "" : {cfg.agent_tag, "/"};

	analysis_port      = new("analysis_port", this);
	analysis_port_cont = new("analysis_port_cont", this);

	if(cfg.agent_type == OVIP_APB_COMPLETER && cfg.is_active == UVM_ACTIVE)
		response_req_port = new("response_req_port", this);

	ADDR_MASK = (ovip_apb_addr_t'(1) << cfg.addr_width)   - 1;
	DATA_MASK = (ovip_apb_data_t'(1) << cfg.data_width*8) - 1;
	STRB_MASK = (ovip_apb_strb_t'(1) << cfg.data_width)   - 1;
endfunction : build_phase


task ovip_apb_monitor::run_phase(uvm_phase phase);
	`uvm_info({MESSAGE_TAG, "APB_MON"}, "monitor up; waiting for reset deassertion", UVM_HIGH)

	forever
	begin
		@(vif.monitor_cb iff vif.monitor_cb.presetn);
		`uvm_info({MESSAGE_TAG, "APB_MON"}, "reset deasserted", UVM_HIGH)

		`OVIP_BEGIN_FIRST_OF
			rst_monitor();
			fork
				xz_select_check();
				bus_monitor();
			join
		`OVIP_END_FIRST_OF
	end
endtask : run_phase


task ovip_apb_monitor::rst_monitor();
	@(vif.monitor_cb iff vif.monitor_cb.presetn == 1'b0);
	`uvm_info({MESSAGE_TAG, "APB_MON"}, "reset asserted", UVM_LOW)
	// Drop any pending completer request so it doesn't survive the reset.
	pending_rsp_req.delete();
endtask : rst_monitor


// PSEL must always be a known value (Appendix A: PSEL must always be valid).
task ovip_apb_monitor::xz_select_check();
	forever
	begin
		@(vif.monitor_cb);
		`OVIP_APB_MON_XZ_CHECK(psel, psel)
	end
endtask : xz_select_check


// The bits of PWDATA that the X/Z and stability checks cover in a write with
// the strobes `strb`: the lanes whose PSTRB bit is HIGH. Every lane inside
// the data width when the agent has no PSTRB, or with
// cfg.check_undefined_data_lanes.
function ovip_apb_data_t ovip_apb_monitor::checked_pwdata_lanes(ovip_apb_strb_t strb);
	ovip_apb_data_t lanes = '0;
	if(cfg.check_undefined_data_lanes || !cfg.pstrb_en) return DATA_MASK;
	for(int ii = 0; ii < cfg.data_width; ii++)
		if(strb[ii]) lanes[ii*8 +: 8] = '1;
	return lanes;
endfunction : checked_pwdata_lanes


// Signals that must be valid while PSEL is asserted (Appendix A): PADDR,
// PENABLE, PWRITE, PPROT, PSTRB, plus PWDATA on writes, on the lanes of
// checked_pwdata_lanes.
function void ovip_apb_monitor::check_request_payload_xz();
	`OVIP_APB_MON_XZ_CHECK(penable, penable)
	`OVIP_APB_MON_XZ_CHECK(pwrite, pwrite)
	if((^(vif.monitor_cb.paddr & ADDR_MASK)) === 1'bx)
		`uvm_error({MESSAGE_TAG, "APB_MON/XZ_CHECK"}, "PADDR contains X's or Z's while PSEL is HIGH.")
	if(cfg.pprot_en)
		`OVIP_APB_MON_XZ_CHECK(pprot, pprot)
	if(vif.monitor_cb.pwrite === 1'b1)
	begin
		if((^(vif.monitor_cb.pwdata & checked_pwdata_lanes(vif.monitor_cb.pstrb))) === 1'bx)
			`uvm_error({MESSAGE_TAG, "APB_MON/XZ_CHECK"}, "PWDATA contains X's or Z's during a write transfer.")
		if(cfg.pstrb_en && (^(vif.monitor_cb.pstrb & STRB_MASK)) === 1'bx)
			`uvm_error({MESSAGE_TAG, "APB_MON/XZ_CHECK"}, "PSTRB contains X's or Z's during a write transfer.")
	end
endfunction : check_request_payload_xz


// Signals that must be valid at completion (PSEL && PENABLE && PREADY):
// PRDATA on reads, PSLVERR (Appendix A).
function void ovip_apb_monitor::check_response_payload_xz(bit is_write);
	if(!is_write && (^(vif.monitor_cb.prdata & DATA_MASK)) === 1'bx)
		`uvm_error({MESSAGE_TAG, "APB_MON/XZ_CHECK"}, "PRDATA contains X's or Z's at read completion.")
	if(cfg.pslverr_en)
		`OVIP_APB_MON_XZ_CHECK(pslverr, pslverr)
endfunction : check_response_payload_xz


// One track_transfer() call per transfer. `at_setup` chains back-to-back
// transfers: when the post-completion cycle turns out to already be the next
// SETUP cycle, the loop re-enters track_transfer without consuming an edge.
// Between transfers, a cycle with PSEL and PENABLE both HIGH is an ACCESS
// cycle with no SETUP cycle before it. It is reported on its first cycle
// and not again while the two stay HIGH.
task ovip_apb_monitor::bus_monitor();
	bit at_setup = 0;
	// PSEL and PENABLE were both HIGH on the last cycle, and it was reported.
	bit access_reported = 0;
	forever
	begin
		while(!at_setup)
		begin
			@(vif.monitor_cb);
			// A cycle sampled with PRESETn LOW starts nothing: rst_monitor
			// ends this thread on the same edge, before or after it wakes.
			if(vif.monitor_cb.presetn !== 1'b1) continue;
			if(vif.monitor_cb.psel === 1'b1 && vif.monitor_cb.penable !== 1'b1)
				at_setup = 1;
			else if(vif.monitor_cb.psel === 1'b1 && vif.monitor_cb.penable === 1'b1)
			begin
				if(!access_reported)
					`uvm_error({MESSAGE_TAG, "APB_MON/FSM"}, "PSEL and PENABLE HIGH with no transfer in progress: an ACCESS cycle must follow a SETUP cycle (spec section 4.1).")
				access_reported = 1;
			end
			else
				access_reported = 0;
		end
		track_transfer(at_setup);
		// PENABLE still HIGH after a completion is reported by track_transfer.
		access_reported = (vif.monitor_cb.psel === 1'b1 && vif.monitor_cb.penable === 1'b1);
	end
endtask : bus_monitor


// Entered with the SETUP cycle currently sampled on monitor_cb. Consumes
// edges up to (and including) the cycle after completion, so it can both
// enforce the PENABLE-deassert rule and detect a back-to-back SETUP.
task ovip_apb_monitor::track_transfer(output bit at_setup);
	ovip_apb_trans tr;
	at_setup = 0;

	check_request_payload_xz();
	tr = sample_request();
	setup_pwdata = vif.monitor_cb.pwdata;
	setup_paddr  = vif.monitor_cb.paddr;
	setup_pstrb  = vif.monitor_cb.pstrb;
	// first, so the request forwarded to the slave sequence carries
	// monitor_error
	check_read_strb(tr);
	analysis_port_cont.write(tr);
	send_rsp_req(tr);

	// SETUP lasts exactly one cycle: the next cycle must be ACCESS.
	@(vif.monitor_cb);
	// A reset ends the transfer, and rst_monitor drops it. A requester reset
	// asynchronously drops PSEL on the same edge, and the two threads wake
	// on that edge in either order, so the reset is checked here first.
	if(vif.monitor_cb.presetn !== 1'b1) return;
	if(vif.monitor_cb.psel !== 1'b1)
	begin
		`uvm_error({MESSAGE_TAG, "APB_MON/FSM"}, "PSEL deasserted after the SETUP cycle -- a started transfer must proceed to ACCESS and complete (spec section 4.1).")
		return;
	end
	if(vif.monitor_cb.penable !== 1'b1)
	begin
		`uvm_error({MESSAGE_TAG, "APB_MON/FSM"}, "PENABLE not asserted on the cycle after SETUP -- SETUP must last exactly one cycle (spec section 4.1).")
		at_setup = 1; // the current cycle looks like a fresh SETUP; recover there
		return;
	end

	// ACCESS: walk wait states until PREADY completes the transfer.
	forever
	begin
		check_request_payload_xz();
		`OVIP_APB_MON_XZ_CHECK(pready, pready)
		if(!request_stable(tr)) tr.monitor_error = 1;
		check_read_strb(tr);

		if(vif.monitor_cb.pready === 1'b1) break;

		tr.num_wait_states++;
		@(vif.monitor_cb);
		if(vif.monitor_cb.presetn !== 1'b1) return;   // a reset ends the transfer (see above)
		if(vif.monitor_cb.psel !== 1'b1 || vif.monitor_cb.penable !== 1'b1)
		begin
			`uvm_error({MESSAGE_TAG, "APB_MON/FSM"}, "PSEL/PENABLE deasserted while PREADY was LOW -- the ACCESS state must be held until the completer asserts PREADY (spec section 4.1).")
			at_setup = (vif.monitor_cb.psel === 1'b1 && vif.monitor_cb.penable !== 1'b1);
			return;
		end
	end

	// Completion cycle: sample the response and publish.
	check_response_payload_xz(tr.write);
	if(!tr.write) tr.rdata = vif.monitor_cb.prdata & DATA_MASK;
	tr.slverr = cfg.pslverr_en ? (vif.monitor_cb.pslverr === 1'b1) : 1'b0;
	close_and_publish(tr);

	// End-of-transfer rule: PENABLE must be deasserted on the next cycle
	// (which is either IDLE or the next transfer's SETUP cycle).
	@(vif.monitor_cb);
	if(vif.monitor_cb.presetn !== 1'b1) return;   // a reset: no check, and no next SETUP (see above)
	if(vif.monitor_cb.penable === 1'b1)
		`uvm_error({MESSAGE_TAG, "APB_MON/FSM"}, "PENABLE still asserted on the cycle after the transfer completed (spec section 3.1: PENABLE is deasserted at the end of the transfer).")
	at_setup = (vif.monitor_cb.psel === 1'b1 && vif.monitor_cb.penable !== 1'b1);
endtask : track_transfer


function ovip_apb_trans ovip_apb_monitor::sample_request();
	ovip_apb_trans tr = ovip_apb_trans::type_id::create("apb_tr");
	tr.bus_width  = cfg.data_width;
	tr.setup_time = $realtime;
	tr.addr  = vif.monitor_cb.paddr & ADDR_MASK;
	tr.write = (vif.monitor_cb.pwrite === 1'b1);
	tr.prot  = cfg.pprot_en ? ovip_apb_prot_t'(vif.monitor_cb.pprot) : '0;
	if(tr.write)
	begin
		tr.wdata = vif.monitor_cb.pwdata & DATA_MASK;
		// PSTRB absent -> every byte lane is valid for a write (spec table
		// 3-1), so downstream consumers (memory-backed slave sequence,
		// scoreboards) always see effective strobes.
		tr.strb = cfg.pstrb_en ? (vif.monitor_cb.pstrb & STRB_MASK)
		                       : (ovip_apb_strb_t'(1) << cfg.data_width) - 1;
	end
	return tr;
endfunction : sample_request


// Spec section 3.2: all PSTRB bits must be LOW during a read transfer.
// Called on the SETUP cycle and on every ACCESS cycle.
function void ovip_apb_monitor::check_read_strb(ovip_apb_trans tr);
	if(!cfg.pstrb_en || tr.write) return;
	if((vif.monitor_cb.pstrb & STRB_MASK) !== '0)
	begin
		`uvm_error({MESSAGE_TAG, "APB_MON/READ_STRB"}, "PSTRB is active during a read transfer (spec section 3.2 requires all-LOW).")
		tr.monitor_error = 1;
	end
endfunction : check_read_strb


// Spec section 3.1.2 / 4.1: PADDR, PWRITE, PWDATA, PSTRB, and PPROT must not
// change between SETUP and the end of the transfer. Compares the live wire
// against the SETUP-cycle snapshot held in `tr`.
function bit ovip_apb_monitor::request_stable(ovip_apb_trans tr);
	bit ok = 1;
	// against the SETUP cycle values: an X or Z bit that stays is not a change
	if((vif.monitor_cb.paddr & ADDR_MASK) !== (setup_paddr & ADDR_MASK))
	begin
		`uvm_error({MESSAGE_TAG, "APB_MON/STABILITY"}, $sformatf("PADDR changed during the transfer (setup=0x%0h, now=0x%0h).", setup_paddr & ADDR_MASK, vif.monitor_cb.paddr & ADDR_MASK))
		ok = 0;
	end
	if(bit'(vif.monitor_cb.pwrite) !== tr.write)
	begin
		`uvm_error({MESSAGE_TAG, "APB_MON/STABILITY"}, "PWRITE changed during the transfer.")
		ok = 0;
	end
	if(cfg.pprot_en && ovip_apb_prot_t'(vif.monitor_cb.pprot) !== tr.prot)
	begin
		`uvm_error({MESSAGE_TAG, "APB_MON/STABILITY"}, "PPROT changed during the transfer.")
		ok = 0;
	end
	if(tr.write)
	begin
		// the lanes of the SETUP cycle's strobes; an X or Z bit that stays
		// is not a change
		ovip_apb_data_t lanes = checked_pwdata_lanes(tr.strb);
		if((vif.monitor_cb.pwdata & lanes) !== (setup_pwdata & lanes))
		begin
			`uvm_error({MESSAGE_TAG, "APB_MON/STABILITY"}, "PWDATA changed during a write transfer.")
			ok = 0;
		end
		if(cfg.pstrb_en && (vif.monitor_cb.pstrb & STRB_MASK) !== (setup_pstrb & STRB_MASK))
		begin
			`uvm_error({MESSAGE_TAG, "APB_MON/STABILITY"}, "PSTRB changed during a write transfer.")
			ok = 0;
		end
	end
	return ok;
endfunction : request_stable


function void ovip_apb_monitor::close_and_publish(ovip_apb_trans tr);
	tr.complete_time        = $realtime;
	tr.transaction_finished = 1;
	`uvm_info({MESSAGE_TAG, "APB_MON"}, tr.convert2string(), UVM_LOW)
	analysis_port.write(tr);
endfunction : close_and_publish


function void ovip_apb_monitor::send_rsp_req(ovip_apb_trans tr);
	if(cfg.agent_type != OVIP_APB_COMPLETER) return;
	if(cfg.is_active  != UVM_ACTIVE)         return;
	begin
		ovip_apb_trans rsp = ovip_apb_trans::type_id::create("rsp_req");
		rsp.copy(tr);
		pending_rsp_req.push_back(rsp);
	end
endfunction : send_rsp_req


task ovip_apb_monitor::get(output ovip_apb_trans tr);
	wait(pending_rsp_req.size());
	tr = pending_rsp_req.pop_front();
endtask : get

`endif
