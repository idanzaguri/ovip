
// A reset ends a transfer under VALID. A slave or master reset asynchronously
// drops VALID with ARESETn, and these threads wake on that edge before or
// after rst_monitor, so each checks ARESETn on every edge it waits for.
task ovip_axi_monitor::aw_channel_signal_stability_check();
	ovip_axi_trans sampling_array[2];
	sampling_array[0] = new;
	sampling_array[1] = new;

	forever
	begin
		int cycle = 0;
		@(vif.monitor_cb iff vif.monitor_cb.awvalid && !vif.monitor_cb.awready);
		forever
		begin
			sample_write_address(sampling_array[cycle%2]);
			if(cycle++ != 0)
			begin
				`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(id    , AWID   )
				`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(addr  , AWADDR )
				`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(awuser, AWUSER )
				if(cfg.awprot_en)   `OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(axprot  , AWPROT  )
				if(cfg.protocol_type != OVIP_PROTOCOL_AXI4_LITE)
				begin
					`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(len  , AWLEN  )
					`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(size , AWSIZE )
					`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(burst, AWBURST)
					if(cfg.awlock_en)   `OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(axlock  , AWLOCK  )
					if(cfg.awcache_en)  `OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(axcache , AWCACHE )
					if(cfg.awqos_en)    `OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(axqos   , AWQOS   )
					if(cfg.awregion_en) `OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(axregion, AWREGION)
				end
			end

			if(!vif.monitor_cb.awvalid) begin `uvm_error({MESSAGE_TAG, "AXI_MON/STABILITY_CHECK"}, "AWVALID was de-asserted before the transfer was sampled!") break; end
			if(vif.monitor_cb.awready) break;
			@(vif.monitor_cb);
			if(!vif.monitor_cb.aresetn) break;   // a reset ends the transfer: rst_monitor drops it
		end
	end
endtask : aw_channel_signal_stability_check

task ovip_axi_monitor::w_channel_signal_stability_check();
	ovip_axi_trans sampling_array[2];
	sampling_array[0] = new;
	sampling_array[1] = new;

	forever
	begin
		int cycle = 0;
		@(vif.monitor_cb iff vif.monitor_cb.wvalid && !vif.monitor_cb.wready);
		forever
		begin
			sample_write_data(sampling_array[cycle%2]);
			// WID is an AXI3 signal that sample_write_data does not take
			sampling_array[cycle%2].id = vif.monitor_cb.wid&WR_ID_MASK;
			if(cycle++ != 0)
			begin
				// WDATA on the bytes whose WSTRB bit is high in one of the two cycles
				ovip_axi_data_t wdata_lanes = wdata_lanes_to_check(sampling_array[0].strb_beats[0] | sampling_array[1].strb_beats[0]);
				`OVIP_AXI_MON_DATA_STABILITY_CHECK(data_beats[0], wdata_lanes, WDATA)
				`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(strb_beats[0], WSTRB)
				`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(got_last_beat, WLAST)
				`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(wuser, WUSER )
				if(cfg.protocol_type == OVIP_PROTOCOL_AXI3) `OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(id, WID)
			end

			if(!vif.monitor_cb.wvalid) begin `uvm_error({MESSAGE_TAG, "AXI_MON/STABILITY_CHECK"}, "WVALID was de-asserted before the transfer was sampled!") break; end
			if(vif.monitor_cb.wready) break;
			@(vif.monitor_cb);
			if(!vif.monitor_cb.aresetn) break;   // a reset ends the transfer: rst_monitor drops it
		end
	end
endtask : w_channel_signal_stability_check


task ovip_axi_monitor::b_channel_signal_stability_check();
	ovip_axi_trans sampling_array[2];
	sampling_array[0] = new;
	sampling_array[1] = new;

	forever
	begin
		int cycle = 0;
		@(vif.monitor_cb iff vif.monitor_cb.bvalid && !vif.monitor_cb.bready);
		forever
		begin
			sample_write_response(sampling_array[cycle%2]);
			if(cycle++ != 0)
			begin
				`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(id ,   BID)
				`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(resp , BRESP)
				`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(buser ,BUSER)
			end

			if(!vif.monitor_cb.bvalid) begin `uvm_error({MESSAGE_TAG, "AXI_MON/STABILITY_CHECK"}, "BVALID was de-asserted before the transfer was sampled!") break; end
			if(vif.monitor_cb.bready) break;
			@(vif.monitor_cb);
			if(!vif.monitor_cb.aresetn) break;   // a reset ends the transfer: rst_monitor drops it
		end
	end
endtask : b_channel_signal_stability_check




task ovip_axi_monitor::ar_channel_signal_stability_check();
	ovip_axi_trans sampling_array[2];
	sampling_array[0] = new;
	sampling_array[1] = new;

	forever
	begin
		int cycle = 0;
		@(vif.monitor_cb iff vif.monitor_cb.arvalid && !vif.monitor_cb.arready);
		forever
		begin
			sample_read_address(sampling_array[cycle%2]);
			if(cycle++ != 0)
			begin
				`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(id    , ARID   )
				`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(addr  , ARADDR )
				`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(aruser, ARUSER )
				if(cfg.arprot_en)   `OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(axprot  , ARPROT  )
				if(cfg.protocol_type != OVIP_PROTOCOL_AXI4_LITE)
				begin
					`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(len   , ARLEN  )
					`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(size  , ARSIZE )
					`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(burst , ARBURST)
					if(cfg.arlock_en)   `OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(axlock  , ARLOCK  )
					if(cfg.arcache_en)  `OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(axcache , ARCACHE )
					if(cfg.arqos_en)    `OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(axqos   , ARQOS   )
					if(cfg.arregion_en) `OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(axregion, ARREGION)
				end
			end

			if(!vif.monitor_cb.arvalid) begin `uvm_error({MESSAGE_TAG, "AXI_MON/STABILITY_CHECK"}, "ARVALID was de-asserted before the transfer was sampled!") break; end
			if(vif.monitor_cb.arready) break;
			@(vif.monitor_cb);
			if(!vif.monitor_cb.aresetn) break;   // a reset ends the transfer: rst_monitor drops it
		end
	end
endtask : ar_channel_signal_stability_check

task ovip_axi_monitor::r_channel_signal_stability_check();
	ovip_axi_trans sampling_array[2];
	foreach(sampling_array[ii])
	begin
		sampling_array[ii] = new;
		// PATCH to disable using transfer_starting_byte_lane when calling sample_read_data from here
		sampling_array[ii].data_beats[0] = 0;
		sampling_array[ii].burst_index = 1;
	end

	forever
	begin
		int cycle = 0;
		ovip_axi_data_t rdata_lanes;
		@(vif.monitor_cb iff vif.monitor_cb.rvalid && !vif.monitor_cb.rready);
		// the lanes of the beat that waits: the same until its handshake
		rdata_lanes = rdata_lanes_to_check();
		forever
		begin
			sample_read_data(sampling_array[cycle%2]);
			if(cycle++ != 0)
			begin
				`OVIP_AXI_MON_DATA_STABILITY_CHECK(data_beats[1], rdata_lanes, RDATA)
				`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(got_last_beat, RLAST)
				`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(ruser, RUSER)
				`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(id, RID)
				// resp_beats[1] is the RRESP of the cycle. `resp` is not: it is the
				// worst response that the sampling item has taken since it was made.
				`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(resp_beats[1], RRESP)
			end

			if(!vif.monitor_cb.rvalid) begin `uvm_error({MESSAGE_TAG, "AXI_MON/STABILITY_CHECK"}, "RVALID was de-asserted before the transfer was sampled!") break; end
			if(vif.monitor_cb.rready) break;
			@(vif.monitor_cb);
			if(!vif.monitor_cb.aresetn) break;   // a reset ends the transfer: rst_monitor drops it
		end
	end
endtask : r_channel_signal_stability_check

// ----------------------------------------------------------------------------------- //
//                                                                                     //
//                       Byte lanes of the data buses to check                         //
//                                                                                     //
// ----------------------------------------------------------------------------------- //

// The WDATA bytes that the X/Z check and the stability check cover: the bytes
// whose bit in `strb` is high. A byte under a low strobe is undefined (spec
// A3.4.3). With cfg.check_undefined_data_lanes: the whole bus.
function ovip_axi_data_t ovip_axi_monitor::wdata_lanes_to_check(ovip_axi_strb_t strb);
	ovip_axi_data_t lanes = '0;
	if(cfg.check_undefined_data_lanes) return DATA_MASK;
	for(int ii = 0; ii < int'(cfg.bus_width); ii++)
		if(strb[ii]) lanes[ii*8 +: 8] = 8'hFF;
	return lanes;
endfunction : wdata_lanes_to_check

// The RDATA bytes that the X/Z check and the stability check cover on the R
// beat that is on the bus: the lanes of the beat, from its first byte to the
// end of its size-aligned container. The other lanes are undefined. The whole
// bus with cfg.check_undefined_data_lanes, on AXI4-Lite, and for a beat that
// has no read or is past ARLEN.
function ovip_axi_data_t ovip_axi_monitor::rdata_lanes_to_check();
	ovip_axi_id_t id = vif.monitor_cb.rid & RD_ID_MASK;
	ovip_axi_data_t lanes = '0;
	ovip_axi_trans tr;
	int burst_size, first_lane, last_lane;
	if(cfg.check_undefined_data_lanes || cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE) return DATA_MASK;
	if(!outstanding_rd_trans.exists(id) || outstanding_rd_trans[id].size() == 0) return DATA_MASK;
	tr = outstanding_rd_trans[id][0];
	if(tr.burst_index > tr.len) return DATA_MASK;
	burst_size = 1 << tr.size;
	first_lane = tr.transfer_starting_byte_lane[tr.burst_index];
	last_lane  = (first_lane & ~(burst_size - 1)) + burst_size - 1;
	for(int ii = first_lane; ii <= last_lane && ii < int'(cfg.bus_width); ii++)
		lanes[ii*8 +: 8] = 8'hFF;
	return lanes;
endfunction : rdata_lanes_to_check

// ----------------------------------------------------------------------------------- //
//                                                                                     //
//                             Channels sample functions                               //
//                                                                                     //
// ----------------------------------------------------------------------------------- //
function void ovip_axi_monitor::check_xz_write_address();
	// an AXI4-Lite port has no ID: AWID is not a pin there, so it is not checked
	if(cfg.protocol_type != OVIP_PROTOCOL_AXI4_LITE) `OVIP_AXI_MON_XZ_CHECK(awid  &WR_ID_MASK, AWID)
	`OVIP_AXI_MON_XZ_CHECK(awaddr&ADDR_MASK , AWADDR)
	`OVIP_AXI_MON_XZ_CHECK(awuser& AWUSER_MASK, AWUSER)
	if(cfg.awprot_en)   `OVIP_AXI_MON_XZ_CHECK(awprot  , AWPROT  )

	if(cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE) return;

	`OVIP_AXI_MON_XZ_CHECK(awlen &LEN_MASK , AWLEN)
	`OVIP_AXI_MON_XZ_CHECK(awsize&SIZE_MASK, AWSIZE)
	`OVIP_AXI_MON_XZ_CHECK(awburst         , AWBURST)

	if(cfg.awlock_en)   `OVIP_AXI_MON_XZ_CHECK(awlock  , AWLOCK  )
	if(cfg.awcache_en)  `OVIP_AXI_MON_XZ_CHECK(awcache , AWCACHE )
	if(cfg.awqos_en)    `OVIP_AXI_MON_XZ_CHECK(awqos   , AWQOS   )
	if(cfg.awregion_en) `OVIP_AXI_MON_XZ_CHECK(awregion, AWREGION)

endfunction : check_xz_write_address


function void ovip_axi_monitor::check_xz_write_data();
	ovip_axi_data_t wdata_lanes = wdata_lanes_to_check(vif.monitor_cb.wstrb&STRB_MASK);
	// WID is a pin on AXI3 only
	if(cfg.protocol_type == OVIP_PROTOCOL_AXI3) `OVIP_AXI_MON_XZ_CHECK(wid&WR_ID_MASK, WID)
	`OVIP_AXI_MON_XZ_CHECK(wdata&wdata_lanes , WDATA)
	`OVIP_AXI_MON_XZ_CHECK(wstrb&STRB_MASK , WSTRB)
	`OVIP_AXI_MON_XZ_CHECK(wuser&WUSER_MASK, WUSER)
	if(cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE) return;
	`OVIP_AXI_MON_XZ_CHECK(wlast, WLAST)
endfunction : check_xz_write_data

function void ovip_axi_monitor::check_xz_write_response();
	if(cfg.protocol_type != OVIP_PROTOCOL_AXI4_LITE) `OVIP_AXI_MON_XZ_CHECK(bid&WR_ID_MASK  , BID)
	`OVIP_AXI_MON_XZ_CHECK(bresp           , BRESP)
	`OVIP_AXI_MON_XZ_CHECK(buser&BUSER_MASK, BUSER)
endfunction : check_xz_write_response

function void ovip_axi_monitor::check_xz_read_address();
	if(cfg.protocol_type != OVIP_PROTOCOL_AXI4_LITE) `OVIP_AXI_MON_XZ_CHECK(arid  &RD_ID_MASK, ARID)
	`OVIP_AXI_MON_XZ_CHECK(araddr&ADDR_MASK , ARADDR)
	`OVIP_AXI_MON_XZ_CHECK(aruser& ARUSER_MASK, ARUSER)
	if(cfg.arprot_en)   `OVIP_AXI_MON_XZ_CHECK(arprot  , ARPROT  )

	if(cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE) return;

	`OVIP_AXI_MON_XZ_CHECK(arlen &LEN_MASK , ARLEN)
	`OVIP_AXI_MON_XZ_CHECK(arsize&SIZE_MASK, ARSIZE)
	`OVIP_AXI_MON_XZ_CHECK(arburst         , ARBURST)

	if(cfg.arlock_en)   `OVIP_AXI_MON_XZ_CHECK(arlock  , ARLOCK  )
	if(cfg.arcache_en)  `OVIP_AXI_MON_XZ_CHECK(arcache , ARCACHE )
	if(cfg.arqos_en)    `OVIP_AXI_MON_XZ_CHECK(arqos   , ARQOS   )
	if(cfg.arregion_en) `OVIP_AXI_MON_XZ_CHECK(arregion, ARREGION)

endfunction : check_xz_read_address


function void ovip_axi_monitor::check_xz_read_data();
	ovip_axi_data_t rdata_lanes = rdata_lanes_to_check();
	if(cfg.protocol_type != OVIP_PROTOCOL_AXI4_LITE) `OVIP_AXI_MON_XZ_CHECK(rid&RD_ID_MASK , RID)
	`OVIP_AXI_MON_XZ_CHECK(rdata&rdata_lanes ,RDATA)
	`OVIP_AXI_MON_XZ_CHECK(ruser&RUSER_MASK, RUSER)
	// RRESP is valid on every beat of a read, not only on the last one
	`OVIP_AXI_MON_XZ_CHECK(rresp, RRESP)
	if(cfg.protocol_type != OVIP_PROTOCOL_AXI4_LITE)
		`OVIP_AXI_MON_XZ_CHECK(rlast, RLAST)
endfunction : check_xz_read_data

