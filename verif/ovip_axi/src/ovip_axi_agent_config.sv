`ifndef OVIP_AXI_CONFIG__SV
`define OVIP_AXI_CONFIG__SV

class ovip_axi_agent_config extends uvm_object;

	uvm_active_passive_enum is_active;
	ovip_agent_dir_t agent_type;

	// Optional short label prepended to this agent's monitor message IDs so logs from
	// multiple agents can be told apart (empty = no prefix). UVM's hierarchical
	// component name is shown on every report regardless of this.
	string agent_tag = "";
	ovip_axi_protocol_t protocol_type = OVIP_PROTOCOL_AXI3;
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

	// Master only, AXI3 only. On AXI3 the first W beat of each write follows
	// the AW order (spec A5.3.3), and the master starts the data of its
	// writes in that order. When set, the master may start the data of a
	// later AW first, inside its window of wr_out_of_order_depth writes. That
	// traffic is illegal: the bit is there to inject the error, and a monitor
	// reports it as AXI_MON/WDATA_OOO. Off by default.
	bit allow_wdata_out_of_aw_order = 0;

	int num_outstanding_transactions    = 0;
	int num_outstanding_wr_transactions = 0;
	int num_outstanding_rd_transactions = 0;

	int tr_timeout_us = 50;

	bit auto_byte_lanes_alignment = 1;

	// Master only. AXI leaves a WDATA byte whose WSTRB bit is low undefined.
	// When set, the driver puts a random value on every such byte, inside or
	// outside the beat's byte window, instead of zero. A slave or interconnect
	// that uses those bytes then shows it. Off by default.
	bit randomize_unstrobed_wdata = 0;

	// Slave only. AXI leaves an RDATA byte lane that a narrow or unaligned beat
	// does not use undefined. When set, the driver puts a random value on every
	// such lane instead of zero. A master or interconnect that uses those lanes
	// then shows it. AXI-Lite reads use the whole bus, so it does nothing there.
	// Off by default.
	bit randomize_unused_rdata = 0;

	// Monitor. AXI leaves a WDATA byte whose WSTRB bit is low undefined, and an
	// RDATA byte lane that a narrow or unaligned beat does not use. The X/Z
	// check and the stability check of the monitor skip these bytes. When set,
	// both checks cover the whole data bus. Off by default.
	bit check_undefined_data_lanes = 0;

	// Master and slave. AXI leaves a channel's payload undefined while its VALID
	// is low. When set, the driver puts random values on it (AW, W and AR at a
	// master; B and R at a slave) at reset and after every handshake, instead
	// of zero or the last value. An interface that takes a field before its
	// handshake then shows it. Off by default.
	bit randomize_idle_payload = 0;

	// Slave only. AXI lets a slave wait for WVALID before it asserts AWREADY.
	// When set, AWREADY follows its ready pattern only while a write burst has
	// offered WVALID ahead of its AW: WVALID high now, or W beats the slave
	// took before the AW. A master that waits for AWREADY before WVALID, which
	// AXI forbids, then hangs. Read at the start of the run. Off by default.
	bit awready_waits_for_wvalid = 0;

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


	// copy() and clone() carry every field.
	virtual function void do_copy(uvm_object rhs);
		ovip_axi_agent_config c;
		if(!$cast(c, rhs)) `uvm_fatal("CAST_FAILED", "ovip_axi_agent_config::do_copy: rhs is not an ovip_axi_agent_config")
		super.do_copy(rhs);
		is_active                          = c.is_active;
		agent_type                         = c.agent_type;
		agent_tag                          = c.agent_tag;
		protocol_type                      = c.protocol_type;
		interface_type                     = c.interface_type;
		bus_width                          = c.bus_width;
		addr_width                         = c.addr_width;
		wr_id_width                        = c.wr_id_width;
		rd_id_width                        = c.rd_id_width;
		len_width                          = c.len_width;
		size_width                         = c.size_width;
		awuser_width                       = c.awuser_width;
		wuser_width                        = c.wuser_width;
		buser_width                        = c.buser_width;
		aruser_width                       = c.aruser_width;
		ruser_width                        = c.ruser_width;
		awlock_en                          = c.awlock_en;
		awcache_en                         = c.awcache_en;
		awprot_en                          = c.awprot_en;
		awqos_en                           = c.awqos_en;
		awregion_en                        = c.awregion_en;
		arlock_en                          = c.arlock_en;
		arcache_en                         = c.arcache_en;
		arprot_en                          = c.arprot_en;
		arqos_en                           = c.arqos_en;
		arregion_en                        = c.arregion_en;
		drive_reset_values_when_idle       = c.drive_reset_values_when_idle;
		wr_out_of_order_depth              = c.wr_out_of_order_depth;
		wr_resp_out_of_order_depth         = c.wr_resp_out_of_order_depth;
		rd_out_of_order_depth              = c.rd_out_of_order_depth;
		wr_interleave_depth                = c.wr_interleave_depth;
		rd_interleave_depth                = c.rd_interleave_depth;
		wr_scheduling_alg                  = c.wr_scheduling_alg;
		rd_scheduling_alg                  = c.rd_scheduling_alg;
		allow_wdata_out_of_aw_order        = c.allow_wdata_out_of_aw_order;
		num_outstanding_transactions       = c.num_outstanding_transactions;
		num_outstanding_wr_transactions    = c.num_outstanding_wr_transactions;
		num_outstanding_rd_transactions    = c.num_outstanding_rd_transactions;
		tr_timeout_us                      = c.tr_timeout_us;
		auto_byte_lanes_alignment          = c.auto_byte_lanes_alignment;
		randomize_unstrobed_wdata          = c.randomize_unstrobed_wdata;
		randomize_unused_rdata             = c.randomize_unused_rdata;
		check_undefined_data_lanes         = c.check_undefined_data_lanes;
		randomize_idle_payload             = c.randomize_idle_payload;
		awready_waits_for_wvalid           = c.awready_waits_for_wvalid;
		suppress_delayed_slave_seq_warning = c.suppress_delayed_slave_seq_warning;
		enable_trans_log                   = c.enable_trans_log;
		trans_log_file                     = c.trans_log_file;
		trans_log_combined_file            = c.trans_log_combined_file;
		trans_log_format                   = c.trans_log_format;
		default_arready_pattern            = c.default_arready_pattern;
		default_awready_pattern            = c.default_awready_pattern;
		default_wready_pattern             = c.default_wready_pattern;
		default_rready_pattern             = c.default_rready_pattern;
		default_bready_pattern             = c.default_bready_pattern;
	endfunction : do_copy


	function bit check_config();

		// Widths that have no default
		if(int'(bus_width) == 0)
			`uvm_error("AXI_CFG", "bus_width is not set: give it an OVIP_AXI_BUS_WIDTH_* value")
		if(addr_width < 1)
			`uvm_error("AXI_CFG", $sformatf("addr_width(%0d) is not set: it must be 1 or more", addr_width))

		// Every depth is 1 at the least
		if(wr_out_of_order_depth      < 1) `uvm_error("AXI_CFG", $sformatf("wr_out_of_order_depth(%0d) must be 1 or more", wr_out_of_order_depth))
		if(wr_resp_out_of_order_depth < 1) `uvm_error("AXI_CFG", $sformatf("wr_resp_out_of_order_depth(%0d) must be 1 or more", wr_resp_out_of_order_depth))
		if(rd_out_of_order_depth      < 1) `uvm_error("AXI_CFG", $sformatf("rd_out_of_order_depth(%0d) must be 1 or more", rd_out_of_order_depth))
		if(wr_interleave_depth        < 1) `uvm_error("AXI_CFG", $sformatf("wr_interleave_depth(%0d) must be 1 or more", wr_interleave_depth))
		if(rd_interleave_depth        < 1) `uvm_error("AXI_CFG", $sformatf("rd_interleave_depth(%0d) must be 1 or more", rd_interleave_depth))

		if(protocol_type != OVIP_PROTOCOL_AXI3)
		begin
			if(agent_type == OVIP_MASTER_AGENT && wr_interleave_depth > 1)
				`uvm_error("AXI_CFG", $sformatf("wr_interleave_depth(%0d) must be 1 for protocol_type=%s",wr_interleave_depth,protocol_type.name()))
			if(agent_type == OVIP_MASTER_AGENT && wr_out_of_order_depth > 1)
				`uvm_error("AXI_CFG", $sformatf("wr_out_of_order_depth(%0d) must be 1 for protocol_type=%s",wr_out_of_order_depth,protocol_type.name()))
		end
		if(protocol_type == OVIP_PROTOCOL_AXI3)
		begin
			// wr_id_width should be 0
			// len_width should be 4
		end

		if(protocol_type == OVIP_PROTOCOL_AXI4_LITE)
		begin
			if(wr_out_of_order_depth      > 1) `uvm_error("AXI_CFG", $sformatf("wr_out_of_order_depth(%0d) must be 1 on AXI-Lite", wr_out_of_order_depth))
			if(wr_resp_out_of_order_depth > 1) `uvm_error("AXI_CFG", $sformatf("wr_resp_out_of_order_depth(%0d) must be 1 on AXI-Lite", wr_resp_out_of_order_depth))
			if(wr_interleave_depth        > 1) `uvm_error("AXI_CFG", $sformatf("wr_interleave_depth(%0d) must be 1 on AXI-Lite", wr_interleave_depth))
			if(rd_out_of_order_depth      > 1) `uvm_error("AXI_CFG", $sformatf("rd_out_of_order_depth(%0d) must be 1 on AXI-Lite", rd_out_of_order_depth))
			if(rd_interleave_depth        > 1) `uvm_error("AXI_CFG", $sformatf("rd_interleave_depth(%0d) must be 1 on AXI-Lite", rd_interleave_depth))
			// AXI4-Lite has a data bus of 32 or 64 bits (spec B1.1.2)
			if(int'(bus_width) != 0 && !(bus_width inside {OVIP_AXI_BUS_WIDTH_4B, OVIP_AXI_BUS_WIDTH_8B}))
				`uvm_error("AXI_CFG", $sformatf("bus_width(%s) must be OVIP_AXI_BUS_WIDTH_4B or OVIP_AXI_BUS_WIDTH_8B on AXI-Lite", bus_width.name()))
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
