`ifndef OVIP_ACE_MASTER_DRIVER__SV
`define OVIP_ACE_MASTER_DRIVER__SV

// ovip_ace_master_driver -- master-side ACE driver. Inherits all AXI request
// driving from ovip_axi_master_driver, adds:
//
//   - ACE additions on AR/AW (ARDOMAIN/ARSNOOP/ARBAR/AWDOMAIN/AWSNOOP/AWBAR/AWUNIQUE)
//     via drive_ar_channel / drive_aw_channel hook overrides.
//   - RRESP[3:2] (IsShared, PassDirty) capture via sample_rd_response.
//   - Snoop responder on AC -> CR / CD via extra_forks() + snoop_phase_driver.
//     Response policy comes from the build_snoop_response() virtual hook;
//     default is "cache miss" (CRRESP=0, no data). Tests override the hook
//     in a derived class.
//   - RACK / WACK, one cycle per completed transaction, via extra_forks() +
//     rack_wack_driver.

class ovip_ace_master_driver extends ovip_axi_master_driver #(virtual ovip_ace_agent_if);

	// Cast of the inherited cfg so ACE-specific knobs are reachable.
	ovip_ace_agent_config ace_cfg;

	`uvm_component_utils(ovip_ace_master_driver)

	function new(string name = "ovip_ace_master_driver", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	extern virtual function void build_phase(uvm_phase phase);

	// Reset value driving
	extern virtual function void drive_reset_values();
	extern virtual function void drive_ar_channel_reset_values();
	extern virtual function void drive_aw_channel_reset_values();
	extern virtual function void drive_snoop_channel_reset_values();

	// Per-transaction signal driving on AR/AW
	extern virtual function void drive_ar_channel(ovip_axi_trans tr);
	extern virtual function void drive_aw_channel(ovip_axi_trans tr);

	// Per-response sampling on R
	extern virtual function void sample_rd_response(ovip_axi_trans tr);

	// Snoop responder + RACK/WACK live in the extra_forks() branch alongside
	// the inherited AXI per-channel drivers.
	extern virtual task extra_forks();
	extern virtual task snoop_phase_driver();
	extern virtual task rack_wack_driver();

	// Test-overridable hook that decides how this master responds to a given
	// snoop. Default behaves like an empty cache: CRRESP=0, no data, no error.
	// A response that sets snoop_resp.data_transfer puts the CD beats in
	// snoop_data_beats; with none, the driver reports an error and clears
	// data_transfer.
	extern virtual function void build_snoop_response(ovip_ace_trans snoop_tr);

endclass : ovip_ace_master_driver



function void ovip_ace_master_driver::build_phase(uvm_phase phase);
	super.build_phase(phase);
	if(!$cast(ace_cfg, cfg))
		`uvm_fatal("ACE_DRV", "Master driver cfg must be an ovip_ace_agent_config")
endfunction : build_phase


function void ovip_ace_master_driver::drive_reset_values();
	super.drive_reset_values();
	drive_snoop_channel_reset_values();
endfunction : drive_reset_values


function void ovip_ace_master_driver::drive_snoop_channel_reset_values();
	// D2.3.3 reset requirements: master holds CRVALID, CDVALID, RACK, WACK
	// LOW during reset.
	vif.master_cb.acready <= 1'b0;
	vif.master_cb.crvalid <= 1'b0;
	vif.master_cb.crresp  <= 5'b0;
	vif.master_cb.cdvalid <= 1'b0;
	vif.master_cb.cddata  <= '0;
	vif.master_cb.cdlast  <= 1'b0;
	vif.master_cb.rack    <= 1'b0;
	vif.master_cb.wack    <= 1'b0;
endfunction : drive_snoop_channel_reset_values


function void ovip_ace_master_driver::drive_ar_channel_reset_values();
	super.drive_ar_channel_reset_values();
	vif.master_cb.ardomain <= 2'b0;
	vif.master_cb.arsnoop  <= 4'b0;
	vif.master_cb.arbar    <= 2'b0;
endfunction : drive_ar_channel_reset_values


function void ovip_ace_master_driver::drive_aw_channel_reset_values();
	super.drive_aw_channel_reset_values();
	vif.master_cb.awdomain <= 2'b0;
	vif.master_cb.awsnoop  <= 3'b0;
	vif.master_cb.awbar    <= 2'b0;
	vif.master_cb.awunique <= 1'b0;
endfunction : drive_aw_channel_reset_values


function void ovip_ace_master_driver::drive_ar_channel(ovip_axi_trans tr);
	ovip_ace_trans ace_tr;
	super.drive_ar_channel(tr);
	if($cast(ace_tr, tr) && ace_tr.direction == OVIP_ACE_INITIATING)
	begin
		vif.master_cb.ardomain <= ace_tr.domain;
		vif.master_cb.arsnoop  <= ace_tr.snoop;
		vif.master_cb.arbar    <= ace_tr.bar;
	end
endfunction : drive_ar_channel


function void ovip_ace_master_driver::drive_aw_channel(ovip_axi_trans tr);
	ovip_ace_trans ace_tr;
	super.drive_aw_channel(tr);
	if($cast(ace_tr, tr) && ace_tr.direction == OVIP_ACE_INITIATING)
	begin
		vif.master_cb.awdomain <= ace_tr.domain;
		vif.master_cb.awsnoop  <= ace_tr.snoop[2:0];
		vif.master_cb.awbar    <= ace_tr.bar;
		vif.master_cb.awunique <= ace_tr.awunique;
	end
endfunction : drive_aw_channel


function void ovip_ace_master_driver::sample_rd_response(ovip_axi_trans tr);
	ovip_ace_trans ace_tr;
	super.sample_rd_response(tr);  // captures rresp[1:0] into tr.resp
	if($cast(ace_tr, tr) && ace_cfg.profile == OVIP_ACE_PROFILE_ACE)
	begin
		ace_tr.pass_dirty = vif.master_cb.rresp[2];
		ace_tr.is_shared  = vif.master_cb.rresp[3];
	end
endfunction : sample_rd_response


task ovip_ace_master_driver::extra_forks();
	fork
		// ACE-Lite has no snoop channels and no RACK/WACK (D11.1). The cb
		// wires are still present in the interface but the master leaves
		// them at reset values: both drivers run in the ACE profile only.
		if(ace_cfg.profile == OVIP_ACE_PROFILE_ACE) rack_wack_driver();
		if(ace_cfg.profile == OVIP_ACE_PROFILE_ACE) snoop_phase_driver();
	join_none
endtask : extra_forks


task ovip_ace_master_driver::snoop_phase_driver();
	ovip_ace_trans snoop_tr;
	forever
	begin
		// Wait until the interconnect drives ACVALID with a stable snoop.
		// Then drive ACREADY=1 to accept the AC handshake.
		@(vif.master_cb iff vif.master_cb.acvalid);
		vif.master_cb.acready <= 1'b1;
		@(vif.master_cb);
		vif.master_cb.acready <= 1'b0;

		// Build a snoop trans capturing the request, then let the test
		// policy hook decide the response.
		snoop_tr = ovip_ace_trans::type_id::create("snoop_tr");
		snoop_tr.direction    = OVIP_ACE_SNOOP;
		snoop_tr.snoop_addr   = vif.monitor_cb.acaddr;
		snoop_tr.acsnoop_code = vif.monitor_cb.acsnoop;
		snoop_tr.acprot       = vif.monitor_cb.acprot;
		build_snoop_response(snoop_tr);

		// DataTransfer promises a full cache line on CD. A response that
		// sets it and gives no beat to send goes out with DataTransfer LOW.
		if(snoop_tr.snoop_resp.data_transfer && snoop_tr.snoop_data_beats.size() == 0)
		begin
			`uvm_error("ACE_MASTER_DRV/SNOOP", "build_snoop_response() set CRRESP.DataTransfer and left snoop_data_beats empty; the response is sent with DataTransfer cleared")
			snoop_tr.snoop_resp.data_transfer = 1'b0;
		end

		// Drive CR and CD side by side. Spec D3.9: CRVALID and CDVALID must
		// not wait for CRREADY or CDREADY, so neither channel waits for the
		// handshake of the other.
		fork
			// Drive CR.
			begin
				vif.master_cb.crvalid <= 1'b1;
				vif.master_cb.crresp  <= { snoop_tr.snoop_resp.was_unique,
				                           snoop_tr.snoop_resp.is_shared,
				                           snoop_tr.snoop_resp.pass_dirty,
				                           snoop_tr.snoop_resp.error,
				                           snoop_tr.snoop_resp.data_transfer };
				@(vif.master_cb iff vif.master_cb.crready);
				vif.master_cb.crvalid <= 1'b0;
			end

			// If the response signaled a data transfer, drive CD beats.
			if(snoop_tr.snoop_resp.data_transfer && snoop_tr.snoop_data_beats.size())
			begin
				int n = snoop_tr.snoop_data_beats.size();
				foreach(snoop_tr.snoop_data_beats[i])
				begin
					vif.master_cb.cdvalid <= 1'b1;
					vif.master_cb.cddata  <= snoop_tr.snoop_data_beats[i];
					vif.master_cb.cdlast  <= (i == n - 1);
					@(vif.master_cb iff vif.master_cb.cdready);
				end
				vif.master_cb.cdvalid <= 1'b0;
				vif.master_cb.cdlast  <= 1'b0;
			end
		join
	end
endtask : snoop_phase_driver


function void ovip_ace_master_driver::build_snoop_response(ovip_ace_trans snoop_tr);
	// Default: cache miss -- line is invalid, no data, no error. Real tests
	// override this to model a cached master that holds Clean / Dirty lines.
	snoop_tr.snoop_resp = '0;
endfunction : build_snoop_response


task ovip_ace_master_driver::rack_wack_driver();
	// One acknowledge per completed transaction, with no backlog (D3.3, D3.5,
	// D6.2.1): RACK is HIGH in the cycle after each RLAST handshake and WACK
	// in the cycle after each B handshake. Transactions that complete in
	// consecutive cycles keep the signal HIGH for as many cycles.
	bit rd_done;
	bit wr_done;
	forever begin
		@(vif.monitor_cb);
		rd_done = vif.monitor_cb.rvalid && vif.monitor_cb.rready && vif.monitor_cb.rlast;
		wr_done = vif.monitor_cb.bvalid && vif.monitor_cb.bready;
		vif.master_cb.rack <= rd_done;
		vif.master_cb.wack <= wr_done;
	end
endtask : rack_wack_driver

`endif
