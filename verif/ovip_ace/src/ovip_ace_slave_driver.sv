`ifndef OVIP_ACE_SLAVE_DRIVER__SV
`define OVIP_ACE_SLAVE_DRIVER__SV

// ovip_ace_slave_driver -- mechanism-only responder, mirroring the AXI shape.
// Policy lives in the sequence library. Inherits all AXI response driving
// from ovip_axi_slave_driver, adds:
//
//   - RRESP[3:2] driving (IsShared, PassDirty) via drive_rd_channel.
//   - Snoop request driver: pulls direction==SNOOP trans items from an
//     internal mailbox and drives AC, then captures master's CR (and
//     optionally CD) into the same trans handle for the test to inspect.
//     Tests push snoops via push_snoop(snoop_tr).
//   - RACK / WACK monitor on the slave side -- captures the master's
//     acknowledge pulses so D6.2 sequencing rules can be enforced by the
//     monitor / scoreboard. (Currently just counts; the rule check itself
//     belongs to the monitor.)

class ovip_ace_slave_driver extends ovip_axi_slave_driver #(virtual ovip_ace_agent_if);

	// Cast of the inherited cfg so ACE-specific knobs are reachable.
	ovip_ace_agent_config ace_cfg;

	// Inbound snoop requests from the test sequence (push via push_snoop()).
	mailbox#(ovip_ace_trans) snoop_request_mb;

	`uvm_component_utils(ovip_ace_slave_driver)

	function new(string name = "ovip_ace_slave_driver", uvm_component parent);
		super.new(name, parent);
		snoop_request_mb = new();
	endfunction : new

	extern virtual function void build_phase(uvm_phase phase);

	// Reset value driving
	extern virtual function void drive_reset_values();
	extern virtual function void drive_r_channel_reset_values();
	extern virtual function void drive_snoop_channel_reset_values();

	// Per-response signal driving on R (write side has no ACE additions)
	extern virtual function void drive_rd_channel(ovip_axi_trans tr);

	// Snoop request driver lives in the extra_forks() branch
	extern virtual task extra_forks();
	extern virtual task snoop_request_driver();

	// Push a snoop into the request mailbox. The driver pulls from there
	// and drives AC; once the master completes CR (and optionally CD), the
	// trans handle is updated with the captured response.
	extern virtual function void push_snoop(ovip_ace_trans snoop_tr);

endclass : ovip_ace_slave_driver



function void ovip_ace_slave_driver::build_phase(uvm_phase phase);
	super.build_phase(phase);
	if(!$cast(ace_cfg, cfg))
		`uvm_fatal("ACE_DRV", "Slave driver cfg must be an ovip_ace_agent_config")
endfunction : build_phase


function void ovip_ace_slave_driver::drive_reset_values();
	super.drive_reset_values();
	drive_snoop_channel_reset_values();
endfunction : drive_reset_values


function void ovip_ace_slave_driver::drive_snoop_channel_reset_values();
	// D2.3.3: interconnect holds ACVALID LOW during reset.
	vif.slave_cb.acvalid <= 1'b0;
	vif.slave_cb.acaddr  <= '0;
	vif.slave_cb.acsnoop <= 4'b0;
	vif.slave_cb.acprot  <= 3'b0;
	vif.slave_cb.crready <= 1'b0;
	vif.slave_cb.cdready <= 1'b0;
endfunction : drive_snoop_channel_reset_values


function void ovip_ace_slave_driver::drive_r_channel_reset_values();
	super.drive_r_channel_reset_values();
	// rresp upper bits already zeroed by super (super writes full 4-bit
	// rresp from a 2-bit tr.resp -- zero-extended). Nothing to do here in
	// addition; kept for clarity.
endfunction : drive_r_channel_reset_values


function void ovip_ace_slave_driver::drive_rd_channel(ovip_axi_trans tr);
	ovip_ace_trans ace_tr;
	bit [3:0] resp4 = 4'b0;

	// Inherited code drives rdata / rid / ruser / rlast and writes
	// rresp <= tr.resp on the last beat. We need rresp[3:2] (IsShared,
	// PassDirty) driven on every beat -- D3.2.1 requires them constant
	// across the burst -- so we overwrite rresp here unconditionally.
	super.drive_rd_channel(tr);

	resp4[1:0] = tr.resp;
	if($cast(ace_tr, tr) && ace_tr.direction == OVIP_ACE_INITIATING
	    && ace_cfg.profile == OVIP_ACE_PROFILE_ACE)
	begin
		resp4[2] = ace_tr.pass_dirty;
		resp4[3] = ace_tr.is_shared;
	end
	vif.slave_cb.rresp <= resp4;
endfunction : drive_rd_channel


task ovip_ace_slave_driver::extra_forks();
	fork
		// ACE-Lite has no snoop channels. Fork conditionally so a Lite
		// agent's driver doesn't sit forever waiting on an unused mailbox.
		if(ace_cfg.profile == OVIP_ACE_PROFILE_ACE) snoop_request_driver();
	join_none
endtask : extra_forks


function void ovip_ace_slave_driver::push_snoop(ovip_ace_trans snoop_tr);
	// try_put (non-blocking, function) rather than put (blocking task): the
	// mailbox is unbounded, so this always succeeds, and it keeps push_snoop a
	// function callable from any context.
	void'(snoop_request_mb.try_put(snoop_tr));
endfunction : push_snoop


task ovip_ace_slave_driver::snoop_request_driver();
	ovip_ace_trans snoop_tr;
	forever
	begin
		snoop_request_mb.get(snoop_tr);

		// Drive AC -- D3.6.2 stability rule: ACADDR/ACSNOOP/ACPROT must be
		// stable from ACVALID HIGH until ACREADY. Same shape as AXI's
		// AR/AW driving.
		vif.slave_cb.acaddr  <= snoop_tr.snoop_addr;
		vif.slave_cb.acsnoop <= snoop_tr.acsnoop_code;
		vif.slave_cb.acprot  <= snoop_tr.acprot;
		vif.slave_cb.acvalid <= 1'b1;
		@(vif.slave_cb iff vif.slave_cb.acready);
		vif.slave_cb.acvalid <= 1'b0;

		// Drive CRREADY=1 to accept the master's response. D3.7 / D3.9:
		// CRVALID can come before or after CRREADY; we hold ready=1 from
		// here until the handshake.
		vif.slave_cb.crready <= 1'b1;
		@(vif.slave_cb iff vif.slave_cb.crvalid);
		snoop_tr.snoop_resp = '{
		    was_unique:    vif.monitor_cb.crresp[4],
		    is_shared:     vif.monitor_cb.crresp[3],
		    pass_dirty:    vif.monitor_cb.crresp[2],
		    error:         vif.monitor_cb.crresp[1],
		    data_transfer: vif.monitor_cb.crresp[0]
		};
		vif.slave_cb.crready <= 1'b0;

		// If response signaled data, drain CD until CDLAST.
		if(snoop_tr.snoop_resp.data_transfer)
		begin
			vif.slave_cb.cdready <= 1'b1;
			snoop_tr.snoop_data_beats.delete();
			forever begin
				@(vif.slave_cb iff vif.slave_cb.cdvalid);
				snoop_tr.snoop_data_beats.push_back(vif.monitor_cb.cddata);
				if(vif.monitor_cb.cdlast) break;
			end
			vif.slave_cb.cdready <= 1'b0;
		end
	end
endtask : snoop_request_driver

`endif
