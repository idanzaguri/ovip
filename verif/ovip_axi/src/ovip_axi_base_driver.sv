`ifndef OVIP_AXI_BASE_DRIVER__SV
`define OVIP_AXI_BASE_DRIVER__SV

virtual class ovip_axi_base_driver extends uvm_driver#(ovip_axi_trans);
	ovip_axi_agent_config cfg;
	virtual ovip_axi_agent_if vif;

	function new(string name = "ovip_axi_base_driver", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	extern virtual task run_phase(uvm_phase phase);
	extern virtual function void build_phase(uvm_phase phase);

	extern virtual task rst_monitor();
	extern virtual function void reset_internal_state();

	pure virtual task raddr_phase_driver(); // initiator
	pure virtual task rdata_phase_driver(); // target

	pure virtual task waddr_phase_driver(); // initiator
	pure virtual task wdata_phase_driver(); // initiator
	pure virtual task bresp_phase_driver(); // target

	pure virtual task transaction_acceptor();

	pure virtual function void drive_reset_values();

	/*pure*/ virtual function void drive_ar_channel_reset_values();endfunction
	/*pure*/ virtual function void drive_r_channel_reset_values();endfunction

	/*pure*/ virtual function void drive_aw_channel_reset_values();endfunction
	/*pure*/ virtual function void drive_w_channel_reset_values();endfunction
	/*pure*/ virtual function void drive_b_channel_reset_values();endfunction

endclass : ovip_axi_base_driver

task ovip_axi_base_driver::rst_monitor();
	@(vif.monitor_cb iff vif.monitor_cb.aresetn == 1'b0);
	`uvm_info("AXI_DRV/RST_MON", "Reset asserted!", UVM_DEBUG)
endtask : rst_monitor

function void ovip_axi_base_driver::reset_internal_state();
	// clean all internal queues on reset
endfunction : reset_internal_state

function void ovip_axi_base_driver::build_phase(uvm_phase phase);
	super.build_phase(phase);

	if (!uvm_config_db#(virtual ovip_axi_agent_if)::get(this, "", "vif", vif))
	begin
		`uvm_fatal("MISSING_VIF",$sformatf("Missing virtual interface - %s.vif", this.get_full_name()))
	end

endfunction : build_phase


task ovip_axi_base_driver::run_phase(uvm_phase phase);
	super.run_phase(phase);

	forever
	begin
		reset_internal_state();
		drive_reset_values();
		@(vif.monitor_cb iff vif.monitor_cb.aresetn); // Waiting for sync reset de-assertion
		`BEGIN_FIRST_OF
			rst_monitor();
			transaction_acceptor();
			fork
				if(cfg.interface_type != OVIP_AXI_WRITE_ONLY_INTERFACE) raddr_phase_driver();
				if(cfg.interface_type != OVIP_AXI_WRITE_ONLY_INTERFACE) rdata_phase_driver();
				if(cfg.interface_type != OVIP_AXI_READ_ONLY_INTERFACE)  waddr_phase_driver();
				if(cfg.interface_type != OVIP_AXI_READ_ONLY_INTERFACE)  wdata_phase_driver();
				if(cfg.interface_type != OVIP_AXI_READ_ONLY_INTERFACE)  bresp_phase_driver();
			join
		`END_FIRST_OF
	end

endtask : run_phase

`endif
