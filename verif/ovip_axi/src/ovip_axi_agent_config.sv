`ifndef OVIP_AXI_CONFIG__SV
`define OVIP_AXI_CONFIG__SV

class ovip_axi_agent_config extends uvm_object;

	uvm_active_passive_enum is_active;
	ovip_agent_dir_t agent_type;

	// Optional short label prepended to this agent's monitor message IDs so logs from
	// multiple agents can be told apart (empty = no prefix). UVM's hierarchical
	// component name is shown on every report regardless of this.
	string agent_tag = "";
	ovip_axi_protocol_t protocol_type;
	ovip_axi_interface_t interface_type;

	// signals width
	ovip_axi_bus_width_t bus_width;
	int addr_width;

	int wr_id_width = 8;
	int rd_id_width = 8;

	int len_width  = 8;
	int size_width = 3;

	int awuser_width = 0;
	int wuser_width  = 0;
	int buser_width  = 0;
	int aruser_width = 0;
	int ruser_width  = 0;

	bit awlock_en;
	bit awcache_en;
	bit awprot_en;
	bit awqos_en;
	bit awregion_en;
	bit arlock_en;
	bit arcache_en;
	bit arprot_en;
	bit arqos_en;
	bit arregion_en;


	bit drive_reset_values_when_idle = 1;

	int wr_out_of_order_depth = 1;
	int wr_resp_out_of_order_depth = 1;
	int rd_out_of_order_depth = 1;
	int wr_interleave_depth = 1;
	int rd_interleave_depth = 1;

	ovip_axi_scheduling_algorithm_t wr_scheduling_alg;
	ovip_axi_scheduling_algorithm_t rd_scheduling_alg;

	int num_outstanding_transactions    = 0;
	int num_outstanding_wr_transactions = 0;
	int num_outstanding_rd_transactions = 0;

	int tr_timeout_us = 50;

	bit auto_byte_lanes_alignment = 1;

	// When set, suppress the "delayed slave sequence" warning. Enable this if the
	// slave sequence intentionally consumes simulation time before responding.
	bit suppress_delayed_slave_seq_warning = 0;

	// -----------------------------------------------------------------
	// Transaction logging
	// -----------------------------------------------------------------
	// When enabled, the agent instantiates an ovip_axi_trans_logger that writes
	// one line per completed transaction (with phase timestamps) to a text file.
	// Works on active and passive agents.
	bit enable_trans_log = 0;
	// Per-agent log path. Empty => "<agent_tag or agent leaf name>_trans.log".
	string trans_log_file = "";
	// When non-empty, ALSO append to this shared file. Give the same path to
	// several agents to get a single interleaved (time-ordered) combined log.
	string trans_log_combined_file = "";
	// Line format for both files (TABLE columns or RAW convert2string).
	ovip_axi_trans_log_format_e trans_log_format = OVIP_AXI_TRANS_LOG_TABLE;
	


	ovip_axi_ready_pattern_t default_arready_pattern;
	ovip_axi_ready_pattern_t default_awready_pattern;
	ovip_axi_ready_pattern_t default_wready_pattern;
	ovip_axi_ready_pattern_t default_rready_pattern;
	ovip_axi_ready_pattern_t default_bready_pattern;

	`uvm_object_utils(ovip_axi_agent_config)

	function new(string name = "ovip_axi_agent_config");
		super.new(name);
		// Default: always ready (no backpressure).
		default_arready_pattern = '{cycles:'{0, 1}, loop:0};
		default_awready_pattern = '{cycles:'{0, 1}, loop:0};
		default_wready_pattern  = '{cycles:'{0, 1}, loop:0};
		default_rready_pattern  = '{cycles:'{0, 1}, loop:0};
		default_bready_pattern  = '{cycles:'{0, 1}, loop:0};
	endfunction : new


	function bit check_config();

		if(protocol_type != OVIP_PROTOCOL_AXI3)
		begin
			if(agent_type == OVIP_MASTER_AGENT && wr_interleave_depth != 1)
				`uvm_error("AXI_CFG", $sformatf("wr_interleave_depth(%0d) must be 1 for protocol_type=%s",wr_interleave_depth,protocol_type.name()))
			if(agent_type == OVIP_MASTER_AGENT && wr_out_of_order_depth != 1)
				`uvm_error("AXI_CFG", $sformatf("wr_out_of_order_depth(%0d) must be 1 for protocol_type=%s",wr_out_of_order_depth,protocol_type.name()))
		end
		if(protocol_type == OVIP_PROTOCOL_AXI3)
		begin
			// wr_id_width should be 0
			// len_width should be 4
		end

		if(protocol_type == OVIP_PROTOCOL_AXI4_LITE)
		begin
			if(wr_out_of_order_depth      != 1) `uvm_error("AXI_CFG", $sformatf("wr_out_of_order_depth(%0d) must be 1 on AXI-Lite", wr_out_of_order_depth))
			if(wr_resp_out_of_order_depth != 1) `uvm_error("AXI_CFG", $sformatf("wr_resp_out_of_order_depth(%0d) must be 1 on AXI-Lite", wr_resp_out_of_order_depth))
			if(wr_interleave_depth        != 1) `uvm_error("AXI_CFG", $sformatf("wr_interleave_depth(%0d) must be 1 on AXI-Lite", wr_interleave_depth))
			if(rd_out_of_order_depth      != 1) `uvm_error("AXI_CFG", $sformatf("rd_out_of_order_depth(%0d) must be 1 on AXI-Lite", rd_out_of_order_depth))
			if(rd_interleave_depth        != 1) `uvm_error("AXI_CFG", $sformatf("rd_interleave_depth(%0d) must be 1 on AXI-Lite", rd_interleave_depth))
		end


		// signals width
		if(bus_width*8 > `OVIP_AXI_MAX_DATA_WIDTH)
			`uvm_error("AXI_CFG", $sformatf("bus_width(%s) exceeds maximum allowed value - `OVIP_AXI_MAX_DATA_WIDTH(%0d)[bits]", bus_width.name(), `OVIP_AXI_MAX_DATA_WIDTH))
		if(addr_width > `OVIP_AXI_MAX_ADDR_WIDTH)
			`uvm_error("AXI_CFG", $sformatf("addr_width(%0d) exceeds maximum allowed value - `OVIP_AXI_MAX_ADDR_WIDTH(%0d)", addr_width, `OVIP_AXI_MAX_ADDR_WIDTH))
		if(wr_id_width > `OVIP_AXI_MAX_ID_WIDTH)
			`uvm_error("AXI_CFG", $sformatf("wr_id_width(%0d) exceeds maximum allowed value - `OVIP_AXI_MAX_ID_WIDTH(%0d)", wr_id_width, `OVIP_AXI_MAX_ID_WIDTH))
		if(rd_id_width > `OVIP_AXI_MAX_ID_WIDTH)
			`uvm_error("AXI_CFG", $sformatf("rd_id_width(%0d) exceeds maximum allowed value - `OVIP_AXI_MAX_ID_WIDTH(%0d)", rd_id_width, `OVIP_AXI_MAX_ID_WIDTH))
		if(awuser_width > `OVIP_AXI_MAX_USER_WIDTH)
			`uvm_error("AXI_CFG", $sformatf("awuser_width(%0d) exceeds maximum allowed value - `OVIP_AXI_MAX_USER_WIDTH(%0d)", awuser_width, `OVIP_AXI_MAX_USER_WIDTH))
		if(wuser_width > `OVIP_AXI_MAX_USER_WIDTH)
			`uvm_error("AXI_CFG", $sformatf("wuser_width(%0d) exceeds maximum allowed value - `OVIP_AXI_MAX_USER_WIDTH(%0d)", wuser_width, `OVIP_AXI_MAX_USER_WIDTH))
		if(buser_width > `OVIP_AXI_MAX_USER_WIDTH)
			`uvm_error("AXI_CFG", $sformatf("buser_width(%0d) exceeds maximum allowed value - `OVIP_AXI_MAX_USER_WIDTH(%0d)", buser_width, `OVIP_AXI_MAX_USER_WIDTH))
		if(aruser_width > `OVIP_AXI_MAX_USER_WIDTH)
			`uvm_error("AXI_CFG", $sformatf("aruser_width(%0d) exceeds maximum allowed value - `OVIP_AXI_MAX_USER_WIDTH(%0d)", aruser_width, `OVIP_AXI_MAX_USER_WIDTH))
		if(ruser_width > `OVIP_AXI_MAX_USER_WIDTH)
			`uvm_error("AXI_CFG", $sformatf("ruser_width(%0d) exceeds maximum allowed value - `OVIP_AXI_MAX_USER_WIDTH(%0d)", ruser_width, `OVIP_AXI_MAX_USER_WIDTH))
		if(len_width  > 8)
			`uvm_error("AXI_CFG", $sformatf("len_width (%0d) exceeds maximum allowed value -  8", len_width))
		if(size_width > 4)
			`uvm_error("AXI_CFG", $sformatf("size_width(%0d) exceeds maximum allowed value -  4 (3 is spec-compliant; 4 is out-of-spec for 256B/512B beats)", size_width))
		// Auto-bump size_width when bus_width requires AxSIZE > 3'b111 (out-of-spec).
		if(int'(bus_width) > 128 && size_width < 4)
		begin
			`uvm_info("AXI_CFG", $sformatf("bus_width(%s) requires 4-bit AxSIZE; auto-bumping size_width from %0d to 4", bus_width.name(), size_width), UVM_LOW)
			size_width = 4;
		end


		return 1;

	endfunction : check_config
endclass : ovip_axi_agent_config


`endif
