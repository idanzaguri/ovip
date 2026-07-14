`ifndef OVIP_ACE_AGENT_CONFIG__SV
`define OVIP_ACE_AGENT_CONFIG__SV

class ovip_ace_agent_config extends ovip_axi_agent_config;

	// -----------------------------------------------------------------
	// Profile
	// -----------------------------------------------------------------
	// ACE vs ACE-Lite. In ACE-Lite mode the snoop channels, RACK/WACK,
	// AWUNIQUE and the RRESP[3:2] extension are all unused, and the
	// permitted AxSNOOP / AxDOMAIN combinations are restricted to the
	// IO-coherent subset (Tables D11-1, D11-2). The parent AXI fields
	// (protocol_type, bus_width, etc.) still apply on top of that.
	ovip_ace_profile_t profile = OVIP_ACE_PROFILE_ACE;

	// -----------------------------------------------------------------
	// Cache line size (D3.1.5)
	// -----------------------------------------------------------------
	// Minimum 16B, maximum min(2048B, AxLEN_max * bus_width_B).
	// Constrains cache-line-size transactions (D3.1.6).
	int unsigned cache_line_size = 64;

	// -----------------------------------------------------------------
	// Snoop channel widths
	// -----------------------------------------------------------------
	int acaddr_width = 64;
	int cddata_width = 128;

	// -----------------------------------------------------------------
	// Master-side capability advertisements
	// -----------------------------------------------------------------
	// External snoop filter support. When 1, the permitted end-state set
	// for cache-line transitions is tighter (D4.3).
	bit supports_snoop_filter = 0;

	// WriteEvict support -- requires the master to also provide the
	// AWUNIQUE signal (D2.1.2 footnote).
	bit supports_write_evict = 0;

	// -----------------------------------------------------------------
	// Master-side cache state tracking
	// -----------------------------------------------------------------
	// STATELESS (default): sequences drive whatever they want, no
	// self-checking against a cache model. TRACK: master driver maintains
	// per-line state and the monitor cross-checks observed state changes
	// against the legal end-state tables (D4 + D5). v0.1 ships STATELESS;
	// TRACK is wired up but the cache model itself is in CONTRIBUTING.md
	// wanted-features.
	ovip_ace_cache_model_t cache_model = OVIP_ACE_CACHE_MODEL_STATELESS;

	// -----------------------------------------------------------------
	// D12 interface-control tie-offs
	// -----------------------------------------------------------------
	// Constrain what the master is permitted to issue. The check_trans_validity
	// hooks in the master driver flag any sequence that asks for an outlawed
	// AxDOMAIN or a cache-maintenance transaction when broadcast is disabled.
	bit broadcast_inner_en       = 1;
	bit broadcast_outer_en       = 1;
	bit broadcast_cache_maint_en = 1;

	`uvm_object_utils(ovip_ace_agent_config)

	function new(string name = "ovip_ace_agent_config");
		super.new(name);
		// Default the AXI protocol_type to ACE so AXI-side checks treat
		// this as a coherent agent. Users can still override.
		protocol_type = OVIP_PROTOCOL_ACE;
	endfunction : new


	function bit check_config();

		// Reuse the AXI-side knob validation first.
		void'(super.check_config());

		// -- Cache line size constraints (D3.1.5)
		if(cache_line_size < 16)
			`uvm_error("ACE_CFG", $sformatf("cache_line_size(%0d) must be >= 16B", cache_line_size))
		if(cache_line_size > 2048)
			`uvm_error("ACE_CFG", $sformatf("cache_line_size(%0d) must be <= 2048B", cache_line_size))
		if(cache_line_size & (cache_line_size - 1))
			`uvm_error("ACE_CFG", $sformatf("cache_line_size(%0d) must be a power of two", cache_line_size))
		if(cache_line_size > 16 * int'(bus_width))
			`uvm_error("ACE_CFG", $sformatf(
				"cache_line_size(%0d) exceeds 16 * bus_width(%0d) = %0d (D3.1.5)",
				cache_line_size, int'(bus_width), 16*int'(bus_width)))

		// -- Snoop channel widths
		if(acaddr_width > `OVIP_ACE_MAX_ACADDR_WIDTH)
			`uvm_error("ACE_CFG", $sformatf(
				"acaddr_width(%0d) exceeds OVIP_ACE_MAX_ACADDR_WIDTH(%0d)",
				acaddr_width, `OVIP_ACE_MAX_ACADDR_WIDTH))
		if(cddata_width > `OVIP_ACE_MAX_CDDATA_WIDTH)
			`uvm_error("ACE_CFG", $sformatf(
				"cddata_width(%0d) exceeds OVIP_ACE_MAX_CDDATA_WIDTH(%0d)",
				cddata_width, `OVIP_ACE_MAX_CDDATA_WIDTH))

		// -- WriteEvict <-> AWUNIQUE coupling (D3.1.4 / Table D3-9)
		// A master that supports WriteEvict must drive AWUNIQUE. We track
		// the capability bit; the trans constraints enforce AWUNIQUE values
		// per Table D3-9 separately.

		// -- ACE-Lite restrictions
		if(profile == OVIP_ACE_PROFILE_ACE_LITE)
		begin
			if(supports_snoop_filter)
				`uvm_error("ACE_CFG", "ACE-Lite masters do not support snoop filters")
			if(supports_write_evict)
				`uvm_error("ACE_CFG", "ACE-Lite masters do not support WriteEvict")
			if(cache_model == OVIP_ACE_CACHE_MODEL_TRACK)
				`uvm_error("ACE_CFG", "ACE-Lite masters have no cache to track")
		end

		return 1;

	endfunction : check_config

endclass : ovip_ace_agent_config

`endif
