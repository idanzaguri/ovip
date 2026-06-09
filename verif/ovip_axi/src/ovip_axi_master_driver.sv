`ifndef OVIP_AXI_MASTER_DRIVER__SV
`define OVIP_AXI_MASTER_DRIVER__SV

class ovip_axi_master_driver #(type IF_T = virtual ovip_axi_agent_if) extends ovip_axi_base_driver #(IF_T);

	// Signal masks - used to sample and drive only the relevant portions of the signal
	// because signal widths are set to the maximum supported length.
	ovip_axi_addr_t ADDR_MASK;
	ovip_axi_data_t DATA_MASK;
	ovip_axi_data_t STRB_MASK;
	ovip_axi_id_t WR_ID_MASK;
	ovip_axi_id_t RD_ID_MASK;
	ovip_axi_user_t AWUSER_MASK;
	ovip_axi_user_t WUSER_MASK;
	ovip_axi_user_t BUSER_MASK;
	ovip_axi_user_t ARUSER_MASK;
	ovip_axi_user_t RUSER_MASK;



	// Queue for read transactions that are ready for the address phase driving.
	// Used for moving tranactions from the transaction_acceptor thread to the raddr_phase_driver thread.
	ovip_axi_trans pending_rd_tr[$];

	// Queues (per ID) for outstanding read transactions (i.e., address phase has already been driven).
	// Used for moving transactions from the raddr_phase_driver thread to the rdata_phase_driver thread.
	ovip_axi_trans outstanding_rd_tr[ovip_axi_id_t][$];



	// Queue for write transactions that are ready for the address phase driving.
	// Used for moving tranactions from the transaction_acceptor thread to the waddr_phase_driver thread.
	ovip_axi_trans pending_wr_tr[$];

	// Queues for write transactions that are ready for the data phase before the address phase.
	ovip_axi_trans pending_tr_with_data_before_addr[$];
	int pending_tr_with_data_before_addr_delay[$]; // Holds tr.addr_phase_delay

	// Queues (per ID) for write transactions waiting for a response (i.e., LAST transfer has been sampled).
	// Used to move transactions from the wdata_phase_driver thread to the bresp_phase_driver thread.
	ovip_axi_trans waiting_for_bresp_tr[ovip_axi_id_t][$];

	// Out-of-Order Queue - used by the wdata_phase_driver thread.
	// This queue manages and schedules transfers according to the following configurations:
	// wr_out_of_order_depth, wr_interleave_depth, and wr_scheduling_alg.
	ovip_axi_out_of_order_queue outstanding_wr_tr;


	mailbox#(ovip_axi_ready_pattern_t) rready_pattern_mb;
	mailbox#(ovip_axi_ready_pattern_t) bready_pattern_mb;
	
	task put_rready_pattern(int unsigned c[$], bit repeat_pattern = 0);
		ovip_axi_ready_pattern_t p = '{cycles:c, loop: repeat_pattern};
		rready_pattern_mb.put(p);
	endtask
	task put_bready_pattern(int unsigned c[$], bit repeat_pattern = 0);
		ovip_axi_ready_pattern_t p = '{cycles:c, loop: repeat_pattern};
		bready_pattern_mb.put(p);
	endtask

	`uvm_component_param_utils( ovip_axi_master_driver#(IF_T) )

	function new(string name = "ovip_axi_master_driver", uvm_component parent);
		super.new(name, parent);
		rready_pattern_mb = new();
		bready_pattern_mb = new();
	endfunction : new

	extern virtual function void build_phase(uvm_phase phase);

	extern virtual function void reset_internal_state();
	extern virtual function void drive_reset_values();

	// Tasks and functions for handling read channels.
	extern virtual task raddr_phase_driver();
	extern virtual task rdata_phase_driver();
	extern virtual task rready_signal_driver();
	extern virtual function void drive_ar_channel_reset_values();
	extern virtual function void drive_ar_channel(ovip_axi_trans tr);
	extern virtual function void sample_rd_response(ovip_axi_trans tr);

	// Tasks and functions for handling write channels.
	extern virtual task waddr_phase_driver();
	extern virtual task wdata_phase_driver();
	extern virtual task bresp_phase_driver();
	extern virtual task bready_signal_driver();
	extern virtual function void drive_aw_channel_reset_values();
	extern virtual function void drive_w_channel_reset_values();
	extern virtual function void drive_aw_channel(ovip_axi_trans tr);
	extern virtual function void drive_w_channel(ovip_axi_trans tr);

	// Manages the `outstanding_wr_tr` out-of-order queue and transactions with data before address phase.
	extern virtual task outstanding_wr_tr_queue_manager();

	// Thread for managing and scheduling transactions from the sequencer.
	extern virtual task transaction_acceptor();

	extern virtual function bit check_write_trans_validity(ovip_axi_trans tr);
	extern virtual function bit check_read_trans_validity(ovip_axi_trans tr);
	extern virtual function bit check_trans_validity(ovip_axi_trans tr);

endclass : ovip_axi_master_driver


function void ovip_axi_master_driver::build_phase(uvm_phase phase);
	super.build_phase(phase);

	outstanding_wr_tr = ovip_axi_out_of_order_queue::type_id::create("outstanding_wr_tr");
	outstanding_wr_tr.reorder_depth      = cfg.wr_out_of_order_depth;
	outstanding_wr_tr.interleaving_depth = cfg.wr_interleave_depth;
	outstanding_wr_tr.scheduling_alg     = cfg.wr_scheduling_alg;
	outstanding_wr_tr.q_type_is_wr_data = 1;

	// Setting signal masks based on the configuration object.
	ADDR_MASK = (ovip_axi_addr_t'(1)<<cfg.addr_width)-1;
	DATA_MASK = (ovip_axi_data_t'(1)<<cfg.bus_width*8)-1;
	STRB_MASK = (ovip_axi_data_t'(1)<<(cfg.bus_width))-1;
	WR_ID_MASK = (ovip_axi_id_t'(1)<<cfg.wr_id_width)-1;
	RD_ID_MASK = (ovip_axi_id_t'(1)<<cfg.rd_id_width)-1;

	AWUSER_MASK = (ovip_axi_user_t'(1)<<cfg.awuser_width)-1;
	WUSER_MASK  = (ovip_axi_user_t'(1)<<cfg.wuser_width) -1;
	BUSER_MASK  = (ovip_axi_user_t'(1)<<cfg.buser_width) -1;
	ARUSER_MASK = (ovip_axi_user_t'(1)<<cfg.aruser_width)-1;
	RUSER_MASK  = (ovip_axi_user_t'(1)<<cfg.ruser_width) -1;
endfunction : build_phase


function void ovip_axi_master_driver::reset_internal_state();
	super.reset_internal_state();
	// Resets all internal data structures.
	pending_rd_tr.delete();
	outstanding_rd_tr.delete();
	pending_wr_tr.delete();
	pending_tr_with_data_before_addr.delete();
	pending_tr_with_data_before_addr_delay.delete();
	waiting_for_bresp_tr.delete();
	outstanding_wr_tr.reset();
	// Flush ready-pattern mailboxes so pre-reset patterns don't survive into post-reset.
	begin
		ovip_axi_ready_pattern_t _drain;
		while(rready_pattern_mb.try_get(_drain));
		while(bready_pattern_mb.try_get(_drain));
	end
endfunction : reset_internal_state


function void ovip_axi_master_driver::drive_reset_values();
	vif.master_cb.arvalid <= 0;
	vif.master_cb.awvalid <= 0;
	vif.master_cb.wvalid  <= 0;
	vif.master_cb.bready <= 0;
	vif.master_cb.rready <= 0;
endfunction : drive_reset_values

// ----------------------------------------------------------------- //
//                           Read channel                            //
//                         Functions & Tasks                         //
// ----------------------------------------------------------------- //

function void ovip_axi_master_driver::drive_ar_channel_reset_values();
	vif.master_cb.araddr <= 0;
	if(cfg.rd_id_width) vif.master_cb.arid <= 0;
	if(cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE) return;

	vif.master_cb.arlen   <= 0;
	vif.master_cb.arsize  <= 0;
	vif.master_cb.arburst <= 0;

	if(cfg.aruser_width) vif.master_cb.aruser   <= 0;
	if(cfg.arlock_en)    vif.master_cb.arlock   <= 0;
	if(cfg.arcache_en)   vif.master_cb.arcache  <= 0;
	if(cfg.arprot_en)    vif.master_cb.arprot   <= 0;
	if(cfg.arqos_en)     vif.master_cb.arqos    <= 0;
	if(cfg.arregion_en)  vif.master_cb.arregion <= 0;

endfunction : drive_ar_channel_reset_values


function void ovip_axi_master_driver::drive_ar_channel(ovip_axi_trans tr);
	vif.master_cb.araddr <= tr.addr;
	if(cfg.rd_id_width) vif.master_cb.arid <= tr.id;
	if(cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE) return;

	vif.master_cb.arlen   <= tr.len;
	vif.master_cb.arsize  <= tr.size;
	vif.master_cb.arburst <= tr.burst;

	if(cfg.aruser_width) vif.master_cb.aruser   <= tr.aruser;
	if(cfg.arlock_en)    vif.master_cb.arlock   <= tr.axlock;
	if(cfg.arcache_en)   vif.master_cb.arcache  <= tr.axcache;
	if(cfg.arprot_en)    vif.master_cb.arprot   <= tr.axprot;
	if(cfg.arqos_en)     vif.master_cb.arqos    <= tr.axqos;
	if(cfg.arregion_en)  vif.master_cb.arregion <= tr.axregion;

endfunction : drive_ar_channel


task ovip_axi_master_driver::raddr_phase_driver();
	ovip_axi_trans tr;

	vif.master_cb.arvalid <= 0;
	if(cfg.drive_reset_values_when_idle)
		drive_ar_channel_reset_values();

	forever
	begin
		wait(pending_rd_tr.size());
		tr = pending_rd_tr.pop_front();

		drive_ar_channel(tr);

		vif.master_cb.arvalid <= 1;
		@(vif.master_cb iff vif.master_cb.arready /*&& vif.monitor_cb.arvalid*/);
		vif.master_cb.arvalid <= 0;

		if(cfg.drive_reset_values_when_idle)
			drive_ar_channel_reset_values();

		tr.valid_address_phase = 1;
		outstanding_rd_tr[tr.id].push_back(tr);

		repeat(tr.delay_until_next_addr) @(vif.master_cb);
	end
endtask : raddr_phase_driver


function void ovip_axi_master_driver::sample_rd_response(ovip_axi_trans tr);

	ovip_axi_data_t	rdata = vif.master_cb.rdata & DATA_MASK;
	if(cfg.auto_byte_lanes_alignment && (tr.is_narrow_transfer || tr.burst_index == 0))
			rdata >>= tr.transfer_starting_byte_lane[tr.burst_index]*8;
	tr.data_beats[tr.burst_index] = rdata;

	// Sample RLAST and RRESP
	if(vif.master_cb.rlast || cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE)
	begin
		tr.got_last_beat = 1'b1;
		tr.resp = ovip_axi_resp_t'(vif.master_cb.rresp);
	end

	if(cfg.ruser_width) tr.ruser = vif.master_cb.ruser & RUSER_MASK;
endfunction : sample_rd_response


task ovip_axi_master_driver::rready_signal_driver();
	ovip_axi_ready_pattern_t ready_pattern = cfg.default_rready_pattern;
	forever begin
		if(ready_pattern.cycles.sum() == 0) begin
			`uvm_warning("OVIP_AXI/READY_PATTERN", "rready pattern cycles[] sum to 0 -- falling back to '{cycles:'{0,1}, loop:0} (always-ready)")
			ready_pattern = '{cycles:'{0,1}, loop:0};
		end
		`BEGIN_FIRST_OF
			rready_pattern_mb.get(ready_pattern);
			forever
			begin
				foreach(ready_pattern.cycles[ii])
				begin
					vif.master_cb.rready <= bit'(ii);
					repeat(ready_pattern.cycles[ii]) @(vif.master_cb);
				end
				if(!ready_pattern.loop) wait(0);
			end
		`END_FIRST_OF
	end
endtask : rready_signal_driver


task ovip_axi_master_driver::rdata_phase_driver();
	ovip_axi_id_t rid;

	fork
		rready_signal_driver();
	join_none

	forever
	begin
		@(vif.master_cb iff vif.monitor_cb.rready && vif.master_cb.rvalid);
		rid = vif.master_cb.rid & RD_ID_MASK;

		if(!outstanding_rd_tr.exists(rid) || outstanding_rd_tr[rid].size() == 0)
		begin
			`uvm_error("AXI_MASTER_DRV/RDATA", $sformatf("Got read data beat with unknown ID(0x%x)", rid))
		end
		else
		begin
			ovip_axi_trans tr = outstanding_rd_tr[rid][0];
			sample_rd_response(tr);
			tr.burst_index++;

			if(tr.got_last_beat)
			begin
				// Last beat received: drop the completed transaction from the outstanding queue
				// and return it as the response. tr is the original request (ids intact for
				// get_response routing) and is not mutated after this put.
				void'(outstanding_rd_tr[rid].pop_front());
				seq_item_port.put(tr);
			end
		end
	end

endtask : rdata_phase_driver


// ----------------------------------------------------------------- //
//                           Write channel                           //
//                         Functions & Tasks                         //
// ----------------------------------------------------------------- //

function void ovip_axi_master_driver::drive_aw_channel_reset_values();
	vif.master_cb.awaddr <= 0;
	if(cfg.awuser_width) vif.master_cb.awuser <= 0;
	if(cfg.wr_id_width)  vif.master_cb.awid   <= 0;

	if(cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE) return;

	vif.master_cb.awlen   <= 0;
	vif.master_cb.awsize  <= 0;
	vif.master_cb.awburst <= 0;

	if(cfg.awlock_en)   vif.master_cb.awlock   <= 0;
	if(cfg.awcache_en)  vif.master_cb.awcache  <= 0;
	if(cfg.awprot_en)   vif.master_cb.awprot   <= 0;
	if(cfg.awqos_en)    vif.master_cb.awqos    <= 0;
	if(cfg.awregion_en) vif.master_cb.awregion <= 0;
endfunction : drive_aw_channel_reset_values


function void ovip_axi_master_driver::drive_aw_channel(ovip_axi_trans tr);
	vif.master_cb.awaddr  <= tr.addr;
	if(cfg.awuser_width) vif.master_cb.awuser <= tr.awuser;
	if(cfg.wr_id_width)  vif.master_cb.awid   <= tr.id;

	if(cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE) return;

	vif.master_cb.awlen   <= tr.len;
	vif.master_cb.awsize  <= tr.size;
	vif.master_cb.awburst <= tr.burst;

	if(cfg.awlock_en)   vif.master_cb.awlock   <= tr.axlock;
	if(cfg.awcache_en)  vif.master_cb.awcache  <= tr.axcache;
	if(cfg.awprot_en)   vif.master_cb.awprot   <= tr.axprot;
	if(cfg.awqos_en)    vif.master_cb.awqos    <= tr.axqos;
	if(cfg.awregion_en) vif.master_cb.awregion <= tr.axregion;
endfunction : drive_aw_channel


function void ovip_axi_master_driver::drive_w_channel_reset_values();
	if(cfg.wuser_width) vif.master_cb.wuser <= 0;
	vif.master_cb.wdata <= 0;
	vif.master_cb.wstrb <= 0;
	if(cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE) return;
	vif.master_cb.wlast <= 0;
	if(cfg.wr_id_width && cfg.protocol_type == OVIP_PROTOCOL_AXI3) vif.master_cb.wid <= 0;
endfunction : drive_w_channel_reset_values


function void ovip_axi_master_driver::drive_w_channel(ovip_axi_trans tr);
	if(cfg.auto_byte_lanes_alignment && (tr.is_narrow_transfer || tr.burst_index == 0))
	begin
		vif.master_cb.wdata <= tr.data_beats[tr.burst_index]<<tr.transfer_starting_byte_lane[tr.burst_index]*8;
		vif.master_cb.wstrb <= tr.strb_beats[tr.burst_index]<<tr.transfer_starting_byte_lane[tr.burst_index];
	end
	else
	begin
		vif.master_cb.wdata <= tr.data_beats[tr.burst_index];
		vif.master_cb.wstrb <= tr.strb_beats[tr.burst_index];
	end

	if(cfg.wuser_width) vif.master_cb.wuser <= tr.wuser;

	if(cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE) return;

	if(cfg.wr_id_width && cfg.protocol_type == OVIP_PROTOCOL_AXI3) vif.master_cb.wid <= tr.id;
	vif.master_cb.wlast <= (tr.burst_index == tr.len);
endfunction : drive_w_channel


task ovip_axi_master_driver::outstanding_wr_tr_queue_manager();
	fork

		// Thread for decrementing `pending_tr_with_data_before_addr_delay` for each transaction
		// where the address phase has already started.
		forever
		begin
			wait(pending_tr_with_data_before_addr.size());
			@(negedge vif.aclk);

			foreach(pending_tr_with_data_before_addr[idx])
			begin
				if(pending_tr_with_data_before_addr[idx].data_phase_started && pending_tr_with_data_before_addr_delay[idx])
					--pending_tr_with_data_before_addr_delay[idx];
			end
			//@(vif.master_cb);
		end

		// Thread for managing outstanding write transactions (`outstanding_wr_tr`).
		forever
		begin
			// This thread shares the master_cb event with waddr_phase_driver, which
			// pushes newly accepted transactions into outstanding_wr_tr on the same
			// clocking edge. Without the trailing #0, schedule_next() could run before
			// the producer's push and miss the just-pushed transaction, deferring it
			// by a full cycle. The #0 placed *after* @(vif.master_cb) re-schedules
			// this thread to run after every other thread that woke on the same edge,
			// so the producer's push is always visible here.
			outstanding_wr_tr.tick_delays();
			@(vif.master_cb);
			#0;
			outstanding_wr_tr.schedule_next();
		end
	join_none

endtask : outstanding_wr_tr_queue_manager


task ovip_axi_master_driver::waddr_phase_driver();

	outstanding_wr_tr_queue_manager(); // Initiate outstanding_wr_tr_queue_manager thread

	vif.master_cb.awvalid <= 0;
	if(cfg.drive_reset_values_when_idle)
		drive_aw_channel_reset_values();

	forever
	begin
		ovip_axi_trans tr;
		bit addr_before_data_tr_ready = 0;

		// Wait until at least one transaction in queues
		wait(pending_wr_tr.size() || pending_tr_with_data_before_addr.size());


		addr_before_data_tr_ready = (
			pending_tr_with_data_before_addr.size()
			&&
			pending_tr_with_data_before_addr[0].data_phase_started
			&&
			pending_tr_with_data_before_addr_delay[0] == 0);



		if(addr_before_data_tr_ready)
		begin
			tr = pending_tr_with_data_before_addr.pop_front();
			pending_tr_with_data_before_addr_delay.delete(0);
		end
		else if(pending_wr_tr.size() == 0)
		begin
			// If there are no ready transactions, wait one cycle and then continue.
			@(vif.master_cb);
			continue;
		end
		else
		begin
			tr = pending_wr_tr.pop_front();

			// Push transaction to the out-of-order queue.
			outstanding_wr_tr.push(tr, {tr.data_delay}, tr.len);

			// To support simultaneous address and data phases,
			// apply the schedule_next immediately instead of waiting for the next clocking block event.
			if(tr.data_start_event == OVIP_AXI_DATA_START_EV_ADDR_DRIVEN)
				outstanding_wr_tr.schedule_next();

			if(tr.data_start_event == OVIP_AXI_DATA_START_EV_BEFORE_ADDR)
			begin
				pending_tr_with_data_before_addr.push_back(tr);
				pending_tr_with_data_before_addr_delay.push_back(tr.addr_phase_delay);
				continue;
			end
		end

		drive_aw_channel(tr);

		vif.master_cb.awvalid <= 1;
		@(vif.master_cb iff vif.master_cb.awready /*&& vif.monitor_cb.awvalid*/);
		tr.valid_address_phase = 1;
		vif.master_cb.awvalid <= 0;

		if(cfg.drive_reset_values_when_idle)
			drive_aw_channel_reset_values();

		repeat(tr.delay_until_next_addr) @(vif.master_cb);
	end
endtask : waddr_phase_driver



task ovip_axi_master_driver::wdata_phase_driver();
	ovip_axi_trans tr;

	vif.master_cb.wvalid <= 0;
	if(cfg.drive_reset_values_when_idle)
		drive_w_channel_reset_values();

	forever
	begin
		outstanding_wr_tr.pop(tr);

		// If `data_start_event` is `OVIP_AXI_DATA_START_EV_ADDR_SAMPLED` and this is the first beat,
		// wait until the address phase has been sampled.
		if(tr.burst_index == 0 && tr.data_start_event == OVIP_AXI_DATA_START_EV_ADDR_SAMPLED)
			wait(tr.valid_address_phase);

		tr.data_phase_started = 1;

		drive_w_channel(tr);
		vif.master_cb.wvalid <= 1;
		// We drove wvalid above, so the W handshake completes as soon as wready is sampled high.
		@(vif.master_cb iff vif.master_cb.wready);
		vif.master_cb.wvalid <= 0;

		if(cfg.drive_reset_values_when_idle)
			drive_w_channel_reset_values();

		if(tr.burst_index++ == tr.len) // transaction data phase finished
		begin
			waiting_for_bresp_tr[tr.id].push_back(tr);
			repeat(tr.delay_until_next_data) @(vif.master_cb);
		end
	end
endtask : wdata_phase_driver



task ovip_axi_master_driver::bready_signal_driver();
	ovip_axi_ready_pattern_t ready_pattern = cfg.default_bready_pattern;
	forever begin
		if(ready_pattern.cycles.sum() == 0) begin
			`uvm_warning("OVIP_AXI/READY_PATTERN", "bready pattern cycles[] sum to 0 -- falling back to '{cycles:'{0,1}, loop:0} (always-ready)")
			ready_pattern = '{cycles:'{0,1}, loop:0};
		end
		`BEGIN_FIRST_OF
			bready_pattern_mb.get(ready_pattern);
			forever
			begin
				foreach(ready_pattern.cycles[ii])
				begin
					vif.master_cb.bready <= bit'(ii);
					repeat(ready_pattern.cycles[ii]) @(vif.master_cb);
				end
				if(!ready_pattern.loop) wait(0);
			end
		`END_FIRST_OF
	end
endtask : bready_signal_driver



task ovip_axi_master_driver::bresp_phase_driver();
	ovip_axi_id_t bid;

	fork
		bready_signal_driver();
	join_none

	// bresp monitor
	forever
	begin
		@(vif.master_cb iff vif.monitor_cb.bready && vif.master_cb.bvalid);

		bid = vif.master_cb.bid & WR_ID_MASK;

		if(!waiting_for_bresp_tr.exists(bid) || waiting_for_bresp_tr[bid].size() == 0)
		begin
			`uvm_error("AXI_MASTER_DRV/BRESP", $sformatf("Got write response with unknown ID(0x%x)", bid))
		end
		else
		begin
			// Return the completed write request as the response (ids intact for routing;
			// not mutated after this put).
			ovip_axi_trans tr = waiting_for_bresp_tr[bid].pop_front();

			tr.resp = ovip_axi_resp_t'(vif.master_cb.bresp);
			tr.buser = vif.master_cb.buser & BUSER_MASK;
			seq_item_port.put(tr);
		end
	end

endtask : bresp_phase_driver

//
// `check_trans_validity` functions
// Note that these functions perform basic checks required for proper driving operation.
// Full verification of the transaction will be handled by the monitor.
//
function bit ovip_axi_master_driver::check_write_trans_validity(ovip_axi_trans tr);
	bit err_flag = 0;
	`OVIP_CHECK_VALUE_VS_SIGNAL_WIDTH("TR_CHK", "AWUSER", tr.awuser, cfg.awuser_width, err_flag)
	`OVIP_CHECK_VALUE_VS_SIGNAL_WIDTH("TR_CHK", "WUSER",  tr.wuser,  cfg.wuser_width,  err_flag)
	`OVIP_CHECK_VALUE_VS_SIGNAL_WIDTH("TR_CHK", "ID",     tr.id,     cfg.wr_id_width,  err_flag)

	if(tr.len+1 > tr.data_beats.size())
	begin
		err_flag = 1;
		`uvm_warning("TR_CHK", $sformatf("Number of data beats(%0d) smaller than burst length (%0d)", tr.data_beats.size(), tr.len+1))
	end
	if(tr.len+1 > tr.strb_beats.size())
	begin
		err_flag = 1;
		`uvm_warning("TR_CHK", $sformatf("Number of wstrb beats(%0d) smaller than burst length (%0d)", tr.strb_beats.size(), tr.len+1))
	end

	foreach(tr.data_beats[ii])
		`OVIP_CHECK_VALUE_VS_SIGNAL_WIDTH("TR_CHK", $sformatf("data_beats[%0d]",ii), tr.data_beats[ii], cfg.bus_width*8, err_flag)

	return err_flag;
endfunction

function bit ovip_axi_master_driver::check_read_trans_validity(ovip_axi_trans tr);
	bit err_flag = 0;
	`OVIP_CHECK_VALUE_VS_SIGNAL_WIDTH("TR_CHK", "ID",     tr.id,    cfg.rd_id_width,  err_flag)
	return err_flag;
endfunction

function bit ovip_axi_master_driver::check_trans_validity(ovip_axi_trans tr);
	bit err_flag;
	`OVIP_CHECK_VALUE_VS_SIGNAL_WIDTH("TR_CHK", "ADDR", tr.addr, cfg.addr_width, err_flag)
	`OVIP_CHECK_VALUE_VS_SIGNAL_WIDTH("TR_CHK", "LEN",  tr.len,  cfg.len_width,  err_flag)

	if(2**tr.size > int'(cfg.bus_width))
	begin
		err_flag = 1;
		`uvm_warning("TR_CHK", $sformatf("AxSIZE=%0d(%0dB) > BUS_WIDTH=%0dB",tr.size,2**tr.size,int'(cfg.bus_width)))
	end

	if(cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE)
	begin
		if(tr.len != 0)
		begin
			err_flag = 1;
			`uvm_warning("TR_CHK", $sformatf("On AXI4-Lite, AxLEN(%0d) must be 0!",tr.len))
		end
		if(2**tr.size != int'(cfg.bus_width))
		begin
			err_flag = 1;
			`uvm_warning("TR_CHK", $sformatf("On AXI4-Lite AxSIZE=%0d(%0dB) must be equal to BUS_WIDTH(%0dB)",tr.size,2**tr.size,int'(cfg.bus_width)))
		end
	end

	if(tr.data_delay.size() > tr.data_beats.size())
	begin
		err_flag = 1;
		`uvm_warning("TR_CHK", $sformatf("data_delay size (%0d) is bigger than transaction length",tr.data_delay.size()))
	end

	if(tr.tr_type == OVIP_AXI_WRITE_TRANS) begin
		err_flag |= check_write_trans_validity(tr);
		if(cfg.interface_type == OVIP_AXI_READ_ONLY_INTERFACE) begin
			err_flag = 1;
			`uvm_warning("TR_CHK", "Attempt to send WRITE transaction but agent is OVIP_AXI_READ_ONLY_INTERFACE")
		end
	end
	else begin
		err_flag |= check_read_trans_validity(tr);
		if(cfg.interface_type == OVIP_AXI_WRITE_ONLY_INTERFACE) begin
			err_flag = 1;
			`uvm_warning("TR_CHK", "Attempt to send READ transaction but agent is OVIP_AXI_WRITE_ONLY_INTERFACE")
		end
	end

	return err_flag;
endfunction : check_trans_validity


//
// `transaction_acceptor`:
// Fetches requests from `seq_item_port` and schedules them to the relevant channel driver
// based on the outstanding configuration.
//
task ovip_axi_master_driver::transaction_acceptor();

	int num_outstanding_wr = 0;
	int num_outstanding_rd = 0;

	ovip_axi_trans queued_trans[$];
	ovip_axi_trans req_fifo[$];


	// Thread for popping transactions from the sequencer.
	// The main purpose of this thread is to eliminate Head-of-Line (HoL) blocking caused by the number of outstanding transactions limitation.
	// For example, if the first element in the `seq_item_port` FIFO is a READ transaction but cannot be driven due to `num_outstanding_rd` being greater than `cfg.num_outstanding_rd_transactions`,
	// this thread allows WRITE transactions further down the FIFO to be driven.
	fork
		forever
		begin
			seq_item_port.get(req);

			// Initialize transaction state variables.
			req.init_state_variables();
			req.bus_width = cfg.bus_width;
			req.is_narrow_transfer = (ovip_axi_bus_width_t'(2**req.size) != cfg.bus_width);
			// Calculate byte lanes alignment offsets if needed.
			if(cfg.auto_byte_lanes_alignment)
				req.calculate_transfer_starting_byte_lane();
			
			// Verify that the transaction is valid.
			if(check_trans_validity(req) && !req.trust_me_i_am_an_engineer)
				`uvm_fatal("AXI_MASTER_DRV", "Something is wrong with this transaction. Check the UVM_WARNINGs above for details")

			req_fifo.push_back(req);
		end
	join_none


	forever
	begin
		@(vif.master_cb iff
			// End of READ transaction - a new READ slot is now available!
			(vif.master_cb.rvalid && vif.monitor_cb.rready && (vif.master_cb.rlast || cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE))
			||
			// End of WRITE transaction - a new WRITE slot is now available!
			(vif.master_cb.bvalid && vif.monitor_cb.bready)
			||
			// There is a pending transation
			(req_fifo.size() || queued_trans.size())
		);


		// Checks for finished transactions and updates the `num_outstanding_*` variables accordingly.
		if(vif.master_cb.rvalid && vif.monitor_cb.rready && (vif.master_cb.rlast || cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE)) --num_outstanding_rd;
		if(vif.master_cb.bvalid && vif.monitor_cb.bready) --num_outstanding_wr;


		while( // There are transactions and available slots for them

			(req_fifo.size() || queued_trans.size())
			&&
			(
				// Total outstanding transactions is within the limit
				cfg.num_outstanding_transactions == 0
				||
				(num_outstanding_wr + num_outstanding_rd < cfg.num_outstanding_transactions)
			)
			&&
			(
				(// Number of outstanding writes is within the limit
					cfg.num_outstanding_wr_transactions == 0
					||
					num_outstanding_wr < cfg.num_outstanding_wr_transactions
				)
				||
				(// Number of outstanding reads is within the limit
					cfg.num_outstanding_rd_transactions == 0
					||
					num_outstanding_rd < cfg.num_outstanding_rd_transactions
				)
			)
		)
		begin
			ovip_axi_trans tr = null;
			bit available_slot[2];

			// Check which channel has an open slot for a transaction.
			// `pending_wr_tr.size() == 0` indicates that the address channel driver is in an idle state.
			available_slot[OVIP_AXI_WRITE_TRANS] = (cfg.num_outstanding_wr_transactions == 0) ||
				(num_outstanding_wr < cfg.num_outstanding_wr_transactions);
			available_slot[OVIP_AXI_READ_TRANS ] = (cfg.num_outstanding_rd_transactions == 0) ||
				(num_outstanding_rd < cfg.num_outstanding_rd_transactions);


			// Break if `req_fifo` (seq_item_port) is empty and there are no available slots for the queued transactions.
			if(!req_fifo.size() && !available_slot[ queued_trans[0].tr_type ]) break;


			// First, check if there are any pending transactions in the `queued_trans` queue.
			// This queue holds only one type of transaction at a time.
			// `queued_trans` stores transactions that exceed `num_outstanding_*_transactions`
			// or if the relevant address channel driver is not in an idle state.
			if (queued_trans.size() && available_slot[queued_trans[0].tr_type])
			begin
				tr = queued_trans.pop_front();
			end


			// If `queued_trans` is empty or the queued transaction cannot be sent to the relevant driver,
			// attempt to pop a transaction from `req_fifo`.
			while(tr == null && req_fifo.size())
			begin
				// If the transaction type is already queued or the driver is blocked,
				// push this transaction to `queued_trans`.
				if(
					(queued_trans.size() && (req_fifo[0].tr_type == queued_trans[0].tr_type) )
					||
					(!available_slot[ req_fifo[0].tr_type ])
				)
				begin
					// Assertion to verify that `queued_trans` contains only one type of transaction at a time.
					if(queued_trans.size() && (req_fifo[0].tr_type != queued_trans[0].tr_type) )
						`uvm_fatal("SIM_ASSERT", $sformatf("Cannot push %s to `queued_trans` because it already contains a different type of transaction", req_fifo[0].tr_type.name()))

					queued_trans.push_back( req_fifo.pop_front() );
				end
				else
				begin
					tr = req_fifo.pop_front();
				end
			end

			if(tr == null) continue;

			// Update ready signal drivers with new patterns if available.
			if(tr.rready_pattern.cycles.size()) rready_pattern_mb.put(tr.rready_pattern);
			if(tr.bready_pattern.cycles.size()) bready_pattern_mb.put(tr.bready_pattern);

			// Push the transaction to the relevant pending transactions queue.
			if(tr.tr_type == OVIP_AXI_WRITE_TRANS)
			begin
				++num_outstanding_wr;
				pending_wr_tr.push_back(tr);
			end
			else
			begin
				++num_outstanding_rd;
				pending_rd_tr.push_back( tr );
			end
		end
	end

endtask : transaction_acceptor

`endif
