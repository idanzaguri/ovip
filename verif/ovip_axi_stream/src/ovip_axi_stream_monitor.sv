`ifndef OVIP_AXI_STREAM_MONITOR__SV
`define OVIP_AXI_STREAM_MONITOR__SV

// AXI-Stream channel monitor. Samples every transfer, accumulates beats into
// an in-progress packet (closed when TLAST is sampled or, with TLAST disabled,
// after every single transfer), publishes completed packets on
// `analysis_port`, and runs the protocol checks inline:
//   - XZ on TVALID/TREADY at every clock; XZ on payload while TVALID HIGH
//   - TVALID and payload must stay stable from the cycle TVALID is asserted
//     until the handshake fires (TVALID && TREADY)
//   - TVALID must be LOW while ARESETn is asserted; first TVALID after reset
//     deassertion can be no earlier than the second rising ACLK edge
//   - TKEEP = 0 with TSTRB = 1 is the reserved byte-qualifier combination
//   - TID and TDEST must not change within a packet
//   - AXI5: TWAKEUP, once asserted with TVALID, must stay HIGH until TREADY
//   - AXI5: per-byte odd parity on every signal when parity_en is set
class ovip_axi_stream_monitor extends uvm_monitor;

	virtual ovip_axi_stream_agent_if vif;
	ovip_axi_stream_agent_config     cfg;

	uvm_analysis_port#(ovip_axi_stream_trans) analysis_port_cont;
	uvm_analysis_port#(ovip_axi_stream_trans) analysis_port;

	// Optional UVM blocking-get port the receiver-side slave sequence taps to
	// fetch newly-monitored "request" packets (TREADY pattern updates, etc.).
	// Mirrors the ovip_axi convention.
	uvm_blocking_get_imp#(ovip_axi_stream_trans, ovip_axi_stream_monitor) response_req_port;
	protected ovip_axi_stream_trans pending_rsp_req[$];

	// Per-agent prefix on the AXIS_MON message ID. Empty by default; set from
	// cfg.agent_tag in build_phase.
	string MESSAGE_TAG;

	// Current in-progress packet, kept across handshakes until TLAST.
	protected ovip_axi_stream_trans current_tr;

	`uvm_component_utils(ovip_axi_stream_monitor)

	function new(string name = "ovip_axi_stream_monitor", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	extern virtual function void build_phase(uvm_phase phase);
	extern virtual task          run_phase(uvm_phase phase);

	// Reset gates and exit-from-reset rule.
	extern virtual task rst_monitor();
	extern virtual task tvalid_low_during_reset_check();
	extern virtual task exit_from_reset_check();

	// Per-cycle XZ on the handshake and (when TVALID is HIGH) on the payload.
	extern virtual task xz_handshake_check();
	extern virtual task xz_payload_check();
	extern virtual function void check_payload_xz();

	// Stability of TVALID + payload between assertion and handshake.
	extern virtual task stability_check();

	// AXI5 wake-up rule.
	extern virtual task wakeup_check();

	// Bus monitor + supporting helpers.
	extern virtual task          bus_monitor();
	extern virtual function void sample_beat_into(ovip_axi_stream_trans tr);
	extern virtual function void check_byte_qualifiers(ovip_axi_stream_trans tr);
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


task ovip_axi_stream_monitor::run_phase(uvm_phase phase);
	`uvm_info({MESSAGE_TAG, "AXIS_MON"}, "monitor up; waiting for reset deassertion", UVM_HIGH)

	// Run the reset-tied checkers immediately so the during-reset and
	// exit-from-reset rules are observed even before the bus comes alive.
	fork tvalid_low_during_reset_check(); join_none

	forever
	begin
		@(vif.monitor_cb iff vif.monitor_cb.aresetn);
		`uvm_info({MESSAGE_TAG, "AXIS_MON"}, "reset deasserted", UVM_HIGH)

		`BEGIN_FIRST_OF
			rst_monitor();
			fork
				exit_from_reset_check();
				xz_handshake_check();
				xz_payload_check();
				stability_check();
				wakeup_check();
				bus_monitor();
			join
		`END_FIRST_OF
	end
endtask : run_phase


task ovip_axi_stream_monitor::rst_monitor();
	@(vif.monitor_cb iff vif.monitor_cb.aresetn == 1'b0);
	`uvm_info({MESSAGE_TAG, "AXIS_MON"}, "reset asserted", UVM_LOW)
	// Drop any half-collected packet so it doesn't survive the reset.
	current_tr = null;
	pending_rsp_req.delete();
endtask : rst_monitor


task ovip_axi_stream_monitor::tvalid_low_during_reset_check();
	forever
	begin
		@(vif.monitor_cb iff vif.monitor_cb.aresetn == 1'b0);
		// Spec section 2.8.2: TVALID must be LOW while ARESETn is asserted.
		// We flag only TVALID == 1; X during the first few sim cycles is the
		// usual pre-drive state, not a spec violation.
		if(vif.monitor_cb.tvalid === 1'b1)
			`uvm_error({MESSAGE_TAG, "AXIS_MON/RESET"}, "TVALID asserted while ARESETn is asserted (spec section 2.8.2).")
		@(vif.monitor_cb iff vif.monitor_cb.aresetn == 1'b1);
	end
endtask : tvalid_low_during_reset_check


// Spec section 2.8.2 (figure 2-4): TVALID must still be LOW at the very edge
// where ARESETn is first sampled HIGH (T1 in the figure); it is allowed to
// rise on the next edge (T2). This task is forked right at that T1 edge by
// run_phase, so we just check TVALID at the current edge -- no @cb here.
task ovip_axi_stream_monitor::exit_from_reset_check();
	if(vif.monitor_cb.tvalid !== 1'b0)
		`uvm_error({MESSAGE_TAG, "AXIS_MON/RESET"}, "TVALID asserted on the same ACLK edge where ARESETn was first sampled HIGH -- spec section 2.8.2 requires TVALID to remain LOW for that edge.")
endtask : exit_from_reset_check


task ovip_axi_stream_monitor::xz_handshake_check();
	forever
	begin
		@(vif.monitor_cb);
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


// We check XOR-reduction over the *full* MAX-width signal even though only
// the bottom (cfg.<width>*8) bits are live -- the drivers leave the unused
// upper bits at 0 by construction (drive_beat assigns from trans fields
// whose upper bytes are zero), so any X anywhere on the wire is a real bug.
// SV-spec-wise variable bit-slice ranges (e.g. `[cfg.width*8-1:0]`) are not
// portable through Questa's vopt pass, so we lean on the full-width form.
function void ovip_axi_stream_monitor::check_payload_xz();
	if(cfg.tdata_width > 0)
		if(^vif.monitor_cb.tdata === 1'bx)
			`uvm_error({MESSAGE_TAG, "AXIS_MON/XZ_CHECK"}, "TDATA contains X's or Z's while TVALID is HIGH.")
	if(cfg.tstrb_en && cfg.tdata_width > 0)
		if(^vif.monitor_cb.tstrb === 1'bx)
			`uvm_error({MESSAGE_TAG, "AXIS_MON/XZ_CHECK"}, "TSTRB contains X's or Z's while TVALID is HIGH.")
	if(cfg.tkeep_en && cfg.tdata_width > 0)
		if(^vif.monitor_cb.tkeep === 1'bx)
			`uvm_error({MESSAGE_TAG, "AXIS_MON/XZ_CHECK"}, "TKEEP contains X's or Z's while TVALID is HIGH.")
	if(cfg.tlast_en) `OVIP_AXI_STREAM_MON_XZ_CHECK(tlast, tlast)
	if(cfg.tid_en   && cfg.tid_width   > 0)
		if(^vif.monitor_cb.tid === 1'bx)
			`uvm_error({MESSAGE_TAG, "AXIS_MON/XZ_CHECK"}, "TID contains X's or Z's while TVALID is HIGH.")
	if(cfg.tdest_en && cfg.tdest_width > 0)
		if(^vif.monitor_cb.tdest === 1'bx)
			`uvm_error({MESSAGE_TAG, "AXIS_MON/XZ_CHECK"}, "TDEST contains X's or Z's while TVALID is HIGH.")
	if(cfg.tuser_en && cfg.tuser_bits_per_byte > 0 && cfg.tdata_width > 0)
		if(^vif.monitor_cb.tuser === 1'bx)
			`uvm_error({MESSAGE_TAG, "AXIS_MON/XZ_CHECK"}, "TUSER contains X's or Z's while TVALID is HIGH.")
	if(cfg.twakeup_en) `OVIP_AXI_STREAM_MON_XZ_CHECK(twakeup, twakeup)
endfunction : check_payload_xz


// Spec section 2.2: once TVALID is asserted, it must stay HIGH and the
// payload must not change until the handshake (TREADY == 1) occurs.
task ovip_axi_stream_monitor::stability_check();
	logic [`OVIP_AXI_STREAM_MAX_DATA_WIDTH-1:0] snap_tdata;
	logic [`OVIP_AXI_STREAM_MAX_STRB_WIDTH-1:0] snap_tstrb;
	logic [`OVIP_AXI_STREAM_MAX_KEEP_WIDTH-1:0] snap_tkeep;
	logic [`OVIP_AXI_STREAM_MAX_ID_WIDTH  -1:0] snap_tid;
	logic [`OVIP_AXI_STREAM_MAX_DEST_WIDTH-1:0] snap_tdest;
	logic [`OVIP_AXI_STREAM_MAX_USER_WIDTH-1:0] snap_tuser;
	logic snap_tlast;

	forever
	begin
		@(vif.monitor_cb iff vif.monitor_cb.tvalid == 1'b1 && vif.monitor_cb.tready == 1'b0);
		snap_tdata = vif.monitor_cb.tdata;
		snap_tstrb = vif.monitor_cb.tstrb;
		snap_tkeep = vif.monitor_cb.tkeep;
		snap_tlast = vif.monitor_cb.tlast;
		snap_tid   = vif.monitor_cb.tid;
		snap_tdest = vif.monitor_cb.tdest;
		snap_tuser = vif.monitor_cb.tuser;

		// Walk forward until the handshake fires. Each intermediate cycle must
		// re-show the same TVALID and payload values.
		while(!vif.monitor_cb.tready)
		begin
			@(vif.monitor_cb);
			if(vif.monitor_cb.tvalid !== 1'b1)
				`uvm_error({MESSAGE_TAG, "AXIS_MON/STABILITY"}, "TVALID deasserted before TREADY -- once HIGH, TVALID must stay HIGH until handshake (spec section 2.2).")
			if(cfg.tdata_width > 0 && snap_tdata !== vif.monitor_cb.tdata)
				`uvm_error({MESSAGE_TAG, "AXIS_MON/STABILITY"}, "TDATA changed between TVALID assertion and handshake.")
			if(cfg.tstrb_en && snap_tstrb !== vif.monitor_cb.tstrb)
				`uvm_error({MESSAGE_TAG, "AXIS_MON/STABILITY"}, "TSTRB changed between TVALID assertion and handshake.")
			if(cfg.tkeep_en && snap_tkeep !== vif.monitor_cb.tkeep)
				`uvm_error({MESSAGE_TAG, "AXIS_MON/STABILITY"}, "TKEEP changed between TVALID assertion and handshake.")
			if(cfg.tlast_en && snap_tlast !== vif.monitor_cb.tlast)
				`uvm_error({MESSAGE_TAG, "AXIS_MON/STABILITY"}, "TLAST changed between TVALID assertion and handshake.")
			if(cfg.tid_en   && snap_tid   !== vif.monitor_cb.tid)
				`uvm_error({MESSAGE_TAG, "AXIS_MON/STABILITY"}, "TID changed between TVALID assertion and handshake.")
			if(cfg.tdest_en && snap_tdest !== vif.monitor_cb.tdest)
				`uvm_error({MESSAGE_TAG, "AXIS_MON/STABILITY"}, "TDEST changed between TVALID assertion and handshake.")
			if(cfg.tuser_en && snap_tuser !== vif.monitor_cb.tuser)
				`uvm_error({MESSAGE_TAG, "AXIS_MON/STABILITY"}, "TUSER changed between TVALID assertion and handshake.")
		end
	end
endtask : stability_check


// Spec section 2.3: once TWAKEUP and TVALID are both HIGH in the same cycle,
// TWAKEUP must remain HIGH until TREADY is asserted.
task ovip_axi_stream_monitor::wakeup_check();
	if(!cfg.twakeup_en) return;
	forever
	begin
		@(vif.monitor_cb iff vif.monitor_cb.twakeup == 1'b1 && vif.monitor_cb.tvalid == 1'b1);
		while(!vif.monitor_cb.tready)
		begin
			@(vif.monitor_cb);
			if(vif.monitor_cb.twakeup !== 1'b1)
				`uvm_error({MESSAGE_TAG, "AXIS_MON/WAKEUP"}, "TWAKEUP deasserted before TREADY after going HIGH alongside TVALID (spec section 2.3).")
		end
	end
endtask : wakeup_check


// The main per-beat collector. Opens a new packet on the first handshake,
// appends each subsequent beat's payload, checks byte qualifiers + packet-
// scope stability per beat, and closes/publishes the packet on TLAST (or on
// every beat when TLAST is not present, treating each transfer as one packet).
task ovip_axi_stream_monitor::bus_monitor();
	forever
	begin
		@(vif.monitor_cb iff vif.monitor_cb.aresetn && vif.monitor_cb.tvalid && vif.monitor_cb.tready);

		if(current_tr == null)
		begin
			current_tr = ovip_axi_stream_trans::type_id::create("axis_tr");
			current_tr.bus_width           = cfg.tdata_width;
			current_tr.tuser_bits_per_byte = cfg.tuser_bits_per_byte;
			current_tr.tvalid_assert_time  = $time; // best-effort -- exact assert time tracked by stability_check
			current_tr.first_beat_time     = $time;
			analysis_port_cont.write(current_tr);
		end

		sample_beat_into(current_tr);
		check_byte_qualifiers(current_tr);
		check_packet_scope_stability(current_tr);

		if(is_packet_done())
		begin
			current_tr.last_beat_time = $time;
			close_and_publish(current_tr);
			current_tr = null;
		end
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
		// beat. The trans's id/dest fields are MAX-width typedefs, matching
		// the wire width directly -- no slicing needed.
		if(cfg.tid_en)     tr.id     = vif.monitor_cb.tid;
		if(cfg.tdest_en)   tr.dest   = vif.monitor_cb.tdest;
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


// Spec section 2.6: within a packet, all transfers must share the same TID
// and TDEST. We saved the first beat's values into the trans; compare on
// every subsequent beat.
function void ovip_axi_stream_monitor::check_packet_scope_stability(ovip_axi_stream_trans tr);
	if(tr.burst_index <= 1) return; // first beat is the reference
	if(cfg.tid_en   && tr.id   !== vif.monitor_cb.tid)
	begin
		`uvm_error({MESSAGE_TAG, "AXIS_MON/PKT_SCOPE"},
			$sformatf("TID changed mid-packet (was 0x%0h, now 0x%0h). Packets must keep TID stable until TLAST (spec section 2.6).",
				tr.id, vif.monitor_cb.tid))
		tr.monitor_error = 1;
	end
	if(cfg.tdest_en && tr.dest !== vif.monitor_cb.tdest)
	begin
		`uvm_error({MESSAGE_TAG, "AXIS_MON/PKT_SCOPE"},
			$sformatf("TDEST changed mid-packet (was 0x%0h, now 0x%0h). Packets must keep TDEST stable until TLAST (spec section 2.6).",
				tr.dest, vif.monitor_cb.tdest))
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
	begin
		ovip_axi_stream_trans rsp = ovip_axi_stream_trans::type_id::create("rsp_req");
		rsp.copy(tr);
		pending_rsp_req.push_back(rsp);
	end
endfunction : send_rsp_req


task ovip_axi_stream_monitor::get(output ovip_axi_stream_trans tr);
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
