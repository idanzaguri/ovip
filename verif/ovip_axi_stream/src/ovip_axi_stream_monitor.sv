`ifndef OVIP_AXI_STREAM_MONITOR__SV
`define OVIP_AXI_STREAM_MONITOR__SV

// AXI-Stream channel monitor. Samples every transfer, accumulates beats into
// the open packet of the transfer's stream, one per TID and TDEST pair
// (closed when TLAST is sampled or, with TLAST disabled, after every single
// transfer), publishes completed packets on `analysis_port`, and runs the
// protocol checks inline:
//   - XZ on TVALID/TREADY at every clock; XZ on payload while TVALID HIGH
//   - TVALID and payload must stay stable from the cycle TVALID is asserted
//     until the handshake fires (TVALID && TREADY)
//     Both checks look at TDATA on the lanes of data bytes and at TUSER on
//     the lanes of data bytes and position bytes, or on every lane with
//     cfg.check_undefined_data_lanes.
//   - TVALID must be LOW while ARESETn is asserted; first TVALID after reset
//     deassertion can be no earlier than the second rising ACLK edge
//   - TKEEP = 0 with TSTRB = 1 is the reserved byte-qualifier combination
//   - with cfg.continuous_packets: TID and TDEST must not change after a
//     transfer with TLAST LOW (packets must not interleave), and a packet
//     has no null bytes within it
//   - AXI5: TWAKEUP, once asserted with TVALID, must stay HIGH until TREADY
//   - AXI5 parity is not checked: the interface has no check signals, and
//     cfg.parity_en is read only by check_config
class ovip_axi_stream_monitor extends uvm_monitor;

	virtual ovip_axi_stream_agent_if vif;
	ovip_axi_stream_agent_config     cfg;

	uvm_analysis_port#(ovip_axi_stream_trans) analysis_port_cont;
	uvm_analysis_port#(ovip_axi_stream_trans) analysis_port;

	// Optional UVM blocking-get port the receiver-side slave sequence taps to
	// fetch newly-monitored "request" packets (TREADY pattern updates, etc.).
	// Mirrors the ovip_axi convention.
	//
	// The monitor queues a copy of a packet for this port only after a reader
	// has called get() once. A packet that completes before the first get()
	// is not delivered, so a slave sequence must be running before the
	// traffic it has to see. With no reader nothing is queued.
	uvm_blocking_get_imp#(ovip_axi_stream_trans, ovip_axi_stream_monitor) response_req_port;
	protected ovip_axi_stream_trans pending_rsp_req[$];
	protected bit has_rsp_req_reader;   // set by the first get()

	// Per-agent prefix on the AXIS_MON message ID. Empty by default; set from
	// cfg.agent_tag in build_phase.
	string MESSAGE_TAG;

	// The open packets, one per stream, each kept across handshakes until its
	// TLAST. A stream is a TID and TDEST pair (spec section 2.7), and streams
	// may interleave transfer by transfer, so the key is {TID, TDEST} on the
	// live bits. A signal that is not enabled counts as 0: with neither TID
	// nor TDEST the channel has one open packet.
	typedef bit [`OVIP_AXI_STREAM_MAX_ID_WIDTH + `OVIP_AXI_STREAM_MAX_DEST_WIDTH - 1 : 0] stream_key_t;
	protected ovip_axi_stream_trans open_tr[stream_key_t];

	// The packet of the previous transfer while it is open (its TLAST was
	// LOW), else null. For the cfg.continuous_packets check.
	protected ovip_axi_stream_trans prev_tr;

	// ARESETn was sampled LOW at least once. For the exit-from-reset check.
	protected bit reset_seen;

	// The live bits of each payload signal, from cfg at the start of
	// run_phase (the ovip_axi convention). The wires are MAX-width. An OVIP
	// transmitter drives the unused upper bits to 0, but a DUT port wired to
	// the low bits leaves them undriven (Z), so every check and every sample
	// looks at the live bits only. A width of 0 on TID or TDEST keeps the
	// whole wire, as before.
	ovip_axi_stream_data_t DATA_MASK;
	ovip_axi_stream_strb_t STRB_MASK;
	ovip_axi_stream_keep_t KEEP_MASK;
	ovip_axi_stream_id_t   ID_MASK;
	ovip_axi_stream_dest_t DEST_MASK;
	ovip_axi_stream_user_t USER_MASK;

	`uvm_component_utils(ovip_axi_stream_monitor)

	function new(string name = "ovip_axi_stream_monitor", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	extern virtual function void build_phase(uvm_phase phase);
	extern virtual task          run_phase(uvm_phase phase);
	extern virtual function void set_masks();

	// Reset gates and exit-from-reset rule.
	extern virtual task rst_monitor();
	extern virtual task tvalid_low_during_reset_check();
	extern virtual task exit_from_reset_check();

	// Per-cycle XZ on the handshake and (when TVALID is HIGH) on the payload.
	extern virtual task xz_handshake_check();
	extern virtual task xz_payload_check();
	extern virtual function void check_payload_xz();

	// The TDATA and TUSER bits that the XZ check and the stability check cover.
	extern virtual function void get_checked_lanes(output ovip_axi_stream_data_t data_mask, output ovip_axi_stream_user_t user_mask);

	// Stability of TVALID + payload between assertion and handshake.
	extern virtual task stability_check();

	// AXI5 wake-up rule.
	extern virtual task wakeup_check();

	// Bus monitor + supporting helpers.
	extern virtual task          bus_monitor();
	extern virtual function void sample_beat_into(ovip_axi_stream_trans tr);
	extern virtual function void check_byte_qualifiers(ovip_axi_stream_trans tr);
	extern virtual function void check_continuous_null_bytes(ovip_axi_stream_trans tr);
	extern virtual function void check_packet_scope_stability(ovip_axi_stream_trans tr);
	extern virtual function bit  is_packet_done();
	extern virtual function void close_and_publish(ovip_axi_stream_trans tr);

	// Slave-side req-port hook (matches ovip_axi).
	extern virtual task          get(output ovip_axi_stream_trans tr);
	extern virtual function void send_rsp_req(ovip_axi_stream_trans tr);

endclass : ovip_axi_stream_monitor


function void ovip_axi_stream_monitor::build_phase(uvm_phase phase);
	super.build_phase(phase);

	if(!uvm_config_db#(virtual ovip_axi_stream_agent_if)::get(this, "", "vif", vif))
		`uvm_fatal("MISSING_VIF", $sformatf("Missing virtual interface - %s.vif", get_full_name()))

	if(!uvm_config_db#(ovip_axi_stream_agent_config)::get(this, "", "cfg", cfg))
		`uvm_fatal("MISSING_CFG", $sformatf("Missing agent config - %s.cfg", get_full_name()))

	MESSAGE_TAG = (cfg.agent_tag == "") ? "" : {cfg.agent_tag, "/"};

	analysis_port      = new("analysis_port", this);
	analysis_port_cont = new("analysis_port_cont", this);

	if(cfg.agent_type == OVIP_AXI_STREAM_RECEIVER && cfg.is_active == UVM_ACTIVE)
		response_req_port = new("response_req_port", this);
endfunction : build_phase


function void ovip_axi_stream_monitor::set_masks();
	DATA_MASK = (ovip_axi_stream_data_t'(1) << (cfg.tdata_width * 8)) - 1;
	STRB_MASK = (ovip_axi_stream_strb_t'(1) << cfg.tdata_width) - 1;
	KEEP_MASK = (ovip_axi_stream_keep_t'(1) << cfg.tdata_width) - 1;
	ID_MASK   = (cfg.tid_width   > 0) ? (ovip_axi_stream_id_t'(1)   << cfg.tid_width)   - 1 : '1;
	DEST_MASK = (cfg.tdest_width > 0) ? (ovip_axi_stream_dest_t'(1) << cfg.tdest_width) - 1 : '1;
	USER_MASK = (ovip_axi_stream_user_t'(1) << (cfg.tuser_bits_per_byte * cfg.tdata_width)) - 1;
endfunction : set_masks


task ovip_axi_stream_monitor::run_phase(uvm_phase phase);
	`uvm_info({MESSAGE_TAG, "AXIS_MON"}, "monitor up; waiting for reset deassertion", UVM_HIGH)
	set_masks();

	// Run the reset-tied checkers immediately so the during-reset and
	// exit-from-reset rules are observed even before the bus comes alive.
	fork
		tvalid_low_during_reset_check();
		begin
			@(vif.monitor_cb iff vif.monitor_cb.aresetn == 1'b0);
			reset_seen = 1;
		end
	join_none

	forever
	begin
		@(vif.monitor_cb iff vif.monitor_cb.aresetn);
		`uvm_info({MESSAGE_TAG, "AXIS_MON"}, "reset deasserted", UVM_HIGH)

		`OVIP_BEGIN_FIRST_OF
			rst_monitor();
			fork
				exit_from_reset_check();
				xz_handshake_check();
				xz_payload_check();
				stability_check();
				wakeup_check();
				bus_monitor();
			join
		`OVIP_END_FIRST_OF
	end
endtask : run_phase


task ovip_axi_stream_monitor::rst_monitor();
	@(vif.monitor_cb iff vif.monitor_cb.aresetn == 1'b0);
	`uvm_info({MESSAGE_TAG, "AXIS_MON"}, "reset asserted", UVM_LOW)
	// Drop every open packet so none survives the reset.
	open_tr.delete();
	prev_tr = null;
	pending_rsp_req.delete();
endtask : rst_monitor


task ovip_axi_stream_monitor::tvalid_low_during_reset_check();
	forever
	begin
		@(vif.monitor_cb iff vif.monitor_cb.aresetn == 1'b0);
		// Spec section 2.8.2: TVALID must be LOW while ARESETn is asserted.
		// One cycle of grace, as ovip_axi's monitor gives: a reset in the
		// middle of a packet can still sample TVALID high on its first cycle,
		// since a synchronous transmitter sees the reset on that same edge.
		// From the next cycle on, every reset cycle is checked. We flag only
		// TVALID == 1; X during the first few sim cycles is the usual
		// pre-drive state, not a spec violation.
		@(vif.monitor_cb);
		while(vif.monitor_cb.aresetn == 1'b0)
		begin
			if(vif.monitor_cb.tvalid === 1'b1)
				`uvm_error({MESSAGE_TAG, "AXIS_MON/RESET"}, "TVALID asserted while ARESETn is asserted (spec section 2.8.2).")
			@(vif.monitor_cb);
		end
	end
endtask : tvalid_low_during_reset_check


// Spec section 2.8.2 (figure 2-4): TVALID must still be LOW at the very edge
// where ARESETn is first sampled HIGH (T2 in the figure); it is allowed to
// rise on the next edge (T3). This task is forked right at that T2 edge by
// run_phase, so we just check TVALID at the current edge -- no @cb here.
// The edge is an exit from reset only after ARESETn was sampled LOW once: a
// bench may hold ARESETn HIGH from time 0. Only TVALID == 1 is flagged, as in
// the check during reset: X or Z there is not "TVALID asserted".
task ovip_axi_stream_monitor::exit_from_reset_check();
	if(!reset_seen) return;
	if(vif.monitor_cb.tvalid === 1'b1)
		`uvm_error({MESSAGE_TAG, "AXIS_MON/RESET"}, "TVALID asserted on the same ACLK edge where ARESETn was first sampled HIGH -- spec section 2.8.2 requires TVALID to remain LOW for that edge.")
endtask : exit_from_reset_check


task ovip_axi_stream_monitor::xz_handshake_check();
	forever
	begin
		@(vif.monitor_cb);
		// No check on the edge where ARESETn is first sampled LOW, as in
		// stability_check: rst_monitor ends this thread on that edge, and the
		// two threads wake on it in either order.
		if(vif.monitor_cb.aresetn !== 1'b1) continue;
		`OVIP_AXI_STREAM_MON_XZ_CHECK(tvalid, tvalid)
		if(cfg.tready_en) `OVIP_AXI_STREAM_MON_XZ_CHECK(tready, tready)
	end
endtask : xz_handshake_check


task ovip_axi_stream_monitor::xz_payload_check();
	forever
	begin
		@(vif.monitor_cb iff vif.monitor_cb.tvalid == 1'b1);
		check_payload_xz();
	end
endtask : xz_payload_check


// The XOR-reduction runs over the live bits only: the signal ANDed with its
// mask from set_masks(). The OVIP drivers leave the unused upper bits at 0,
// but a DUT port wired to the low bits leaves them undriven, and Z there is
// not a fault. A mask, not a bit-slice: variable slice ranges (e.g.
// `[cfg.width*8-1:0]`) are not portable through Questa's vopt pass.
// TDATA and TUSER are checked on the lanes that get_checked_lanes() gives.
function void ovip_axi_stream_monitor::check_payload_xz();
	ovip_axi_stream_data_t data_mask;
	ovip_axi_stream_user_t user_mask;
	get_checked_lanes(data_mask, user_mask);
	if(cfg.tdata_width > 0)
		if(^(vif.monitor_cb.tdata & data_mask) === 1'bx)
			`uvm_error({MESSAGE_TAG, "AXIS_MON/XZ_CHECK"}, "TDATA contains X's or Z's while TVALID is HIGH.")
	if(cfg.tstrb_en && cfg.tdata_width > 0)
		if(^(vif.monitor_cb.tstrb & STRB_MASK) === 1'bx)
			`uvm_error({MESSAGE_TAG, "AXIS_MON/XZ_CHECK"}, "TSTRB contains X's or Z's while TVALID is HIGH.")
	if(cfg.tkeep_en && cfg.tdata_width > 0)
		if(^(vif.monitor_cb.tkeep & KEEP_MASK) === 1'bx)
			`uvm_error({MESSAGE_TAG, "AXIS_MON/XZ_CHECK"}, "TKEEP contains X's or Z's while TVALID is HIGH.")
	if(cfg.tlast_en) `OVIP_AXI_STREAM_MON_XZ_CHECK(tlast, tlast)
	if(cfg.tid_en   && cfg.tid_width   > 0)
		if(^(vif.monitor_cb.tid & ID_MASK) === 1'bx)
			`uvm_error({MESSAGE_TAG, "AXIS_MON/XZ_CHECK"}, "TID contains X's or Z's while TVALID is HIGH.")
	if(cfg.tdest_en && cfg.tdest_width > 0)
		if(^(vif.monitor_cb.tdest & DEST_MASK) === 1'bx)
			`uvm_error({MESSAGE_TAG, "AXIS_MON/XZ_CHECK"}, "TDEST contains X's or Z's while TVALID is HIGH.")
	if(cfg.tuser_en && cfg.tuser_bits_per_byte > 0 && cfg.tdata_width > 0)
		if(^(vif.monitor_cb.tuser & user_mask) === 1'bx)
			`uvm_error({MESSAGE_TAG, "AXIS_MON/XZ_CHECK"}, "TUSER contains X's or Z's while TVALID is HIGH.")
	if(cfg.twakeup_en) `OVIP_AXI_STREAM_MON_XZ_CHECK(twakeup, twakeup)
endfunction : check_payload_xz


// The TDATA and TUSER bits that the XZ check and the stability check cover
// in the current cycle. With cfg.check_undefined_data_lanes: every live bit.
// Without it: TDATA on the lanes of data bytes only, TKEEP HIGH and TSTRB
// HIGH, where an absent TKEEP counts as HIGH and an absent TSTRB as TKEEP
// (spec section 3.1.2), and TUSER on the lanes of data bytes and position
// bytes, TKEEP HIGH. The TDATA of a position byte or a null byte is not
// valid (spec section 2.5.2) and the TUSER bits of a null byte are not
// transferred (spec section 2.9), so a transmitter may leave them X or
// change them while the beat waits.
function void ovip_axi_stream_monitor::get_checked_lanes(output ovip_axi_stream_data_t data_mask, output ovip_axi_stream_user_t user_mask);
	bit is_kept;
	bit is_data;
	data_mask = DATA_MASK;
	user_mask = USER_MASK;
	// with neither qualifier every byte is a data byte
	if(cfg.check_undefined_data_lanes || (!cfg.tkeep_en && !cfg.tstrb_en)) return;
	for(int b = 0; b < cfg.tdata_width; b++)
	begin
		is_kept = cfg.tkeep_en ? (vif.monitor_cb.tkeep[b] === 1'b1) : 1'b1;
		is_data = cfg.tstrb_en ? (vif.monitor_cb.tstrb[b] === 1'b1) : is_kept;
		if(is_kept && is_data) continue;
		data_mask[b*8 +: 8] = '0;
		if(is_kept) continue;   // a position byte: its TUSER bits are transferred
		for(int k = 0; k < cfg.tuser_bits_per_byte; k++)
			user_mask[b*cfg.tuser_bits_per_byte + k] = 1'b0;
	end
endfunction : get_checked_lanes


// Spec section 2.2: once TVALID is asserted, it must stay HIGH and the
// payload must not change until the handshake (TREADY == 1) occurs. Without
// TREADY on the interface every beat is a transfer in its first cycle, so
// there is nothing to check. TDATA and TUSER are compared on the lanes that
// get_checked_lanes() gives in the first cycle of the beat. The snapshots
// are 4-state, so a bit that is X in both cycles is not a change.
task ovip_axi_stream_monitor::stability_check();
	logic [`OVIP_AXI_STREAM_MAX_DATA_WIDTH-1:0] snap_tdata;
	logic [`OVIP_AXI_STREAM_MAX_STRB_WIDTH-1:0] snap_tstrb;
	logic [`OVIP_AXI_STREAM_MAX_KEEP_WIDTH-1:0] snap_tkeep;
	logic [`OVIP_AXI_STREAM_MAX_ID_WIDTH  -1:0] snap_tid;
	logic [`OVIP_AXI_STREAM_MAX_DEST_WIDTH-1:0] snap_tdest;
	logic [`OVIP_AXI_STREAM_MAX_USER_WIDTH-1:0] snap_tuser;
	logic snap_tlast;
	// the TDATA and TUSER bits to compare, from the first cycle of the beat
	ovip_axi_stream_data_t data_mask;
	ovip_axi_stream_user_t user_mask;

	if(!cfg.tready_en) return;
	forever
	begin
		@(vif.monitor_cb iff vif.monitor_cb.tvalid == 1'b1 && vif.monitor_cb.tready == 1'b0);
		get_checked_lanes(data_mask, user_mask);
		snap_tdata = vif.monitor_cb.tdata & data_mask;
		snap_tstrb = vif.monitor_cb.tstrb & STRB_MASK;
		snap_tkeep = vif.monitor_cb.tkeep & KEEP_MASK;
		snap_tlast = vif.monitor_cb.tlast;
		snap_tid   = vif.monitor_cb.tid   & ID_MASK;
		snap_tdest = vif.monitor_cb.tdest & DEST_MASK;
		snap_tuser = vif.monitor_cb.tuser & user_mask;

		// Walk forward until the handshake fires. Each intermediate cycle must
		// re-show the same TVALID and payload values.
		while(!vif.monitor_cb.tready)
		begin
			@(vif.monitor_cb);
			// A reset ends the transfer, and rst_monitor drops it. A transmitter
			// reset asynchronously drops TVALID on the same edge, and the two
			// threads wake on that edge in either order, so the reset comes first.
			if(vif.monitor_cb.aresetn !== 1'b1) break;
			if(vif.monitor_cb.tvalid !== 1'b1)
				`uvm_error({MESSAGE_TAG, "AXIS_MON/STABILITY"}, "TVALID deasserted before TREADY -- once HIGH, TVALID must stay HIGH until handshake (spec section 2.2).")
			if(cfg.tdata_width > 0 && snap_tdata !== (vif.monitor_cb.tdata & data_mask))
				`uvm_error({MESSAGE_TAG, "AXIS_MON/STABILITY"}, "TDATA changed between TVALID assertion and handshake.")
			if(cfg.tstrb_en && snap_tstrb !== (vif.monitor_cb.tstrb & STRB_MASK))
				`uvm_error({MESSAGE_TAG, "AXIS_MON/STABILITY"}, "TSTRB changed between TVALID assertion and handshake.")
			if(cfg.tkeep_en && snap_tkeep !== (vif.monitor_cb.tkeep & KEEP_MASK))
				`uvm_error({MESSAGE_TAG, "AXIS_MON/STABILITY"}, "TKEEP changed between TVALID assertion and handshake.")
			if(cfg.tlast_en && snap_tlast !== vif.monitor_cb.tlast)
				`uvm_error({MESSAGE_TAG, "AXIS_MON/STABILITY"}, "TLAST changed between TVALID assertion and handshake.")
			if(cfg.tid_en   && snap_tid   !== (vif.monitor_cb.tid & ID_MASK))
				`uvm_error({MESSAGE_TAG, "AXIS_MON/STABILITY"}, "TID changed between TVALID assertion and handshake.")
			if(cfg.tdest_en && snap_tdest !== (vif.monitor_cb.tdest & DEST_MASK))
				`uvm_error({MESSAGE_TAG, "AXIS_MON/STABILITY"}, "TDEST changed between TVALID assertion and handshake.")
			if(cfg.tuser_en && snap_tuser !== (vif.monitor_cb.tuser & user_mask))
				`uvm_error({MESSAGE_TAG, "AXIS_MON/STABILITY"}, "TUSER changed between TVALID assertion and handshake.")
		end
	end
endtask : stability_check


// Spec section 2.3: once TWAKEUP and TVALID are both HIGH in the same cycle,
// TWAKEUP must remain HIGH until TREADY is asserted. Without TREADY on the
// interface it counts as HIGH in that same cycle, so there is nothing to
// check.
task ovip_axi_stream_monitor::wakeup_check();
	if(!cfg.twakeup_en || !cfg.tready_en) return;
	forever
	begin
		@(vif.monitor_cb iff vif.monitor_cb.twakeup == 1'b1 && vif.monitor_cb.tvalid == 1'b1);
		while(!vif.monitor_cb.tready)
		begin
			@(vif.monitor_cb);
			// A reset ends the transfer, as in stability_check: a transmitter
			// reset asynchronously drops TWAKEUP on the same edge.
			if(vif.monitor_cb.aresetn !== 1'b1) break;
			if(vif.monitor_cb.twakeup !== 1'b1)
				`uvm_error({MESSAGE_TAG, "AXIS_MON/WAKEUP"}, "TWAKEUP deasserted before TREADY after going HIGH alongside TVALID (spec section 2.3).")
		end
	end
endtask : wakeup_check


// The main per-beat collector. Opens a new packet on the first handshake of a
// stream, appends each subsequent beat of that stream, checks byte qualifiers
// + packet-scope stability per beat, and closes/publishes the packet on TLAST
// (or on every beat when TLAST is not present, treating each transfer as one
// packet).
task ovip_axi_stream_monitor::bus_monitor();
	ovip_axi_stream_trans  tr;
	ovip_axi_stream_id_t   tid;
	ovip_axi_stream_dest_t tdest;
	stream_key_t           key;

	forever
	begin
		// A transfer. Without TREADY on the interface it counts as HIGH (spec
		// section 3.1.1): every cycle with TVALID HIGH is a transfer.
		@(vif.monitor_cb iff vif.monitor_cb.aresetn && vif.monitor_cb.tvalid && (!cfg.tready_en || vif.monitor_cb.tready));

		// The stream of this transfer, and its open packet.
		tid   = cfg.tid_en   ? (vif.monitor_cb.tid   & ID_MASK)   : '0;
		tdest = cfg.tdest_en ? (vif.monitor_cb.tdest & DEST_MASK) : '0;
		key   = {tid, tdest};

		if(open_tr.exists(key))
			tr = open_tr[key];
		else
		begin
			tr = ovip_axi_stream_trans::type_id::create("axis_tr");
			tr.bus_width           = cfg.tdata_width;
			tr.tuser_bits_per_byte = cfg.tuser_bits_per_byte;
			tr.tvalid_assert_time  = $realtime; // the first handshake, not the TVALID rise
			tr.first_beat_time     = $realtime;
			open_tr[key] = tr;
			analysis_port_cont.write(tr);
		end

		sample_beat_into(tr);
		check_byte_qualifiers(tr);
		check_continuous_null_bytes(tr);
		check_packet_scope_stability(tr);

		if(is_packet_done())
		begin
			tr.last_beat_time = $realtime;
			close_and_publish(tr);
			open_tr.delete(key);
			prev_tr = null;
		end
		else
			prev_tr = tr;
	end
endtask : bus_monitor


function void ovip_axi_stream_monitor::sample_beat_into(ovip_axi_stream_trans tr);
	ovip_axi_stream_data_t data_beat;
	ovip_axi_stream_keep_t keep_beat;
	ovip_axi_stream_strb_t strb_beat;
	ovip_axi_stream_user_t user_beat;

	if(cfg.tdata_width > 0)
		for(int b = 0; b < cfg.tdata_width; b++)
			data_beat[b*8 +: 8] = vif.monitor_cb.tdata[b*8 +: 8];
	tr.data_beats.push_back(data_beat);

	if(cfg.tkeep_en)
	begin
		for(int b = 0; b < cfg.tdata_width; b++) keep_beat[b] = vif.monitor_cb.tkeep[b];
		tr.keep_beats.push_back(keep_beat);
	end

	if(cfg.tstrb_en)
	begin
		for(int b = 0; b < cfg.tdata_width; b++) strb_beat[b] = vif.monitor_cb.tstrb[b];
		tr.strb_beats.push_back(strb_beat);
	end

	if(cfg.tuser_en)
	begin
		int total = cfg.tuser_bits_per_byte * cfg.tdata_width;
		for(int b = 0; b < total; b++) user_beat[b] = vif.monitor_cb.tuser[b];
		tr.user_beats.push_back(user_beat);
	end

	if(tr.burst_index == 0)
	begin
		// Take TID/TDEST/TWAKEUP as the packet's scope values from the first
		// beat, on the live bits (the trans's id/dest fields are MAX-width).
		if(cfg.tid_en)     tr.id     = vif.monitor_cb.tid   & ID_MASK;
		if(cfg.tdest_en)   tr.dest   = vif.monitor_cb.tdest & DEST_MASK;
		if(cfg.twakeup_en) tr.wakeup = vif.monitor_cb.twakeup;
	end

	tr.burst_index++;
endfunction : sample_beat_into


// Spec section 2.5.3: TKEEP=0 with TSTRB=1 is the reserved combination and
// must not be used.
function void ovip_axi_stream_monitor::check_byte_qualifiers(ovip_axi_stream_trans tr);
	if(!cfg.tkeep_en || !cfg.tstrb_en) return;
	for(int b = 0; b < cfg.tdata_width; b++)
	begin
		if(vif.monitor_cb.tkeep[b] === 1'b0 && vif.monitor_cb.tstrb[b] === 1'b1)
		begin
			`uvm_error({MESSAGE_TAG, "AXIS_MON/BYTE_QUAL"},
				$sformatf("Byte %0d has the reserved TKEEP=0 TSTRB=1 combination (spec section 2.5.3).", b))
			tr.monitor_error = 1;
		end
	end
endfunction : check_byte_qualifiers


// Spec section 3.3: with Continuous_Packets there are no null bytes within a
// packet. A transfer with TLAST LOW has every TKEEP bit HIGH. A transfer with
// TLAST HIGH has null bytes only above all its data bytes, so its TKEEP is a
// run of ones from bit 0 (or all zero: a last transfer with no data byte).
// Without TKEEP on the interface there is no null byte.
function void ovip_axi_stream_monitor::check_continuous_null_bytes(ovip_axi_stream_trans tr);
	logic [`OVIP_AXI_STREAM_MAX_KEEP_WIDTH-1:0] keep;
	if(!cfg.continuous_packets || !cfg.tkeep_en) return;
	keep = vif.monitor_cb.tkeep & KEEP_MASK;
	if(^keep === 1'bx) return; // the XZ check reports it
	if(!is_packet_done())
	begin
		if(keep != KEEP_MASK)
		begin
			`uvm_error({MESSAGE_TAG, "AXIS_MON/NULL_BYTE"},
				$sformatf("TKEEP=0x%0h with TLAST LOW. With continuous_packets every TKEEP bit must be HIGH in a transfer that is not the last of its packet (spec section 3.3).", keep))
			tr.monitor_error = 1;
		end
	end
	else if((keep & (keep + 1'b1)) != 0)
	begin
		`uvm_error({MESSAGE_TAG, "AXIS_MON/NULL_BYTE"},
			$sformatf("TKEEP=0x%0h with TLAST HIGH. With continuous_packets null bytes are permitted only above all the data bytes (spec section 3.3).", keep))
		tr.monitor_error = 1;
	end
endfunction : check_continuous_null_bytes


// Spec section 3.3: with Continuous_Packets, packets must not interleave, so
// TID and TDEST must not change in the transfer after one with TLAST LOW.
// `tr` is the packet of the current transfer. Without continuous_packets such
// a transfer is legal: it belongs to another stream (spec section 2.7).
function void ovip_axi_stream_monitor::check_packet_scope_stability(ovip_axi_stream_trans tr);
	if(!cfg.continuous_packets) return;
	if(prev_tr == null || prev_tr == tr) return;
	if(cfg.tid_en && prev_tr.id != tr.id)
	begin
		`uvm_error({MESSAGE_TAG, "AXIS_MON/PKT_SCOPE"},
			$sformatf("TID changed while TLAST was LOW (was 0x%0h, now 0x%0h). With continuous_packets, packets must not interleave (spec section 3.3).",
				prev_tr.id, tr.id))
		tr.monitor_error = 1;
	end
	if(cfg.tdest_en && prev_tr.dest != tr.dest)
	begin
		`uvm_error({MESSAGE_TAG, "AXIS_MON/PKT_SCOPE"},
			$sformatf("TDEST changed while TLAST was LOW (was 0x%0h, now 0x%0h). With continuous_packets, packets must not interleave (spec section 3.3).",
				prev_tr.dest, tr.dest))
		tr.monitor_error = 1;
	end
endfunction : check_packet_scope_stability


function bit ovip_axi_stream_monitor::is_packet_done();
	// With TLAST present, the packet ends when TLAST is sampled HIGH at the
	// handshake. With TLAST absent, every transfer is a one-beat packet.
	if(!cfg.tlast_en) return 1;
	return (vif.monitor_cb.tlast === 1'b1);
endfunction : is_packet_done


function void ovip_axi_stream_monitor::close_and_publish(ovip_axi_stream_trans tr);
	tr.got_last_beat        = 1;
	tr.transaction_finished = 1;
	`uvm_info({MESSAGE_TAG, "AXIS_MON"}, tr.convert2string(), UVM_LOW)
	analysis_port.write(tr);
	send_rsp_req(tr);
endfunction : close_and_publish


function void ovip_axi_stream_monitor::send_rsp_req(ovip_axi_stream_trans tr);
	if(cfg.agent_type != OVIP_AXI_STREAM_RECEIVER) return;
	if(cfg.is_active   != UVM_ACTIVE)              return;
	if(!has_rsp_req_reader)                        return;
	begin
		ovip_axi_stream_trans rsp = ovip_axi_stream_trans::type_id::create("rsp_req");
		rsp.copy(tr);
		pending_rsp_req.push_back(rsp);
	end
endfunction : send_rsp_req


task ovip_axi_stream_monitor::get(output ovip_axi_stream_trans tr);
	has_rsp_req_reader = 1;
	forever
	begin
		wait(pending_rsp_req.size());
		if(pending_rsp_req.size())
		begin
			tr = pending_rsp_req.pop_front();
			return;
		end
	end
endtask : get

`endif
