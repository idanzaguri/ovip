
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
				if(cfg.protocol_type != OVIP_PROTOCOL_AXI4_LITE)
				begin
					`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(len  , AWLEN  )
					`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(size , AWSIZE )
					`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(burst, AWBURST)
					if(cfg.awlock_en)   `OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(axlock  , AWLOCK  )
					if(cfg.awcache_en)  `OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(axcache , AWCACHE )
					if(cfg.awprot_en)   `OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(axprot  , AWPROT  )
					if(cfg.awqos_en)    `OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(axqos   , AWQOS   )
					if(cfg.awregion_en) `OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(axregion, AWREGION)
				end
			end

			if(!vif.monitor_cb.awvalid) begin `uvm_error("AXI_MON/STABILITY_CHECK", "AWVALID was de-asserted before the transfer was sampled!") break; end
			if(vif.monitor_cb.awready) break;
			@(vif.monitor_cb);
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
			if(cycle++ != 0)
			begin
				`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(data_beats[0], WDATA)
				`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(strb_beats[0], WSTRB)
				`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(got_last_beat, WLAST)
				`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(wuser, WUSER )
			end

			if(!vif.monitor_cb.wvalid) begin `uvm_error("AXI_MON/STABILITY_CHECK", "WVALID was de-asserted before the transfer was sampled!") break; end
			if(vif.monitor_cb.wready) break;
			@(vif.monitor_cb);
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

			if(!vif.monitor_cb.bvalid) begin `uvm_error("AXI_MON/STABILITY_CHECK", "BVALID was de-asserted before the transfer was sampled!") break; end
			if(vif.monitor_cb.bready) break;
			@(vif.monitor_cb);
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
				if(cfg.protocol_type != OVIP_PROTOCOL_AXI4_LITE)
				begin
					`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(len   , ARLEN  )
					`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(size  , ARSIZE )
					`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(burst , ARBURST)
					if(cfg.arlock_en)   `OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(axlock  , ARLOCK  )
					if(cfg.arcache_en)  `OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(axcache , ARCACHE )
					if(cfg.arprot_en)   `OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(axprot  , ARPROT  )
					if(cfg.arqos_en)    `OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(axqos   , ARQOS   )
					if(cfg.arregion_en) `OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(axregion, ARREGION)
				end
			end

			if(!vif.monitor_cb.arvalid) begin `uvm_error("AXI_MON/STABILITY_CHECK", "ARVALID was de-asserted before the transfer was sampled!") break; end
			if(vif.monitor_cb.arready) break;
			@(vif.monitor_cb);
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
		@(vif.monitor_cb iff vif.monitor_cb.rvalid && !vif.monitor_cb.rready);
		forever
		begin
			sample_read_data(sampling_array[cycle%2]);
			if(cycle++ != 0)
			begin
				`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(data_beats[1], RDATA)
				`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(got_last_beat, RLAST)
				`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(ruser, RUSER)
				`OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(id, RID)
				if(sampling_array[0].got_last_beat) `OVIP_AXI_MON_SIGNAL_STABILITY_CHECK(resp, RRESP)
			end

			if(!vif.monitor_cb.rvalid) begin `uvm_error("AXI_MON/STABILITY_CHECK", "RVALID was de-asserted before the transfer was sampled!") break; end
			if(vif.monitor_cb.rready) break;
			@(vif.monitor_cb);
		end
	end
endtask : r_channel_signal_stability_check

// ----------------------------------------------------------------------------------- //
//                                                                                     //
//                             Channels sample functions                               //
//                                                                                     //
// ----------------------------------------------------------------------------------- //
function void ovip_axi_monitor::check_xz_write_address();
	`OVIP_AXI_MON_XZ_CHECK(awid  &WR_ID_MASK, AWID)
	`OVIP_AXI_MON_XZ_CHECK(awaddr&ADDR_MASK , AWADDR)
	`OVIP_AXI_MON_XZ_CHECK(awuser& AWUSER_MASK, AWUSER)

	if(cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE) return;

	`OVIP_AXI_MON_XZ_CHECK(awlen &LEN_MASK , AWLEN)
	`OVIP_AXI_MON_XZ_CHECK(awsize&SIZE_MASK, AWSIZE)
	`OVIP_AXI_MON_XZ_CHECK(awburst         , AWBURST)

	if(cfg.awlock_en)   `OVIP_AXI_MON_XZ_CHECK(awlock  , AWLOCK  )
	if(cfg.awcache_en)  `OVIP_AXI_MON_XZ_CHECK(awcache , AWCACHE )
	if(cfg.awprot_en)   `OVIP_AXI_MON_XZ_CHECK(awprot  , AWPROT  )
	if(cfg.awqos_en)    `OVIP_AXI_MON_XZ_CHECK(awqos   , AWQOS   )
	if(cfg.awregion_en) `OVIP_AXI_MON_XZ_CHECK(awregion, AWREGION)

endfunction : check_xz_write_address


function void ovip_axi_monitor::check_xz_write_data();
	`OVIP_AXI_MON_XZ_CHECK(wdata&DATA_MASK , WDATA)
	`OVIP_AXI_MON_XZ_CHECK(wstrb&STRB_MASK , WSTRB)
	`OVIP_AXI_MON_XZ_CHECK(wuser&WUSER_MASK, WUSER)
	if(cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE) return;
	`OVIP_AXI_MON_XZ_CHECK(wlast, WLAST)
endfunction : check_xz_write_data

function void ovip_axi_monitor::check_xz_write_response();
	`OVIP_AXI_MON_XZ_CHECK(bid&WR_ID_MASK  , BID)
	`OVIP_AXI_MON_XZ_CHECK(bresp           , BRESP)
	`OVIP_AXI_MON_XZ_CHECK(buser&BUSER_MASK, BUSER)
endfunction : check_xz_write_response

function void ovip_axi_monitor::check_xz_read_address();
	`OVIP_AXI_MON_XZ_CHECK(arid  &RD_ID_MASK, ARID)
	`OVIP_AXI_MON_XZ_CHECK(araddr&ADDR_MASK , ARADDR)
	`OVIP_AXI_MON_XZ_CHECK(aruser& ARUSER_MASK, ARUSER)

	if(cfg.protocol_type == OVIP_PROTOCOL_AXI4_LITE) return;

	`OVIP_AXI_MON_XZ_CHECK(arlen &LEN_MASK , ARLEN)
	`OVIP_AXI_MON_XZ_CHECK(arsize&SIZE_MASK, ARSIZE)
	`OVIP_AXI_MON_XZ_CHECK(arburst         , ARBURST)

	if(cfg.arlock_en)   `OVIP_AXI_MON_XZ_CHECK(arlock  , ARLOCK  )
	if(cfg.arcache_en)  `OVIP_AXI_MON_XZ_CHECK(arcache , ARCACHE )
	if(cfg.arprot_en)   `OVIP_AXI_MON_XZ_CHECK(arprot  , ARPROT  )
	if(cfg.arqos_en)    `OVIP_AXI_MON_XZ_CHECK(arqos   , ARQOS   )
	if(cfg.arregion_en) `OVIP_AXI_MON_XZ_CHECK(arregion, ARREGION)

endfunction : check_xz_read_address


function void ovip_axi_monitor::check_xz_read_data();
	`OVIP_AXI_MON_XZ_CHECK(rid&RD_ID_MASK , RID)
	`OVIP_AXI_MON_XZ_CHECK(rdata&DATA_MASK ,RDATA)
	`OVIP_AXI_MON_XZ_CHECK(ruser&RUSER_MASK, RUSER)
	if(cfg.protocol_type != OVIP_PROTOCOL_AXI4_LITE)
	begin
		`OVIP_AXI_MON_XZ_CHECK(rlast, RLAST)
		if(vif.monitor_cb.rlast)
			`OVIP_AXI_MON_XZ_CHECK(rresp, RRESP)
	end
	else
	begin
		`OVIP_AXI_MON_XZ_CHECK(rresp, RRESP)
	end
endfunction : check_xz_read_data

