`ifndef OVIP_AXI_STREAM_AGENT__SV
`define OVIP_AXI_STREAM_AGENT__SV

class ovip_axi_stream_agent extends uvm_agent;
	ovip_axi_stream_agent_config cfg;
	virtual ovip_axi_stream_agent_if vif;

	ovip_axi_stream_monitor mon;

	// Active-only handles. The slave driver is pattern-driven so it has no
	// sequencer of its own; the slave sequence drives the receiver via the
	// monitor's response_req_port and by calling slave_drv.put_tready_pattern.
	ovip_axi_stream_master_driver     master_drv;
	uvm_sequencer#(ovip_axi_stream_trans) master_sqr;
	ovip_axi_stream_slave_driver      slave_drv;
	ovip_axi_stream_slave_sequencer   slave_sqr;

	`uvm_component_utils(ovip_axi_stream_agent)

	function new(string name = "ovip_axi_stream_agent", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	extern virtual function void build_phase(uvm_phase phase);
	extern virtual function void connect_phase(uvm_phase phase);

endclass : ovip_axi_stream_agent


function void ovip_axi_stream_agent::build_phase(uvm_phase phase);
	if(cfg == null)
		if(!uvm_config_db#(ovip_axi_stream_agent_config)::get(this, "", "cfg", cfg))
			`uvm_fatal("MISSING_CFG", $sformatf("Missing config object - %s.cfg", get_full_name()))
	void'(cfg.check_config());

	is_active = cfg.is_active;
	super.build_phase(phase);

	// Push cfg down to children so each build_phase finds it.
	uvm_config_db#(ovip_axi_stream_agent_config)::set(this, "mon", "cfg", cfg);

	mon = ovip_axi_stream_monitor::type_id::create("mon", this);
	mon.cfg = cfg;

	if(get_is_active())
	begin
		if(cfg.agent_type == OVIP_AXI_STREAM_TRANSMITTER)
		begin
			uvm_config_db#(ovip_axi_stream_agent_config)::set(this, "master_drv", "cfg", cfg);
			master_drv = ovip_axi_stream_master_driver::type_id::create("master_drv", this);
			master_drv.cfg = cfg;
			master_sqr = uvm_sequencer#(ovip_axi_stream_trans)::type_id::create("master_sqr", this);
		end
		else
		begin
			uvm_config_db#(ovip_axi_stream_agent_config)::set(this, "slave_drv", "cfg", cfg);
			slave_drv = ovip_axi_stream_slave_driver::type_id::create("slave_drv", this);
			slave_drv.cfg = cfg;
			slave_sqr = ovip_axi_stream_slave_sequencer::type_id::create("slave_sqr", this);
		end
	end
endfunction : build_phase


function void ovip_axi_stream_agent::connect_phase(uvm_phase phase);
	super.connect_phase(phase);

	if(!uvm_config_db#(virtual ovip_axi_stream_agent_if)::get(this, "", "vif", vif))
		`uvm_fatal("MISSING_VIF", $sformatf("Missing virtual interface - %s.vif", get_full_name()))

	mon.vif = vif;

	if(get_is_active())
	begin
		if(cfg.agent_type == OVIP_AXI_STREAM_TRANSMITTER)
		begin
			master_drv.vif = vif;
			master_drv.seq_item_port.connect(master_sqr.seq_item_export);
		end
		else
		begin
			slave_drv.vif        = vif;
			slave_sqr.slave_drv  = slave_drv;
			slave_sqr.response_req_port.connect(mon.response_req_port);
		end
	end
endfunction : connect_phase

`endif
