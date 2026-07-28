`ifndef OVIP_APB_AGENT_CONFIG__SV
`define OVIP_APB_AGENT_CONFIG__SV

class ovip_apb_agent_config extends uvm_object;

	uvm_active_passive_enum is_active;
	ovip_apb_agent_type_t   agent_type;
	ovip_apb_protocol_t     protocol_type = OVIP_APB_PROTOCOL_APB4;

	// Optional short label prepended to this agent's message IDs so logs from
	// multiple agents can be told apart (empty = no prefix). UVM's
	// hierarchical component name is shown on every report regardless.
	string agent_tag = "";

	// Signal widths. `data_width` is in *bytes* (matching the family
	// convention); the spec restricts the data buses to 8, 16, or 32 bits, so
	// the legal values are 1, 2, and 4. `addr_width` is in bits (up to 32).
	int addr_width = 32;
	int data_width = 4;

	// Per-signal presence on the interface. PSEL/PENABLE/PADDR/PWRITE/PWDATA/
	// PRDATA/PREADY are mandatory and always live. PSTRB and PPROT are APB4
	// additions; PSLVERR is optional from APB3 onward (a completer without it
	// is modeled by keeping the wire tied LOW).
	bit pstrb_en   = 0; // APB4 only
	bit pprot_en   = 0; // APB4 only
	bit pslverr_en = 1;

	// Drive X-free defaults on every idle cycle (helps adjacent assertions
	// and waveform readability). On by default.
	bit drive_reset_values_when_idle = 1;

	// Completer-side default wait-state range, used by the base slave
	// sequence when the test doesn't override its knobs.
	int unsigned default_min_wait_states = 0;
	int unsigned default_max_wait_states = 3;

	// When enabled, the agent instantiates an ovip_apb_trans_logger that
	// writes one line per completed transaction. `trans_log_file` empty =
	// "<agent_name>_trans.log"; `trans_log_combined_file` non-empty = also
	// append into a file shared by every agent given the same path.
	bit enable_trans_log = 0;
	string trans_log_file = "";
	string trans_log_combined_file = "";
	ovip_apb_trans_log_format_e trans_log_format = OVIP_APB_TRANS_LOG_TABLE;

	`uvm_object_utils(ovip_apb_agent_config)

	function new(string name = "ovip_apb_agent_config");
		super.new(name);
	endfunction : new


	// Validates the configuration against the spec rules and the MAX caps.
	// Emits uvm_error for each problem and still returns 1 so the test sees
	// them all in one shot.
	function bit check_config();

		// Width caps against the wire-level MAX defines.
		if(addr_width <= 0 || addr_width > `OVIP_APB_MAX_ADDR_WIDTH)
			`uvm_error("APB_CFG", $sformatf("addr_width(%0d) outside the legal range 1..%0d (spec section 2.1: PADDR can be up to 32 bits)",
				addr_width, `OVIP_APB_MAX_ADDR_WIDTH))

		// Spec section 2.1.2: the data buses can be 8, 16, or 32 bits wide.
		if(!(data_width inside {1, 2, 4}))
			`uvm_error("APB_CFG", $sformatf("data_width(%0dB) is illegal -- the spec allows 8, 16, or 32-bit data buses (data_width of 1, 2, or 4)",
				data_width))
		if(data_width * 8 > `OVIP_APB_MAX_DATA_WIDTH)
			`uvm_error("APB_CFG", $sformatf("data_width(%0dB = %0db) exceeds OVIP_APB_MAX_DATA_WIDTH(%0d)",
				data_width, data_width*8, `OVIP_APB_MAX_DATA_WIDTH))

		// Protocol gating: PSTRB and PPROT are APB4 (issue C) additions.
		if(protocol_type == OVIP_APB_PROTOCOL_APB3)
		begin
			if(pstrb_en) `uvm_error("APB_CFG", "pstrb_en=1 is only allowed for OVIP_APB_PROTOCOL_APB4 (PSTRB was added in issue C).")
			if(pprot_en) `uvm_error("APB_CFG", "pprot_en=1 is only allowed for OVIP_APB_PROTOCOL_APB4 (PPROT was added in issue C).")
		end

		return 1;
	endfunction : check_config

endclass : ovip_apb_agent_config

`endif
