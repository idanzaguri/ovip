`ifndef OVIP_AXI_SLAVE_DRIVER__SV
`define OVIP_AXI_SLAVE_DRIVER__SV

class ovip_axi_slave_driver #(type IF_T = virtual ovip_axi_agent_if) extends ovip_axi_base_driver #(IF_T);

	ovip_axi_data_t DATA_MASK;
	ovip_axi_id_t WR_ID_MASK;
	ovip_axi_id_t RD_ID_MASK;
	ovip_axi_user_t BUSER_MASK;
	ovip_axi_user_t RUSER_MASK;

	ovip_axi_out_of_order_queue outstanding_rd_tr; // data
	ovip_axi_out_of_order_queue outstanding_wr_tr; // bresp


	mailbox#(ovip_axi_ready_pattern_t) arready_pattern_mb;
	mailbox#(ovip_axi_ready_pattern_t) awready_pattern_mb;
	mailbox#(ovip_axi_ready_pattern_t) wready_pattern_mb;

	task put_arready_pattern(int unsigned c[$], bit repeat_pattern = 0);
		ovip_axi_ready_pattern_t p = '{cycles:c, loop: repeat_pattern};
		arready_pattern_mb.put(p);
	endtask
	task put_awready_pattern(int unsigned c[$], bit repeat_pattern = 0);
		ovip_axi_ready_pattern_t p = '{cycles:c, loop: repeat_pattern};
		awready_pattern_mb.put(p);
	endtask
	task put_wready_pattern(int unsigned c[$], bit repeat_pattern = 0);
		ovip_axi_ready_pattern_t p = '{cycles:c, loop: repeat_pattern};
		wready_pattern_mb.put(p);
	endtask


	`uvm_component_param_utils( ovip_axi_slave_driver#(IF_T) )

	function new(string name = "ovip_axi_slave_driver", uvm_component parent);
		super.new(name, parent);
		arready_pattern_mb = new();
		awready_pattern_mb = new();
		wready_pattern_mb = new();
	endfunction : new

	extern virtual function void build_phase(uvm_phase phase);

	extern virtual function void reset_internal_state();

	extern virtual task transaction_acceptor();

	extern virtual task raddr_phase_driver(); // target
	extern virtual task rdata_phase_driver(); // initiator

	extern virtual task waddr_phase_driver(); // target
	extern virtual task wdata_phase_driver(); // target
	extern virtual task bresp_phase_driver(); // initator

	extern virtual function void drive_reset_values();
	extern virtual function ovip_axi_data_t idle_value(int bits = 64);
	extern virtual task awready_after_wvalid_driver();

	extern virtual function void drive_r_channel_reset_values();
	extern virtual function void drive_b_channel_reset_values();

	extern virtual function void drive_wr_resp(ovip_axi_trans tr);
	extern virtual function void drive_rd_channel(ovip_axi_trans tr);

	extern virtual function bit check_write_trans_validity(ovip_axi_trans tr);
	extern virtual function bit check_read_trans_validity(ovip_axi_trans tr);
	extern virtual function bit check_trans_validity(ovip_axi_trans tr);

endclass : ovip_axi_slave_driver


function void ovip_axi_slave_driver::build_phase(uvm_phase phase);
	super.build_phase(phase);

	outstanding_wr_tr = ovip_axi_out_of_order_queue::type_id::create("outstanding_wr_tr");
	outstanding_wr_tr.reorder_depth      = cfg.wr_resp_out_of_order_depth;
	outstanding_wr_tr.interleaving_depth = 1;
	outstanding_wr_tr.scheduling_alg     = cfg.wr_scheduling_alg;

	outstanding_rd_tr = ovip_axi_out_of_order_queue::type_id::create("outstanding_rd_tr");
	outstanding_rd_tr.reorder_depth      = cfg.rd_out_of_order_depth;
	outstanding_rd_tr.interleaving_depth = cfg.rd_interleave_depth;
	outstanding_rd_tr.scheduling_alg     = cfg.rd_scheduling_alg;

	// setting signal masks according to cfg object
	DATA_MASK  = (ovip_axi_data_t'(1)<<cfg.bus_width*8)-1;
	WR_ID_MASK = (ovip_axi_id_t'(1)<<cfg.wr_id_width)-1;
	RD_ID_MASK = (ovip_axi_id_t'(1)<<cfg.rd_id_width)-1;
	BUSER_MASK = (ovip_axi_user_t'(1)<<cfg.buser_width) -1;
	RUSER_MASK = (ovip_axi_user_t'(1)<<cfg.ruser_width) -1;
endfunction : build_phase

function void ovip_axi_slave_driver::reset_internal_state();
	super.reset_internal_state();
	// clean all internal queues on reset
	outstanding_rd_tr.reset();
	outstanding_wr_tr.reset();
	begin
		// Flush ready-pattern mailboxes so pre-reset patterns don't survive into post-reset.
		ovip_axi_ready_pattern_t _drain;
		while(arready_pattern_mb.try_get(_drain));
		while(awready_pattern_mb.try_get(_drain));
		while(wready_pattern_mb.try_get(_drain));
	end
endfunction : reset_internal_state


// A payload field's value while its VALID is low: zero, or random over `bits`
// bits when cfg.randomize_idle_payload asks for it. AXI leaves it undefined.
function ovip_axi_data_t ovip_axi_slave_driver::idle_value(int bits = 64);
	ovip_axi_data_t v = '0;
	if(cfg.randomize_idle_payload)
		for(int ii = 0; ii < bits && ii < $bits(v); ii += 32)
			v[ii +: 32] = $urandom;
	return v;
endfunction : idle_value

function void ovip_axi_slave_driver::drive_reset_values();
	vif.slave_cb.rvalid <= 0;
	vif.slave_cb.bvalid <= 0;

	vif.slave_cb.arready <= 0;
	vif.slave_cb.awready <= 0;
	vif.slave_cb.wready <= 0;
	vif.slave_cb.bvalid <= 0;

endfunction : drive_reset_values


task ovip_axi_slave_driver::raddr_phase_driver();
	ovip_axi_ready_pattern_t ready_pattern = cfg.default_arready_pattern;
	forever begin
		if(ready_pattern.cycles.sum() == 0) begin
			`uvm_warning("OVIP_AXI/READY_PATTERN", "arready pattern cycles[] sum to 0 -- falling back to '{cycles:'{0,1}, loop:0} (always-ready)")
			ready_pattern = '{cycles:'{0,1}, loop:0};
		end
		`OVIP_BEGIN_FIRST_OF
			arready_pattern_mb.get(ready_pattern);
			forever
			begin
				foreach(ready_pattern.cycles[ii])
				begin
					vif.slave_cb.arready <= bit'(ii);
					repeat(ready_pattern.cycles[ii]) @(vif.slave_cb);
				end
				if(!ready_pattern.loop) wait(0);
			end
		`OVIP_END_FIRST_OF
	end
endtask : raddr_phase_driver



task ovip_axi_slave_driver::waddr_phase_driver();
	ovip_axi_ready_pattern_t ready_pattern = cfg.default_awready_pattern;
	if(cfg.awready_waits_for_wvalid)
	begin
		awready_after_wvalid_driver();
		return;
	end
	forever begin
		if(ready_pattern.cycles.sum() == 0) begin
			`uvm_warning("OVIP_AXI/READY_PATTERN", "awready pattern cycles[] sum to 0 -- falling back to '{cycles:'{0,1}, loop:0} (always-ready)")
			ready_pattern = '{cycles:'{0,1}, loop:0};
		end
		`OVIP_BEGIN_FIRST_OF
			awready_pattern_mb.get(ready_pattern);
			forever
			begin
				foreach(ready_pattern.cycles[ii])
				begin
					vif.slave_cb.awready <= bit'(ii);
					repeat(ready_pattern.cycles[ii]) @(vif.slave_cb);
				end
				if(!ready_pattern.loop) wait(0);
			end
		`OVIP_END_FIRST_OF
	end
endtask : waddr_phase_driver


// cfg.awready_waits_for_wvalid: AWREADY follows the ready pattern, but only
// while some write burst has offered WVALID ahead of its AW. The slave still
// takes W whenever WREADY allows, so a burst whose W it took before the AW
// counts as well. One loop per cycle: it counts, then drives.
task ovip_axi_slave_driver::awready_after_wvalid_driver();
	ovip_axi_ready_pattern_t ready_pattern = cfg.default_awready_pattern;
	ovip_axi_ready_pattern_t next_pattern;
	int  w_ahead  = 0;   // W bursts that offered WVALID and whose AW the slave has not taken
	bit  in_burst = 0;   // a W burst has started and its last beat is not taken yet
	bit  lite     = (cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE);
	int  ii       = 0;   // the pattern's current entry: even entries low, odd ones high
	int  left;           // cycles left in it
	bit  held     = 0;   // a pattern that does not loop has ended: its last entry holds
	if(ready_pattern.cycles.sum() == 0) ready_pattern = '{cycles:'{0,1}, loop:0};
	left = ready_pattern.cycles[0];
	vif.slave_cb.awready <= 0;
	forever
	begin
		@(vif.monitor_cb);
		// what this edge saw
		if(vif.monitor_cb.wvalid && !in_burst) begin w_ahead++; in_burst = 1; end
		if(vif.monitor_cb.wvalid && vif.monitor_cb.wready && (lite || vif.monitor_cb.wlast)) in_burst = 0;
		if(vif.monitor_cb.awvalid && vif.monitor_cb.awready) w_ahead--;
		// a new pattern replaces the current one
		if(awready_pattern_mb.try_get(next_pattern) && next_pattern.cycles.sum() != 0)
		begin
			ready_pattern = next_pattern;
			ii = 0;
			left = ready_pattern.cycles[0];
			held = 0;
		end
		// step the pattern by one cycle
		while(!held && left == 0)
		begin
			if(ii + 1 < ready_pattern.cycles.size()) ii++;
			else if(ready_pattern.loop) ii = 0;
			else begin held = 1; break; end
			left = ready_pattern.cycles[ii];
		end
		if(!held) left--;
		vif.slave_cb.awready <= bit'(ii) && (w_ahead > 0);
	end
endtask : awready_after_wvalid_driver

task ovip_axi_slave_driver::wdata_phase_driver();
	ovip_axi_ready_pattern_t ready_pattern = cfg.default_wready_pattern;
	forever begin
		if(ready_pattern.cycles.sum() == 0) begin
			`uvm_warning("OVIP_AXI/READY_PATTERN", "wready pattern cycles[] sum to 0 -- falling back to '{cycles:'{0,1}, loop:0} (always-ready)")
			ready_pattern = '{cycles:'{0,1}, loop:0};
		end
		`OVIP_BEGIN_FIRST_OF
			wready_pattern_mb.get(ready_pattern);
			forever
			begin
				foreach(ready_pattern.cycles[ii])
				begin
					vif.slave_cb.wready <= bit'(ii);
					repeat(ready_pattern.cycles[ii]) @(vif.slave_cb);
				end
				if(!ready_pattern.loop) wait(0);
			end
		`OVIP_END_FIRST_OF
	end
endtask : wdata_phase_driver

function void ovip_axi_slave_driver::drive_b_channel_reset_values();
	if(cfg.wr_id_width) vif.slave_cb.bid   <= idle_value();
	if(cfg.buser_width) vif.slave_cb.buser <= idle_value();
	vif.slave_cb.bresp <= idle_value();
endfunction : drive_b_channel_reset_values


function void ovip_axi_slave_driver::drive_wr_resp(ovip_axi_trans tr);
	if(cfg.wr_id_width) vif.slave_cb.bid   <= tr.id;
	if(cfg.buser_width) vif.slave_cb.buser <= tr.buser;
	vif.slave_cb.bresp <= tr.resp;
endfunction : drive_wr_resp


task ovip_axi_slave_driver::bresp_phase_driver();
	ovip_axi_trans tr;

	if(cfg.drive_reset_values_when_idle || cfg.randomize_idle_payload)
	drive_b_channel_reset_values();

	forever
	begin
		outstanding_wr_tr.pop(tr);

		drive_wr_resp(tr);

		vif.slave_cb.bvalid <= 1;
		@(vif.slave_cb iff vif.slave_cb.bready);
		vif.slave_cb.bvalid <= 0;

		tr.transaction_finished = 1;

		if(cfg.drive_reset_values_when_idle || cfg.randomize_idle_payload)
			drive_b_channel_reset_values();

	end
endtask : bresp_phase_driver



function void ovip_axi_slave_driver::drive_r_channel_reset_values();
	if(cfg.rd_id_width) vif.slave_cb.rid    <= idle_value();
	if(cfg.ruser_width) vif.slave_cb.ruser  <= idle_value();
	vif.slave_cb.rdata <= idle_value(int'(cfg.bus_width) * 8);
	vif.slave_cb.rresp <= idle_value();
	if(cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE) return;
	vif.slave_cb.rlast <= idle_value();
endfunction : drive_r_channel_reset_values


function void ovip_axi_slave_driver::drive_rd_channel(ovip_axi_trans tr);
	ovip_axi_data_t rdata;
	if(cfg.auto_byte_lanes_alignment && (tr.is_narrow_transfer || tr.burst_index == 0 || tr.burst == OVIP_AXI_BURST_FIXED))
		rdata = tr.data_beats[tr.burst_index]<<tr.transfer_starting_byte_lane[tr.burst_index]*8;
	else
		rdata = tr.data_beats[tr.burst_index];

	// A lane the beat does not use is undefined in AXI: random instead of zero
	// when asked. A beat uses its container from its first byte to its end.
	if(cfg.randomize_unused_rdata && cfg.protocol_type != OVIP_PROTOCOL_AXI4_LITE)
	begin
		int s = 1 << tr.size;
		int lo, hi;
		if(tr.transfer_starting_byte_lane.size() != tr.len + 1)
		begin
			tr.bus_width = cfg.bus_width;
			tr.calculate_transfer_starting_byte_lane();
		end
		lo = tr.transfer_starting_byte_lane[tr.burst_index];
		hi = (lo & ~(s - 1)) + s;
		for(int ii = 0; ii < int'(cfg.bus_width); ii++)
			if(ii < lo || ii >= hi) rdata[ii*8 +: 8] = $urandom;
	end
	vif.slave_cb.rdata <= rdata;

	if(cfg.rd_id_width) vif.slave_cb.rid   <= tr.id;
	if(cfg.ruser_width) vif.slave_cb.ruser <= tr.ruser;

	// RRESP rides every beat: the beat's own entry when the sequence filled
	// resp_beats, else `resp` on all of them
	vif.slave_cb.rresp <= tr.resp_of_beat(tr.burst_index);

	if(cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE)
		return;

	vif.slave_cb.rlast <= (tr.burst_index == tr.len);
endfunction : drive_rd_channel


task ovip_axi_slave_driver::rdata_phase_driver();
	ovip_axi_trans tr;

	vif.slave_cb.rvalid <= 0;
	if(cfg.drive_reset_values_when_idle || cfg.randomize_idle_payload)
		drive_r_channel_reset_values();

	forever
	begin
		outstanding_rd_tr.pop(tr);

		drive_rd_channel(tr);

		vif.slave_cb.rvalid <= 1;
		@(vif.slave_cb iff vif.slave_cb.rready /*&& vif.monitor_cb.wvalid*/);
		vif.slave_cb.rvalid <= 0;

		tr.transaction_finished = (tr.burst_index == tr.len);

		if(cfg.drive_reset_values_when_idle || cfg.randomize_idle_payload)
			drive_r_channel_reset_values();

		if(tr.transaction_finished)
			repeat(tr.delay_until_next_data) @(vif.slave_cb);

		tr.burst_index++;
	end


endtask : rdata_phase_driver


//
// check_trans_validity functions
// Note that these functions only check for basic requirements needed for proper driving operation.
// The transaction will be fully verified by the monitor anyway.
//
function bit ovip_axi_slave_driver::check_write_trans_validity(ovip_axi_trans tr);
	bit err_flag = 0;
	`OVIP_CHECK_VALUE_VS_SIGNAL_WIDTH("TR_CHK", "ID",    tr.id,    cfg.wr_id_width, err_flag)
	`OVIP_CHECK_VALUE_VS_SIGNAL_WIDTH("TR_CHK", "BUSER", tr.buser, cfg.buser_width, err_flag)
	return err_flag;
endfunction

function bit ovip_axi_slave_driver::check_read_trans_validity(ovip_axi_trans tr);
	bit err_flag = 0;
	`OVIP_CHECK_VALUE_VS_SIGNAL_WIDTH("TR_CHK", "ID",    tr.id,    cfg.rd_id_width, err_flag)
	`OVIP_CHECK_VALUE_VS_SIGNAL_WIDTH("TR_CHK", "RUSER", tr.ruser, cfg.ruser_width, err_flag)
	if(tr.len+1 > tr.data_beats.size())
	begin
		err_flag = 1;
		`uvm_warning("TR_CHK", $sformatf("Number of data beats(%0d) smaller than burst length (%0d)", tr.data_beats.size(), tr.len+1))
	end

	foreach(tr.data_beats[ii])
		`OVIP_CHECK_VALUE_VS_SIGNAL_WIDTH("TR_CHK", $sformatf("data_beats[%0d]",ii), tr.data_beats[ii], cfg.bus_width*8, err_flag)

	return err_flag;
endfunction

function bit ovip_axi_slave_driver::check_trans_validity(ovip_axi_trans tr);
	bit err_flag = 0;

	if(tr.tr_type == OVIP_AXI_WRITE_TRANS)
		err_flag |= check_write_trans_validity(tr);
	else
		err_flag |= check_read_trans_validity(tr);

	return err_flag;
endfunction : check_trans_validity


task ovip_axi_slave_driver::transaction_acceptor();

	forever
	begin
		if(outstanding_wr_tr.is_empty() && outstanding_rd_tr.is_empty()) begin
			seq_item_port.get_next_item(req);
			// Timing note: to support an immediate response (the cycle after WLAST
			// for writes or ARVALID for reads), we must be aligned to the clocking
			// block event. This holds as long as the slave sequence does not consume
			// simulation time between getting the item and sending the response.
			`ifndef XCELIUM
			if(!vif.slave_cb.triggered) begin
				if(!cfg.suppress_delayed_slave_seq_warning)
					`uvm_warning("SLAVE_DRV", "Slave sequence returned an item off the clocking-block edge; waiting for the next clock cycle to drive it, which affects item scheduling. Set cfg.suppress_delayed_slave_seq_warning to suppress this warning.")
				@(vif.slave_cb);
			end
			`endif
		end
		else
			seq_item_port.try_next_item(req);

		while(req != null)
		begin
			//accept_tr(req);
			//`uvm_info("SLAVE_DRV", $sformatf("Got %s(%0d)", req.tr_type.name(), req.id), UVM_LOW)
			if(check_trans_validity(req) && req.trust_me_i_am_an_engineer == 0)
				`uvm_fatal("AXI_SLAVE_DRV", "Something is bad with this transaction! See UVM_WARNINGs above")

			if(req.tr_type == OVIP_AXI_WRITE_TRANS)
			begin
				outstanding_wr_tr.push(req, {req.bresp_delay});
			end
			else
			begin
				// Calculate byte lanes alignment offsets if needed.
				if(cfg.auto_byte_lanes_alignment)
					req.calculate_transfer_starting_byte_lane();
				outstanding_rd_tr.push(req, req.data_delay, req.len);
			end

			// Update ready signals drivers with new values if available
			if(req.arready_pattern.cycles.size()) arready_pattern_mb.put(req.arready_pattern);
			if(req.awready_pattern.cycles.size()) awready_pattern_mb.put(req.awready_pattern);
			if(req.wready_pattern.cycles.size())  wready_pattern_mb.put(req.wready_pattern);

			seq_item_port.item_done();
			seq_item_port.try_next_item(req);
		end

		outstanding_wr_tr.schedule_next();
		outstanding_wr_tr.tick_delays();

		outstanding_rd_tr.schedule_next();
		outstanding_rd_tr.tick_delays();
		@(vif.slave_cb);
	end

endtask : transaction_acceptor

`endif
