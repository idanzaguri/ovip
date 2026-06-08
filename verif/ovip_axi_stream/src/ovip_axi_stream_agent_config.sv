`ifndef OVIP_AXI_STREAM_AGENT_CONFIG__SV
`define OVIP_AXI_STREAM_AGENT_CONFIG__SV

class ovip_axi_stream_agent_config extends uvm_object;

	uvm_active_passive_enum     is_active;
	ovip_axi_stream_agent_type_t agent_type;
	ovip_axi_stream_protocol_t   protocol_type = OVIP_AXI_STREAM_PROTOCOL_AXI4S;

	// Optional short label prepended to this agent's monitor message IDs so
	// logs from multiple agents can be told apart (empty = no prefix). UVM's
	// hierarchical component name is shown on every report regardless.
	string agent_tag = "";

	// Signal widths. `tdata_width` is in *bytes* (matching the spec's preferred
	// unit); the live wire width is `tdata_width * 8` bits, gated by the MAX
	// in ovip_axi_stream_defines.sv.
	int tdata_width = 4;
	int tid_width   = 0;
	int tdest_width = 0;
	// TUSER is per-byte per the spec (one `tuser_bits_per_byte`-wide group per
	// byte of TDATA). Total wire width = tuser_bits_per_byte * tdata_width.
	int tuser_bits_per_byte = 0;

	// Per-signal presence on the interface. Mandatory signals (TVALID, ACLK,
	// ARESETn) are always live. Receiver-only agents naturally ignore the
	// transmitter-driven enables for everything except TREADY-pattern
	// generation.
	bit tready_en = 1; // recommended present even if the receiver never back-pressures
	bit tstrb_en  = 0;
	bit tkeep_en  = 0;
	bit tlast_en  = 0;
	bit tid_en    = 0;
	bit tdest_en  = 0;
	bit tuser_en  = 0;
	bit twakeup_en = 0; // AXI5-Stream only
	bit parity_en  = 0; // AXI5-Stream only; turns on TVALIDCHK/TREADYCHK/TDATACHK/... checks

	// Continuous_Packets profile (spec section 3.3): packets cannot interleave,
	// no null bytes within a packet, TSTRB must not be present. The monitor
	// enforces these when this is set.
	bit continuous_packets = 0;

	// Initiate every idle cycle with X-free defaults (helps adjacent assertions
	// and waveform readability). On by default.
	bit drive_reset_values_when_idle = 1;

	// Cap on the number of outstanding-but-unfinished transactions the monitor
	// will hold mid-packet before flagging an error. 0 = unlimited.
	int num_outstanding_transactions = 0;

	// Soft per-transaction timeout used by the monitor's incomplete-trans
	// watchdog (microseconds; 0 = no watchdog).
	int tr_timeout_us = 50;

	// Receiver-side default TREADY pattern. Same struct shape as ovip_axi's
	// ready patterns: cycles[$] holds per-level cycle counts, level alternates
	// with the index (even=0, odd=1), loop=1 wraps. Default = always ready.
	ovip_axi_stream_ready_pattern_t default_tready_pattern;

	`uvm_object_utils(ovip_axi_stream_agent_config)

	function new(string name = "ovip_axi_stream_agent_config");
		super.new(name);
		default_tready_pattern = '{cycles:'{0, 1}, loop:0};
	endfunction : new


	// Validates the configuration against the spec rules and the MAX caps.
	// Returns 1 if the config is consistent; emits uvm_error for each problem
	// and still returns 1 so the test sees them all in one shot.
	function bit check_config();

		// Width caps against the wire-level MAX defines.
		if(tdata_width * 8 > `OVIP_AXI_STREAM_MAX_DATA_WIDTH)
			`uvm_error("AXIS_CFG", $sformatf("tdata_width(%0dB = %0db) exceeds OVIP_AXI_STREAM_MAX_DATA_WIDTH(%0d)",
				tdata_width, tdata_width*8, `OVIP_AXI_STREAM_MAX_DATA_WIDTH))
		if(tid_width > `OVIP_AXI_STREAM_MAX_ID_WIDTH)
			`uvm_error("AXIS_CFG", $sformatf("tid_width(%0d) exceeds OVIP_AXI_STREAM_MAX_ID_WIDTH(%0d)",
				tid_width, `OVIP_AXI_STREAM_MAX_ID_WIDTH))
		if(tdest_width > `OVIP_AXI_STREAM_MAX_DEST_WIDTH)
			`uvm_error("AXIS_CFG", $sformatf("tdest_width(%0d) exceeds OVIP_AXI_STREAM_MAX_DEST_WIDTH(%0d)",
				tdest_width, `OVIP_AXI_STREAM_MAX_DEST_WIDTH))
		if(tuser_bits_per_byte * tdata_width > `OVIP_AXI_STREAM_MAX_USER_WIDTH)
			`uvm_error("AXIS_CFG", $sformatf("tuser total width (%0d*%0d = %0d) exceeds OVIP_AXI_STREAM_MAX_USER_WIDTH(%0d)",
				tuser_bits_per_byte, tdata_width, tuser_bits_per_byte*tdata_width, `OVIP_AXI_STREAM_MAX_USER_WIDTH))

		// Spec section 2.1: recommended TID_WIDTH and TDEST_WIDTH <= 8.
		if(tid_width   > 8) `uvm_warning("AXIS_CFG", $sformatf("tid_width(%0d) exceeds the spec-recommended maximum of 8",   tid_width))
		if(tdest_width > 8) `uvm_warning("AXIS_CFG", $sformatf("tdest_width(%0d) exceeds the spec-recommended maximum of 8", tdest_width))

		// Spec section 3.1.5: if TDATA is absent (tdata_width=0), TSTRB must also be absent.
		if(tdata_width == 0 && tstrb_en)
			`uvm_error("AXIS_CFG", "tstrb_en=1 is illegal when tdata_width=0 (spec section 3.1.5).")

		// Cross-signal presence: TSTRB requires TKEEP (the spec defines TSTRB
		// in terms of TKEEP). A TSTRB-only configuration would be ambiguous.
		if(tstrb_en && !tkeep_en)
			`uvm_warning("AXIS_CFG", "tstrb_en=1 without tkeep_en is unusual -- TSTRB's data/position distinction only makes sense when TKEEP qualifies the byte as transported.")

		// Protocol gating: AXI4-Stream forbids the AXI5 additions.
		if(protocol_type == OVIP_AXI_STREAM_PROTOCOL_AXI4S)
		begin
			if(twakeup_en) `uvm_error("AXIS_CFG", "twakeup_en=1 is only allowed for OVIP_AXI_STREAM_PROTOCOL_AXI5S.")
			if(parity_en)  `uvm_error("AXIS_CFG", "parity_en=1 is only allowed for OVIP_AXI_STREAM_PROTOCOL_AXI5S.")
		end

		// Continuous-packets profile (spec section 3.3): no TSTRB, no nulls, no interleave.
		if(continuous_packets && tstrb_en)
			`uvm_error("AXIS_CFG", "tstrb_en=1 is incompatible with continuous_packets=1 (spec section 3.3).")

		return 1;
	endfunction : check_config

endclass : ovip_axi_stream_agent_config

`endif
