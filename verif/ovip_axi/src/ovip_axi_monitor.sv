`ifndef OVIP_AXI_MONITOR__SV
`define OVIP_AXI_MONITOR__SV

class ovip_axi_monitor #(type IF_T = virtual ovip_axi_agent_if) extends uvm_monitor;

	string MESSAGE_TAG; // prefix on monitor message IDs; set from cfg.agent_tag (empty = none)

	IF_T vif;

	ovip_axi_agent_config cfg;

	int unsigned transaction_counter;

	int unsigned num_outstanding_wr;
	int unsigned num_outstanding_rd;


	// Signal masks - used to sample only the relevant portions of the signal
	// because signal widths are set to the maximum supported length.
	ovip_axi_addr_t ADDR_MASK;
	bit [3:0]       SIZE_MASK;
	bit [7:0]       LEN_MASK;
	ovip_axi_data_t DATA_MASK;
	ovip_axi_data_t STRB_MASK;
	ovip_axi_id_t WR_ID_MASK;
	ovip_axi_id_t RD_ID_MASK;
	ovip_axi_user_t AWUSER_MASK;
	ovip_axi_user_t WUSER_MASK;
	ovip_axi_user_t BUSER_MASK;
	ovip_axi_user_t ARUSER_MASK;
	ovip_axi_user_t RUSER_MASK;


	// `analysis_port_cont` - Broadcast the transaction when it starts.
	uvm_analysis_port #(ovip_axi_trans) analysis_port_cont;
	// `analysis_port` - Broadcast the transaction when it finishes.
	uvm_analysis_port #(ovip_axi_trans) analysis_port;


	// Queues (per ID) for outstanding read transactions (i.e., address phase has already been driven).
	// Used for moving transactions from the raddr_phase_monitor thread to the rdata_phase_monitor thread.
	protected ovip_axi_trans outstanding_rd_trans[ovip_axi_id_t][$];


	// Queues (per ID) for outstanding write transactions with the address phase sampled.
	protected ovip_axi_trans outstanding_wr_trans[ovip_axi_id_t][$];

	// Queues (per ID) for outstanding write transactions without the address phase.
	// For data phases without an ID field (non-AXI3 ports), all transactions are pushed into entry ID=0,
	// regardless of the actual ID.
	protected ovip_axi_trans outstanding_wr_trans_wo_addr_phase[ovip_axi_id_t][$];

	// Queues (per ID) for write transactions waiting for a response (i.e., LAST transfer has been sampled).
	protected ovip_axi_trans wr_trans_waiting_for_response[ovip_axi_id_t][$];


	// Queues for managing write transactions ordering.
	// These are needed for checking transactions and handling data channels without an ID field (non-AXI3 ports).
	protected ovip_axi_id_t wr_address_phase_order[$];
	protected ovip_axi_id_t wr_resp_phase_order[$];

	// Queue for managing read transactions ordering.
	protected ovip_axi_id_t rd_address_phase_order[$];


	// If both address and data phases are valid simultaneously,
	// wait for the address phase monitor thread to finish to avoid race conditions.
	semaphore addr_data_wr_phases_sync_sm;

	// Response request port - used for active slave ports.
	uvm_blocking_get_imp#(ovip_axi_trans, ovip_axi_monitor#(IF_T)) response_req_port;
	ovip_axi_trans pending_rsp_req[$];


	`uvm_component_param_utils(ovip_axi_monitor#(IF_T))


	function new(string name = "ovip_axi_monitor", uvm_component parent);
		super.new(name, parent);
		MESSAGE_TAG = "";
		num_outstanding_wr = 0;
		num_outstanding_rd = 0;
		transaction_counter = 0;
		addr_data_wr_phases_sync_sm = new(0);
	endfunction : new


	extern virtual function void build_phase(uvm_phase phase);
	extern virtual function void report_phase(uvm_phase phase);
	extern virtual task run_phase(uvm_phase phase);
	extern virtual task rst_monitor();

	// Empty hook subclasses override to fork additional per-channel monitors
	virtual task extra_forks(); endtask


	extern virtual function ovip_axi_trans new_transaction();
	extern virtual function ovip_axi_trans new_wr_transaction();
	extern virtual function ovip_axi_trans new_rd_transaction();
	extern virtual function void close_and_send_transaction(ovip_axi_trans tr);


	extern virtual task raddr_phase_monitor();
	extern virtual task rdata_phase_monitor();
	extern virtual task waddr_phase_monitor();
	extern virtual task wdata_phase_monitor();
	extern virtual task bresp_phase_monitor();


	extern virtual task check_that_all_valid_signals_are_low_while_reset();
	extern virtual task hand_shake_signals_xz_monitor();
	`ifndef OVIP_AXI_DISABLE_XZ_AND_SIGNALS_STABILITY_CHECKS
		extern virtual function void check_xz_write_address();
		extern virtual function void check_xz_write_data();
		extern virtual function void check_xz_write_response();
		extern virtual function void check_xz_read_address();
		extern virtual function void check_xz_read_data();

		extern virtual task aw_channel_signal_stability_check();
		extern virtual task w_channel_signal_stability_check();
		extern virtual task b_channel_signal_stability_check();
		extern virtual task ar_channel_signal_stability_check();
		extern virtual task r_channel_signal_stability_check();
	`else
		virtual function void check_xz_write_address() ; endfunction
		virtual function void check_xz_write_data()    ; endfunction
		virtual function void check_xz_write_response(); endfunction
		virtual function void check_xz_read_address()  ; endfunction
		virtual function void check_xz_read_data()     ; endfunction
	`endif


	// These functions can be extended to support additional signals
	extern virtual function void sample_write_address(ovip_axi_trans tr);
	extern virtual function void sample_write_data(ovip_axi_trans tr);
	extern virtual function void sample_write_response(ovip_axi_trans tr);
	extern virtual function void sample_read_address(ovip_axi_trans tr);
	extern virtual function void sample_read_data(ovip_axi_trans tr);

	// Auxiliary functions for handling Data Before Address (DBA) transactions.
	// These functions are primarily used to manage transactions where data phases occur before address phases.
	extern virtual function ovip_axi_trans locate_related_DBA_transaction(ovip_axi_id_t id);
	extern virtual function void check_wr_data_phase_post_address(ovip_axi_trans tr);
	extern virtual function void close_wr_transaction(ovip_axi_trans tr);
	extern virtual function void axi3_write_out_of_order_checker(ovip_axi_id_t id);
	extern virtual task axi3_write_interleaved_monitor();

	// Functions for checking channel activity.￼
	extern virtual task check_outstanding();
	extern virtual function void check_address_phase(ovip_axi_trans tr);
	extern virtual function void check_data_phase(ovip_axi_trans tr);
	extern virtual function void check_write_response(ovip_axi_trans tr);


	// Functions for sending response requests to the slave sequencer.
	// Used on active slave ports.
	extern virtual function void send_rsp_req(ovip_axi_trans tr);
	extern virtual task get(output ovip_axi_trans tr);


endclass : ovip_axi_monitor



function void ovip_axi_monitor::build_phase(uvm_phase phase);
	super.build_phase(phase);

	// Optional per-agent prefix on monitor message IDs (empty by default).
	if(cfg.agent_tag != "") MESSAGE_TAG = {cfg.agent_tag, "/"};

	if (!uvm_config_db#(IF_T)::get(this, "", "vif", vif))
	begin
		`uvm_fatal("MISSING_VIF",$sformatf("Missing virtual interface - %s.vif", this.get_full_name() ))
	end
	analysis_port_cont = new("analysis_port_cont", this);
	analysis_port = new("analysis_port", this);

	if(cfg.agent_type == OVIP_SLAVE_AGENT && cfg.is_active)
		response_req_port = new("response_req_port", this);

endfunction : build_phase


task ovip_axi_monitor::run_phase(uvm_phase phase);

	// Setting signal masks based on the configuration object.
	ADDR_MASK = (ovip_axi_addr_t'(1)<<cfg.addr_width)-1;
	LEN_MASK  = (1<<cfg.len_width)-1;
	SIZE_MASK = (1<<cfg.size_width)-1;
	DATA_MASK = (ovip_axi_data_t'(1)<<cfg.bus_width*8)-1;
	STRB_MASK = (ovip_axi_data_t'(1)<<(cfg.bus_width))-1;
	WR_ID_MASK = (ovip_axi_id_t'(1)<<cfg.wr_id_width)-1;
	RD_ID_MASK = (ovip_axi_id_t'(1)<<cfg.rd_id_width)-1;

	AWUSER_MASK = (ovip_axi_user_t'(1)<<cfg.awuser_width)-1;
	WUSER_MASK  = (ovip_axi_user_t'(1)<<cfg.wuser_width) -1;
	BUSER_MASK  = (ovip_axi_user_t'(1)<<cfg.buser_width) -1;
	ARUSER_MASK = (ovip_axi_user_t'(1)<<cfg.aruser_width)-1;
	RUSER_MASK  = (ovip_axi_user_t'(1)<<cfg.ruser_width) -1;

	fork
		check_that_all_valid_signals_are_low_while_reset();
	join_none

	forever
	begin
		`uvm_info(MESSAGE_TAG, "Waiting for reset de-assertion", UVM_DEBUG)
		@(vif.monitor_cb iff vif.monitor_cb.aresetn);
		`uvm_info(MESSAGE_TAG, "Reset has been de-asserted", UVM_DEBUG)

		`BEGIN_FIRST_OF
			rst_monitor();
			fork
				if(cfg.interface_type != OVIP_AXI_WRITE_ONLY_INTERFACE) raddr_phase_monitor();
				if(cfg.interface_type != OVIP_AXI_WRITE_ONLY_INTERFACE) rdata_phase_monitor();
				if(cfg.interface_type != OVIP_AXI_READ_ONLY_INTERFACE) waddr_phase_monitor();
				if(cfg.interface_type != OVIP_AXI_READ_ONLY_INTERFACE) wdata_phase_monitor();
				if(cfg.interface_type != OVIP_AXI_READ_ONLY_INTERFACE) bresp_phase_monitor();

				hand_shake_signals_xz_monitor();
				`ifndef OVIP_AXI_DISABLE_XZ_AND_SIGNALS_STABILITY_CHECKS
					if(cfg.interface_type != OVIP_AXI_READ_ONLY_INTERFACE) aw_channel_signal_stability_check();
					if(cfg.interface_type != OVIP_AXI_READ_ONLY_INTERFACE) w_channel_signal_stability_check();
					if(cfg.interface_type != OVIP_AXI_READ_ONLY_INTERFACE) b_channel_signal_stability_check();
					if(cfg.interface_type != OVIP_AXI_WRITE_ONLY_INTERFACE) ar_channel_signal_stability_check();
					if(cfg.interface_type != OVIP_AXI_WRITE_ONLY_INTERFACE) r_channel_signal_stability_check();
				`endif

				extra_forks();
			join
		`END_FIRST_OF
	end
endtask : run_phase


task ovip_axi_monitor::rst_monitor();
	@(vif.monitor_cb iff vif.monitor_cb.aresetn == 1'b0);
	`uvm_info(MESSAGE_TAG, "Reset asserted!", UVM_LOW)

	outstanding_rd_trans.delete();
	outstanding_wr_trans.delete();
	outstanding_wr_trans_wo_addr_phase.delete();
	wr_trans_waiting_for_response.delete();
	wr_address_phase_order.delete();
	wr_resp_phase_order.delete();
	rd_address_phase_order.delete();

	num_outstanding_wr = 0;
	num_outstanding_rd = 0;
	addr_data_wr_phases_sync_sm = new(0);
	pending_rsp_req.delete();
endtask : rst_monitor


function ovip_axi_trans ovip_axi_monitor::new_transaction();
	new_transaction = ovip_axi_trans::type_id::create($sformatf("axi_tr_%0d",++transaction_counter));
	new_transaction.bus_width = cfg.bus_width;
	//void'(begin_tr(tr));
	analysis_port_cont.write(new_transaction);
endfunction : new_transaction


function ovip_axi_trans ovip_axi_monitor::new_wr_transaction();
	new_wr_transaction = new_transaction();
	new_wr_transaction.tr_type = OVIP_AXI_WRITE_TRANS;
	fork
		begin
			ovip_axi_trans tr = new_wr_transaction;
			`BEGIN_FIRST_OF
			begin
				#(cfg.tr_timeout_us*1us);
				`uvm_fatal({MESSAGE_TAG, "AXI_MON/TIMEOUT"}, $sformatf("Transaction did not complete within %0d us (tr_timeout_us). %s", cfg.tr_timeout_us, tr.convert2string()))
			end
			begin
				tr.completed_ev.wait_on(); // triggered in sample_write_response (BRESP received)
			end
			`END_FIRST_OF
		end
	join_none
endfunction : new_wr_transaction


function ovip_axi_trans ovip_axi_monitor::new_rd_transaction();
	new_rd_transaction = new_transaction();
	new_rd_transaction.tr_type = OVIP_AXI_READ_TRANS;
	fork
		begin
			ovip_axi_trans tr = new_rd_transaction;
			`BEGIN_FIRST_OF
			begin
				#(cfg.tr_timeout_us*1us);
				`uvm_fatal({MESSAGE_TAG, "AXI_MON/TIMEOUT"}, $sformatf("Transaction did not complete within %0d us (tr_timeout_us). %s", cfg.tr_timeout_us, tr.convert2string()))
			end
			begin
				tr.completed_ev.wait_on(); // triggered in sample_read_data (last beat received)
			end
			`END_FIRST_OF
		end
	join_none

endfunction : new_rd_transaction


function void ovip_axi_monitor::close_and_send_transaction(ovip_axi_trans tr);
	`uvm_info({MESSAGE_TAG, "AXI_MON"}, tr.convert2string(), UVM_LOW)
	analysis_port.write(tr);
endfunction : close_and_send_transaction

// ----------------------------------------------------------------------------------- //
//                                                                                     //
//                       X/Z monitor and steady driving checker                        //
//                                                                                     //
// ----------------------------------------------------------------------------------- //
task ovip_axi_monitor::check_that_all_valid_signals_are_low_while_reset();
	forever
	begin
		@(vif.monitor_cb iff !vif.monitor_cb.aresetn);
		// One-cycle grace after reset assertion: on a mid-burst reset the valid signals
		// can still sample high on the very first reset cycle (the interface's ~aresetn
		// override needs a cycle to win). From the next cycle onward we enforce the rule.
		@(vif.monitor_cb);
		while(vif.monitor_cb.aresetn == 0)
		begin
			if(cfg.interface_type != OVIP_AXI_READ_ONLY_INTERFACE) begin
				if(vif.monitor_cb.awvalid !== 0) `uvm_error({MESSAGE_TAG, "AXI_MON/BAD_VALIDATOR"}, "Signal AWVALID must be de-asserted while reset is asserted!")
				if(vif.monitor_cb.wvalid  !== 0) `uvm_error({MESSAGE_TAG, "AXI_MON/BAD_VALIDATOR"}, "Signal WVALID must be de-asserted while reset is asserted!")
				if(vif.monitor_cb.bvalid  !== 0) `uvm_error({MESSAGE_TAG, "AXI_MON/BAD_VALIDATOR"}, "Signal BVALID must be de-asserted while reset is asserted!")
			end

			if(cfg.interface_type != OVIP_AXI_WRITE_ONLY_INTERFACE) begin
				if(vif.monitor_cb.arvalid !== 0) `uvm_error({MESSAGE_TAG, "AXI_MON/BAD_VALIDATOR"}, "Signal ARVALID must be de-asserted while reset is asserted!")
				if(vif.monitor_cb.rvalid  !== 0) `uvm_error({MESSAGE_TAG, "AXI_MON/BAD_VALIDATOR"}, "Signal RVALID must be de-asserted while reset is asserted!")
			end
			@(vif.monitor_cb);
		end
	end
endtask : check_that_all_valid_signals_are_low_while_reset


task ovip_axi_monitor::hand_shake_signals_xz_monitor();
	forever
	begin
		@(vif.monitor_cb iff vif.monitor_cb.aresetn);
		if(cfg.interface_type != OVIP_AXI_READ_ONLY_INTERFACE) begin
			`OVIP_AXI_MON_XZ_CHECK(awvalid, AWVALID)
			`OVIP_AXI_MON_XZ_CHECK(awready, AWREADY)
			`OVIP_AXI_MON_XZ_CHECK(wvalid , WVALID )
			`OVIP_AXI_MON_XZ_CHECK(wready , WREADY )
			`OVIP_AXI_MON_XZ_CHECK(bvalid , BVALID )
			`OVIP_AXI_MON_XZ_CHECK(bready , BREADY )
		end
		if(cfg.interface_type != OVIP_AXI_WRITE_ONLY_INTERFACE) begin
			`OVIP_AXI_MON_XZ_CHECK(arvalid, ARVALID)
			`OVIP_AXI_MON_XZ_CHECK(arready, ARREADY)
			`OVIP_AXI_MON_XZ_CHECK(rvalid , RVALID )
			`OVIP_AXI_MON_XZ_CHECK(rready , RREADY )
		end
	end
endtask : hand_shake_signals_xz_monitor

`ifndef OVIP_AXI_DISABLE_XZ_AND_SIGNALS_STABILITY_CHECKS
	`include "ovip_axi_monitor_xz_and_stability_functions.sv"
`endif

// ----------------------------------------------------------------------------------- //
//                                                                                     //
//                                Read channels monitors                               //
//                                                                                     //
// ----------------------------------------------------------------------------------- //


task ovip_axi_monitor::check_outstanding();

	if(num_outstanding_wr > cfg.num_outstanding_wr_transactions && cfg.num_outstanding_wr_transactions)
		`uvm_error({MESSAGE_TAG, "AXI_MON/OUTSTANDING_EXCEED"}, $sformatf("Number of outstanding write transactions (%0d) exceeded the configured limit (%0d)",
			num_outstanding_wr, cfg.num_outstanding_wr_transactions))

	if(num_outstanding_rd > cfg.num_outstanding_rd_transactions && cfg.num_outstanding_rd_transactions)
		`uvm_error({MESSAGE_TAG, "AXI_MON/OUTSTANDING_EXCEED"}, $sformatf("Number of outstanding read transactions (%0d) exceeded the configured limit (%0d)",
			num_outstanding_rd, cfg.num_outstanding_rd_transactions))

	if(num_outstanding_rd+num_outstanding_wr > cfg.num_outstanding_transactions && cfg.num_outstanding_transactions)
		`uvm_error({MESSAGE_TAG ,"AXI_MON/OUTSTANDING_EXCEED"}, $sformatf("Total number of outstanding transactions (%0d) exceeded the configured limit (%0d)",
			num_outstanding_rd+num_outstanding_wr, cfg.num_outstanding_rd_transactions))

endtask : check_outstanding


function void ovip_axi_monitor::check_address_phase(ovip_axi_trans tr);
	int burst_len = 1 + tr.len;
	int burst_size = (1<<tr.size);

	string error_tag = (tr.tr_type == OVIP_AXI_WRITE_TRANS)? "AXI_MON/WR" : "AXI_MON/RD";
	error_tag = {MESSAGE_TAG, error_tag};


	if(cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE)
	begin
		// TODO: is there any check that should be done here?
		return;
	end


	if(burst_size > cfg.bus_width)
	begin
		`uvm_error(error_tag, $sformatf("Burst size(%0d) is bigger than bus width(%0d)", burst_size, cfg.bus_width))
		tr.monitor_error = 1;
	end


	if(tr.burst == OVIP_AXI_BURST_INCR)
	begin
		ovip_axi_addr_t aligned_addr;
		aligned_addr = tr.addr & `OVIP_AXI_MAX_ADDR_WIDTH'hFFF;
		aligned_addr &= ({`OVIP_AXI_MAX_ADDR_WIDTH{1'b1}}<<tr.size);
		if(aligned_addr + burst_len*burst_size > `OVIP_AXI_MAX_ADDR_WIDTH'h1000)
		begin
			`uvm_error(error_tag, "4K boundary crossing")
			tr.monitor_error = 1;
		end
	end
	else if(tr.burst == OVIP_AXI_BURST_FIXED)
	begin
		if(burst_len > 16)
		begin
			`uvm_error(error_tag, $sformatf("The length of a FIXED burst must not exceed 16 (actual value: %0d).", burst_len))
			tr.monitor_error = 1;
		end
	end
	else if(tr.burst == OVIP_AXI_BURST_WRAP)
	begin
		if(tr.addr % burst_size)
		begin
			`uvm_error(error_tag, $sformatf("WRAP burst: start address (0x%0h) must be aligned to burst_size (%0dB).", tr.addr, burst_size))
			tr.monitor_error = 1;
		end

		if( !(burst_len inside {2, 4, 8, 16}) )
		begin
			`uvm_error(error_tag, $sformatf("WRAP burst: length must be 2, 4, 8, or 16 transfers (actual: %0d).", burst_len))
			tr.monitor_error = 1;
		end

		// WRAP windows are aligned to total_size = burst_size*(len+1), which
		// itself is a power of two <= 16*128 = 2KB for spec-compliant sizes.
		// A spec-compliant WRAP therefore can never cross a 4KB boundary, so
		// no 4K cross check is needed here.
	end
	else // OVIP_AXI_BURST_RES
	begin
		`uvm_error(error_tag, "Got transaction with reserved burst type!")
		tr.monitor_error = 1;
	end
endfunction : check_address_phase



function void ovip_axi_monitor::check_data_phase(ovip_axi_trans tr);
	if(!tr.valid_address_phase) return;

	if(cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE)
	begin
		if(tr.resp == OVIP_AXI_RESP_EXOKAY)
			`uvm_error("AXI_MON", "EXOKAY response is not supported on AXI4-Lite")
		return;
	end

	begin
		int burst_len = 1 + tr.len;
		int num_beats = tr.burst_index;
		string error_tag = (tr.tr_type == OVIP_AXI_WRITE_TRANS)? "AXI_MON/WR" : "AXI_MON/RD";
		error_tag = {MESSAGE_TAG, error_tag};

		if(tr.got_last_beat && num_beats < burst_len)
		begin
			`uvm_error(error_tag, $sformatf("xLAST was asserted on transfer #%0d, but the address phase AxLEN indicates it should be on transfer #%0d.", num_beats, burst_len))
			tr.monitor_error = 1;
		end

		if(!tr.got_last_beat && num_beats >= burst_len)
		begin
			`uvm_error(error_tag, $sformatf("Missing xLAST: The expected xLAST assertion on transfer #%0d (as per AWLEN=%0d) was not observed.", num_beats, burst_len))
			tr.monitor_error = 1;
		end
	end

endfunction : check_data_phase

function void ovip_axi_monitor::check_write_response(ovip_axi_trans tr);

	if(cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE && tr.resp == OVIP_AXI_RESP_EXOKAY)
		`uvm_error("AXI_MON", "EXOKAY response is not supported on AXI4-Lite")

endfunction : check_write_response


// ----------------------------------------------------------------------------------- //
//                                                                                     //
//                             Channels sample functions                               //
//                                                                                     //
// ----------------------------------------------------------------------------------- //

function void ovip_axi_monitor::sample_write_address(ovip_axi_trans tr);
	tr.addr   = vif.monitor_cb.awaddr&ADDR_MASK;
	tr.id     = vif.monitor_cb.awid  &WR_ID_MASK;
	tr.awuser = vif.monitor_cb.awuser&AWUSER_MASK;

	if(cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE)
	begin
		tr.len   = 0;
		tr.size  = ovip_axi_size_t'($clog2(int'(cfg.bus_width))); // AXI size = log2(bytes per beat)
		tr.burst = OVIP_AXI_BURST_INCR;
		return;
	end

	tr.len   = vif.monitor_cb.awlen&LEN_MASK;
	tr.size  = ovip_axi_size_t'(vif.monitor_cb.awsize&SIZE_MASK);
	tr.burst = ovip_axi_burst_t'(vif.monitor_cb.awburst);

	if(cfg.awlock_en)   tr.axlock   = vif.monitor_cb.awlock;
	if(cfg.awcache_en)  tr.axcache  = vif.monitor_cb.awcache;
	if(cfg.awprot_en)   tr.axprot   = vif.monitor_cb.awprot;
	if(cfg.awqos_en)    tr.axqos    = vif.monitor_cb.awqos;
	if(cfg.awregion_en) tr.axregion = vif.monitor_cb.awregion;
endfunction : sample_write_address


function void ovip_axi_monitor::sample_write_data(ovip_axi_trans tr);
	// Data & Strobe
	ovip_axi_data_t wdata = vif.monitor_cb.wdata&DATA_MASK;
	ovip_axi_strb_t wstrb = vif.monitor_cb.wstrb&STRB_MASK;
	tr.data_beats[tr.burst_index] = wdata;
	tr.strb_beats[tr.burst_index] = wstrb;

	if(tr.burst_index == 0) tr.data_phase_begin_time = $time; // first W beat

	// Check strobes and handle automatic byte lane alignment.
	// This is relevant for all beats in the case of narrow transfers
	// and always necessary on the first beat due to potential unaligned access.
	if(tr.is_narrow_transfer || (tr.valid_address_phase && tr.burst_index == 0))
	begin
		string err_msg[$];
		if(!tr.check_strb(tr.burst_index, tr.burst_index, err_msg))
		begin
			`uvm_error("AXI_MON/INVALID_WSTRB", err_msg[0])
			tr.monitor_error = 1;
		end

		if(cfg.auto_byte_lanes_alignment)
		begin
			tr.data_beats[tr.burst_index] >>= tr.transfer_starting_byte_lane[tr.burst_index]*8;
			tr.strb_beats[tr.burst_index] >>= tr.transfer_starting_byte_lane[tr.burst_index];
		end
	end


	tr.wuser = vif.monitor_cb.wuser&WUSER_MASK;
	tr.got_last_beat = (vif.monitor_cb.wlast || cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE);
	if(tr.got_last_beat) tr.data_phase_time = $time; // last W beat
endfunction : sample_write_data


function void ovip_axi_monitor::sample_write_response(ovip_axi_trans tr);
	tr.id    = vif.monitor_cb.bid&WR_ID_MASK;
	tr.resp  = ovip_axi_resp_t'(vif.monitor_cb.bresp);
	tr.buser = vif.monitor_cb.buser&BUSER_MASK;
	tr.resp_phase_time = $time; // B response
	tr.transaction_finished = 1;
	tr.completed_ev.trigger();
endfunction : sample_write_response


function void ovip_axi_monitor::sample_read_address(ovip_axi_trans tr);
	tr.id     = vif.monitor_cb.arid  &RD_ID_MASK;
	tr.addr   = vif.monitor_cb.araddr&ADDR_MASK;
	tr.aruser = vif.monitor_cb.aruser&ARUSER_MASK;

	if(cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE)
	begin
		tr.len   = 0;
		tr.size  = ovip_axi_size_t'($clog2(int'(cfg.bus_width))); // AXI size = log2(bytes per beat)
		tr.burst = OVIP_AXI_BURST_INCR;
		return;
	end

	tr.len   = vif.monitor_cb.arlen&LEN_MASK;
	tr.size  = ovip_axi_size_t'(vif.monitor_cb.arsize & SIZE_MASK);
	tr.burst = ovip_axi_burst_t'(vif.monitor_cb.arburst);

	if(cfg.arlock_en)   tr.axlock   = vif.monitor_cb.arlock;
	if(cfg.arcache_en)  tr.axcache  = vif.monitor_cb.arcache;
	if(cfg.arprot_en)   tr.axprot   = vif.monitor_cb.arprot;
	if(cfg.arqos_en)    tr.axqos    = vif.monitor_cb.arqos;
	if(cfg.arregion_en) tr.axregion = vif.monitor_cb.arregion;

endfunction : sample_read_address


function void ovip_axi_monitor::sample_read_data(ovip_axi_trans tr);
	ovip_axi_data_t	rdata = vif.monitor_cb.rdata & DATA_MASK;
	if(cfg.auto_byte_lanes_alignment && (tr.is_narrow_transfer || tr.burst_index == 0))
			rdata >>= tr.transfer_starting_byte_lane[tr.burst_index]*8;
	tr.data_beats[tr.burst_index] = rdata;

	if(tr.burst_index == 0) tr.data_phase_begin_time = $time; // first R beat

	tr.id = vif.monitor_cb.rid&RD_ID_MASK;

	tr.got_last_beat = (vif.monitor_cb.rlast || cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE);
	tr.transaction_finished = tr.got_last_beat;
	if(tr.transaction_finished) tr.completed_ev.trigger();

	if(tr.got_last_beat)
		tr.resp = ovip_axi_resp_t'(vif.monitor_cb.rresp);

	if(tr.got_last_beat)
	begin
		tr.data_phase_time = $time; // last R beat
		tr.resp_phase_time = $time; // read response rides the last beat
	end

	// optional signals
	tr.ruser = vif.monitor_cb.ruser & RUSER_MASK;
endfunction : sample_read_data

// ----------------------------------------------------------------------------------- //
//                                                                                     //
//                               Write channels monitors                               //
//                                                                                     //
// ----------------------------------------------------------------------------------- //

// This function checks if there are already data phase beats related to this address phase.
// It is used for handling data before address (DBA).
function ovip_axi_trans ovip_axi_monitor::locate_related_DBA_transaction(ovip_axi_id_t id);
	ovip_axi_id_t _id = (cfg.protocol_type == OVIP_PROTOCOL_AXI3)? id : 0; // since on non-AXI3 there is no ID in write phase
	bit data_phase_exsits = outstanding_wr_trans_wo_addr_phase.exists(_id) && outstanding_wr_trans_wo_addr_phase[_id].size();

	if(data_phase_exsits)
	begin
		ovip_axi_trans tr = outstanding_wr_trans_wo_addr_phase[_id].pop_front();
		tr.id = id;
		`uvm_info({MESSAGE_TAG, "AXI_MON/DBA"}, $sformatf("Received a new address phase for an already open transaction"), UVM_HIGH)
		return tr;
	end

	return null;
endfunction : locate_related_DBA_transaction


function void ovip_axi_monitor::check_wr_data_phase_post_address(ovip_axi_trans tr);
	string err_msg[$];

	int last_beat = tr.burst_index-1;
	if(last_beat > tr.len) // more transfer then expected
	begin
		`uvm_error({MESSAGE_TAG, "AXI_MON/AWLEN_MISMATCH"}, $sformatf("Transaction length mismatch. Data phase indicated a total of %0d transfers, but the address phase specified an AWLEN of %0d!",
			last_beat, tr.len))
		tr.monitor_error = 1;
		last_beat = tr.len;
	end

	if(!tr.check_strb(0, last_beat, err_msg))
	begin
		tr.monitor_error = 1;
		foreach(err_msg[ii])
		begin
			`uvm_error({MESSAGE_TAG, "AXI_MON/INVALID_WSTRB"}, $sformatf("WR transaction(%s) with addr_phase @%0t. Arrived with %s",
				tr.get_name(), tr.addr_phase_time, err_msg[ii]))
		end
	end

	if(cfg.auto_byte_lanes_alignment)
	begin
		for(int ii=0; ii<tr.burst_index; ii++)
		begin
			tr.strb_beats[ii] >>= tr.transfer_starting_byte_lane[ii];
			tr.data_beats[ii] >>= tr.transfer_starting_byte_lane[ii]*8;
			if(!tr.is_narrow_transfer) break;
		end
	end
endfunction : check_wr_data_phase_post_address


function void ovip_axi_monitor::close_wr_transaction(ovip_axi_trans tr);

	// Remove the transaction from both the address and data phase contexts.
	if(cfg.protocol_type == OVIP_PROTOCOL_AXI3)
	begin
		int idx[$] = wr_address_phase_order.find_first_index() with (item == tr.id);
		wr_address_phase_order.delete( idx[0] );
	end
	else
	begin
		wr_address_phase_order.delete(0);
	end
	outstanding_wr_trans[tr.id].delete(0);


	// Add the transaction to the response phase context.
	wr_trans_waiting_for_response[tr.id].push_back(tr);
	wr_resp_phase_order.push_back(tr.id);

	// For active slaves, forward the transaction to the responder.
	if(cfg.agent_type == OVIP_SLAVE_AGENT && cfg.is_active)
	begin
		send_rsp_req(tr);
	end
endfunction : close_wr_transaction


task ovip_axi_monitor::axi3_write_interleaved_monitor();
	bit wr_interleaved_ids[ovip_axi_id_t]; // Interleaved writes are valid in AXI3 only
	ovip_axi_id_t id;
	bit addr_phase_exists;

	if(cfg.protocol_type != OVIP_PROTOCOL_AXI3) return;

	forever
	begin
		@(vif.monitor_cb iff vif.monitor_cb.aresetn && vif.monitor_cb.wvalid && vif.monitor_cb.wready);
		id = vif.monitor_cb.wid&WR_ID_MASK;

		// Interleaved depth check
		wr_interleaved_ids[id] = 1;
		if(wr_interleaved_ids.num() > cfg.wr_interleave_depth)
			`uvm_error({MESSAGE_TAG, "AXI_MON/INTERLEAVING_EXCEED"}, $sformatf("Write data interleaving depth (%0d) exceeded configured limit (%0d)",
				wr_interleaved_ids.num(), cfg.wr_interleave_depth))
		if(vif.monitor_cb.wlast) wr_interleaved_ids.delete(id);


	end
endtask : axi3_write_interleaved_monitor


function void ovip_axi_monitor::axi3_write_out_of_order_checker(ovip_axi_id_t id);
	int idx[$] = wr_address_phase_order.find_first_index() with (item == id);
	if(idx.size() == 0) `uvm_fatal("SIM_ASSERT", $sformatf("missing matching entry in `wr_address_phase_order` array! ID=%0d", id))
	if(idx[0] >= cfg.wr_out_of_order_depth)
		`uvm_error({MESSAGE_TAG, "AXI_MON/WDATA_OOO"}, $sformatf("Out of order depth (%0d) exceeded the allowed value (%0d)", idx[0]+1, cfg.wr_out_of_order_depth))
endfunction : axi3_write_out_of_order_checker


task ovip_axi_monitor::waddr_phase_monitor();
	ovip_axi_trans tr;
	ovip_axi_id_t id;

	forever
	begin
		@(vif.monitor_cb iff vif.monitor_cb.aresetn & vif.monitor_cb.awvalid & vif.monitor_cb.awready);

		id = vif.monitor_cb.awid&WR_ID_MASK;
		wr_address_phase_order.push_back(id);

		// First, check if there is an open transaction missing the address phase
		// (i.e., the first data beat was sampled before the address phase).
		tr = locate_related_DBA_transaction(id);

		if(tr == null)
		begin
			// Address-first write: the address is its first phase, so count it as
			// outstanding now. (A data-before-address write was already counted when
			// its data phase opened it -- see wdata_phase_monitor.)
			++num_outstanding_wr;
			check_outstanding();
			tr = new_wr_transaction();
			`uvm_info({MESSAGE_TAG, "AXI_MON"}, $sformatf("Received new address phase with ID=%0d", id), UVM_HIGH)
		end
		else
		begin
			`uvm_info({MESSAGE_TAG, "AXI_MON"}, $sformatf("Received new address phase with ID=%0d for an already opened transaction", id), UVM_HIGH)
		end

		check_xz_write_address();
		sample_write_address(tr);
		check_address_phase(tr);
		tr.addr_phase_time = $time;
		tr.valid_address_phase = 1;
		tr.is_narrow_transfer = (2**tr.size != int'(cfg.bus_width));
		//if(cfg.auto_byte_lanes_alignment)
		// Calling calculate_transfer_starting_byte_lane even when auto_byte_lanes_alignment=0 since tr.check_strb needs it.
		tr.calculate_transfer_starting_byte_lane();

		// For data before address (DBA) scenarios, after receiving the address phase,
		// we can then check all previously sampled data beats.
		if(tr.burst_index != 0)
			check_wr_data_phase_post_address(tr);

		outstanding_wr_trans[id].push_back(tr);

		if(tr.got_last_beat)
		begin
			check_data_phase(tr);
			close_wr_transaction(tr);
		end

		if(vif.monitor_cb.wvalid && vif.monitor_cb.wready) addr_data_wr_phases_sync_sm.put(1);
	end
endtask : waddr_phase_monitor


task ovip_axi_monitor::wdata_phase_monitor();
	fork axi3_write_interleaved_monitor(); join_none

	forever
	begin
		ovip_axi_trans tr;
		ovip_axi_id_t id;
		bit addr_phase_exists;

		@(vif.monitor_cb iff vif.monitor_cb.aresetn && vif.monitor_cb.wvalid && vif.monitor_cb.wready);
		if(vif.monitor_cb.awvalid && vif.monitor_cb.awready) addr_data_wr_phases_sync_sm.get(1);

		// Stage I: Retrieve the transaction ID and check if the address phase has already been processed for it.
		if(cfg.protocol_type == OVIP_PROTOCOL_AXI3)
		begin
			id = vif.monitor_cb.wid&WR_ID_MASK;
			addr_phase_exists = (outstanding_wr_trans.exists(id) && outstanding_wr_trans[id].size());
			if(addr_phase_exists)
				axi3_write_out_of_order_checker(id);
		end
		else // In non-AXI3 ports, the ID is implicitly defined by the order of the address phases.
		begin
			id = 0;
			if(wr_address_phase_order.size())
			begin
				addr_phase_exists = 1;
				id = wr_address_phase_order[0];
			end
		end

		// Stage II:
		// If there is an open transaction, pop it from the relevant queue:
		// - `outstanding_wr_trans` if the address phase exists
		// - `outstanding_wr_trans_wo_addr_phase` if it's a Data Before Address (DBA) transaction
		// If this is the first transfer of a DBA transaction, create a new transaction and add it to
		// `outstanding_wr_trans_wo_addr_phase`.
		if(addr_phase_exists)
		begin
			if(outstanding_wr_trans.exists(id) == 0) `uvm_fatal("SIM_ASSERT", $sformatf("addr_phase_exists: unknown id %0d",id))
			tr = outstanding_wr_trans[id][0];
			if(tr == null) `uvm_fatal("SIM_ASSERT","addr_phase_exists: tr == null")
		end
		else
		begin
			// Check if there is an existing open outstanding transaction without an address phase (i.e., without WLAST).
			// If such a transaction exists, use it. Otherwise, add a new transaction to the queue.
			if(
				outstanding_wr_trans_wo_addr_phase.exists(id)
				&&
				outstanding_wr_trans_wo_addr_phase[id].size()
				&&
				!outstanding_wr_trans_wo_addr_phase[id][$].got_last_beat
			)
			begin
				tr = outstanding_wr_trans_wo_addr_phase[id][$];
			end
			else
			begin
				// Data-before-address write: data is its first phase, so count it as
				// outstanding now (it will NOT be re-counted when its address arrives).
				tr = new_wr_transaction();
				outstanding_wr_trans_wo_addr_phase[id].push_back( tr );
				++num_outstanding_wr;
				check_outstanding();
			end
		end


		tr.data_phase_started = 1;
		check_xz_write_data();
		sample_write_data(tr);
		tr.burst_index++;
		check_data_phase(tr);

		if(tr.got_last_beat && tr.valid_address_phase)
		begin
			close_wr_transaction(tr);
		end
	end
endtask : wdata_phase_monitor


task ovip_axi_monitor::bresp_phase_monitor();
	forever
	begin
		ovip_axi_id_t id;
		ovip_axi_trans tr;
		@(vif.monitor_cb iff vif.monitor_cb.aresetn & vif.monitor_cb.bvalid & vif.monitor_cb.bready);
		--num_outstanding_wr;
		id = vif.monitor_cb.bid & WR_ID_MASK;


		if(!wr_trans_waiting_for_response.exists(id) || wr_trans_waiting_for_response[id].size() == 0)
		begin
			`uvm_error({MESSAGE_TAG, "AXI_MON/BRESP"}, $sformatf("Unexpected BRESP: write response for ID 0x%0x with no matching outstanding write request.", id))
			continue;
		end

		// Check for out-of-order depth.
		begin
			int idx[$] = wr_resp_phase_order.find_first_index() with (item == id);
			if(idx.size() == 0) `uvm_fatal("SIM_ASSERT", "missing matching entry inside wr_resp_phase_order array!")
			if(idx[0] >= cfg.wr_resp_out_of_order_depth)
				`uvm_error({MESSAGE_TAG, "AXI_MON/BRESP_OOO"}, $sformatf("out of order depth (%0d) exceeded the allowed value (%0d)", idx[0]+1, cfg.wr_resp_out_of_order_depth))
			wr_resp_phase_order.delete( idx[0] );
		end

		tr = wr_trans_waiting_for_response[id].pop_front();

		check_xz_write_response();
		sample_write_response(tr);
		check_write_response(tr);
		close_and_send_transaction(tr);
	end
endtask : bresp_phase_monitor



// ----------------------------------------------------------------------------------- //
//                                                                                     //
//                                Read channels monitors                               //
//                                                                                     //
// ----------------------------------------------------------------------------------- //

task ovip_axi_monitor::raddr_phase_monitor();
	ovip_axi_trans tr;

	forever
	begin
		@(vif.monitor_cb iff vif.monitor_cb.aresetn & vif.monitor_cb.arvalid & vif.monitor_cb.arready);
		++num_outstanding_rd;
		check_outstanding();

		tr = new_rd_transaction();

		check_xz_read_address();
		sample_read_address(tr);
		check_address_phase(tr);

		rd_address_phase_order.push_back(tr.id);

		tr.addr_phase_time = $time;
		tr.valid_address_phase = 1;

		tr.is_narrow_transfer = (2**tr.size != int'(cfg.bus_width));
		if(cfg.auto_byte_lanes_alignment)
			tr.calculate_transfer_starting_byte_lane();


		outstanding_rd_trans[tr.id].push_back(tr);

		if(cfg.agent_type == OVIP_SLAVE_AGENT && cfg.is_active)
		begin
			send_rsp_req(tr);
		end
	end

endtask : raddr_phase_monitor


task ovip_axi_monitor::rdata_phase_monitor();
	bit rd_interleaved_ids[ovip_axi_id_t];

	forever
	begin
		ovip_axi_trans tr;
		ovip_axi_id_t id;

		@(vif.monitor_cb iff vif.monitor_cb.aresetn & vif.monitor_cb.rvalid & vif.monitor_cb.rready);
		id = vif.monitor_cb.rid & RD_ID_MASK;

		if(!outstanding_rd_trans.exists(id) || outstanding_rd_trans[id].size() == 0)
		begin
			`uvm_error({MESSAGE_TAG, "AXI_MON/RDATA"}, "Data phase encountered without a corresponding address phase. Ignoring this beat.")
			continue;
		end

		//
		// Interleave and out-of-order checks
		//
		begin
			// Check if the out-of-order depth is exceeded.
			int idx[$] = rd_address_phase_order.find_first_index() with (item == id);
			if(idx.size() == 0) `uvm_fatal("SIM_ASSERT", "Missing matching entry in rd_address_phase_order array!")
			if(idx[0] >= cfg.rd_out_of_order_depth)
				`uvm_error({MESSAGE_TAG, "AXI_MON/RDATA_OOO"}, $sformatf("out of order depth (%0d) exceeded the allowed value (%0d)", idx[0]+1, cfg.rd_out_of_order_depth))

			// Check if the interleaved depth is exceeded.
			rd_interleaved_ids[id] = 1;
			if(rd_interleaved_ids.num() > cfg.rd_interleave_depth)
				`uvm_error({MESSAGE_TAG, "AXI_MON/RDATA"}, $sformatf("Read data interleaving (%0d) exceeded the configured rd_interleave_depth (%0d).", rd_interleaved_ids.num(), cfg.rd_interleave_depth))

			if(vif.monitor_cb.rlast || cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE)
			begin
				rd_interleaved_ids.delete(id);
				rd_address_phase_order.delete( idx[0] );
			end
		end



		tr = outstanding_rd_trans[id][0];

		check_xz_read_data();
		sample_read_data(tr);
		tr.burst_index++;

		check_data_phase(tr);

		if(tr.got_last_beat)
		begin
			--num_outstanding_rd;
			outstanding_rd_trans[id].delete(0);
			close_and_send_transaction(tr);
		end
	end
endtask : rdata_phase_monitor


function void ovip_axi_monitor::send_rsp_req(ovip_axi_trans tr);
	ovip_axi_trans rsp_req = ovip_axi_trans::type_id::create("rsp_req");
	rsp_req.copy(tr);
	pending_rsp_req.push_back(rsp_req);
endfunction : send_rsp_req


task ovip_axi_monitor::get(output ovip_axi_trans tr);
	// Loop in case the queue is cleared by rst_monitor between the wait satisfying
	// and our pop_front -- pop_front on an empty queue would hand the slave
	// sequence a default-constructed (null-handle) trans.
	forever begin
		wait(pending_rsp_req.size());
		if(pending_rsp_req.size()) begin
			tr = pending_rsp_req.pop_front();
			return;
		end
	end
endtask : get



function void ovip_axi_monitor::report_phase(uvm_phase phase);
	super.report_phase(phase);

	foreach(outstanding_rd_trans[id,ii])
		`uvm_error("AXI_MON/INCOMPLETE_RD_TRANS",$sformatf("Transactions did not complete before the test was terminated: %s", outstanding_rd_trans[id][ii].convert2string()) )

	foreach(outstanding_wr_trans[id,ii])
		`uvm_error("AXI_MON/INCOMPLETE_WR_TRANS",$sformatf("Transactions did not complete before the test was terminated: %s", outstanding_wr_trans[id][ii].convert2string()) )

	foreach(outstanding_wr_trans_wo_addr_phase[id,ii])
		`uvm_error("AXI_MON/INCOMPLETE_WR_TRANS",$sformatf("Transactions did not complete(missing address phase) before the test was terminated: %s", outstanding_wr_trans_wo_addr_phase[id][ii].convert2string()))

	foreach(wr_trans_waiting_for_response[id,ii])
		`uvm_error("AXI_MON/INCOMPLETE_WR_TRANS",$sformatf("Transactions did not complete(missing response) before the test was terminated: %s", wr_trans_waiting_for_response[id][ii].convert2string()) )
endfunction : report_phase

`endif
