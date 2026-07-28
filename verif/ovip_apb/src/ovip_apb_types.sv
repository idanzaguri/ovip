`ifndef OVIP_APB_TYPES__SV
`define OVIP_APB_TYPES__SV

	typedef bit [`OVIP_APB_MAX_ADDR_WIDTH-1 : 0] ovip_apb_addr_t;
	typedef bit [`OVIP_APB_MAX_DATA_WIDTH-1 : 0] ovip_apb_data_t;
	typedef bit [`OVIP_APB_MAX_STRB_WIDTH-1 : 0] ovip_apb_strb_t;
	typedef bit [2:0]                            ovip_apb_prot_t;

	// Two protocol issues supported by the VIP: APB3 (IHI 0024 issue B --
	// PREADY + PSLVERR) is the baseline; APB4 (issue C, v2.0) adds the
	// optional PSTRB write strobes and PPROT protection type. Selecting the
	// protocol gates which signals the agent is allowed to enable. The APB5
	// additions (PWAKEUP, user signals, parity check signals, PNSE/RME) are
	// intentionally out of scope for this VIP.
	typedef enum bit {
		OVIP_APB_PROTOCOL_APB3,
		OVIP_APB_PROTOCOL_APB4
	} ovip_apb_protocol_t;

	// Spec calls these Requester (the APB bridge that initiates transfers)
	// and Completer (the peripheral that responds). The Requester drives
	// every signal except PREADY/PRDATA/PSLVERR; the Completer drives only
	// those three. A passive agent of either flavor just snoops the wires.
	typedef enum bit {
		OVIP_APB_REQUESTER,
		OVIP_APB_COMPLETER
	} ovip_apb_agent_type_t;

	// PPROT bit meanings per spec section 3.5 (table 3-2).
	typedef enum int {
		OVIP_APB_PPROT_PRIVILEGED  = 0, // PPROT[0]: 0 = normal, 1 = privileged
		OVIP_APB_PPROT_NON_SECURE  = 1, // PPROT[1]: 0 = secure, 1 = non-secure
		OVIP_APB_PPROT_INSTRUCTION = 2  // PPROT[2]: 0 = data,   1 = instruction
	} ovip_apb_prot_bit_t;

	// Output format for ovip_apb_trans_logger. TABLE writes one aligned
	// column row per transaction (with a header); RAW writes convert2string().
	typedef enum bit {
		OVIP_APB_TRANS_LOG_TABLE,
		OVIP_APB_TRANS_LOG_RAW
	} ovip_apb_trans_log_format_e;

`endif
