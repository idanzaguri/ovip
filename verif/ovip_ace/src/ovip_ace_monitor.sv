`ifndef OVIP_ACE_MONITOR__SV
`define OVIP_ACE_MONITOR__SV

// ovip_ace_monitor -- observes an ACE / ACE-Lite port. Inherits the whole AXI
// address/data/response reconstruction from ovip_axi_monitor and layers the
// ACE additions on top:
//
//   - Every reconstructed transaction is an ovip_ace_trans (via the
//     new_transaction() override), so subscribers get the ACE fields.
//   - AR/AW capture ARDOMAIN/ARSNOOP/ARBAR and AWDOMAIN/AWSNOOP/AWBAR/AWUNIQUE
//     (sample_read_address / sample_write_address overrides).
//   - R capture picks up RRESP[3:2] (IsShared, PassDirty) (sample_read_data).
//   - A snoop-channel monitor reconstructs AC -> CR (-> CD) snoop transactions
//     and broadcasts them on snoop_analysis_port (ACE profile only).
//   - A RACK/WACK sequencing monitor enforces the D6.2 acknowledge rules.
//   - Inline protocol checks cover the legal AxSNOOP/AxDOMAIN envelope (D3.1),
//     the cache-line-size addressing rules (D3.1.6), the ACE-Lite permitted
//     subset (D11), and the snoop-response consistency rules (D3.7 / D5.1).
//
// Scope note (v0.1): the snoop-channel monitor assumes a single outstanding
// snoop at a time (AC -> CR -> CD in order), matching the ovip_ace slave
// driver's one-at-a-time snoop_request_driver.

class ovip_ace_monitor extends ovip_axi_monitor #(virtual ovip_ace_agent_if);

	// Cast of the inherited cfg so ACE-specific knobs are reachable.
	ovip_ace_agent_config ace_cfg;

	// Broadcast reconstructed snoop transactions (direction == SNOOP).
	uvm_analysis_port #(ovip_ace_trans) snoop_analysis_port;

	// Masks for the ACE-only buses (sized to the maximum wire width; the cfg
	// picks how many bits are actually active).
	ovip_ace_acaddr_t ACADDR_MASK;
	ovip_ace_cddata_t CDDATA_MASK;

	`uvm_component_utils(ovip_ace_monitor)

	function new(string name = "ovip_ace_monitor", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	extern virtual function void build_phase(uvm_phase phase);
	extern virtual task run_phase(uvm_phase phase);

	// Produce ovip_ace_trans instead of ovip_axi_trans for every reconstructed
	// transaction, so the ACE fields ride along and subscribers can $cast.
	extern virtual function ovip_axi_trans new_transaction();

	// Channel sampling overrides -- add the ACE additions after the AXI capture.
	extern virtual function void sample_read_address(ovip_axi_trans tr);
	extern virtual function void sample_write_address(ovip_axi_trans tr);
	extern virtual function void sample_read_data(ovip_axi_trans tr);

	// ACE-specific per-channel monitors, forked alongside the AXI ones.
	extern virtual task extra_forks();
	extern virtual task snoop_channel_monitor();
	extern virtual task rack_wack_sequencing_monitor();
	extern virtual task ace_handshake_signals_xz_monitor();
	`ifndef OVIP_AXI_DISABLE_XZ_AND_SIGNALS_STABILITY_CHECKS
		extern virtual task ac_channel_signal_stability_check();
		extern virtual task cr_channel_signal_stability_check();
		extern virtual task cd_channel_signal_stability_check();
	`endif

	// ACE protocol checks.
	extern virtual function void check_ace_read_address(ovip_ace_trans tr);
	extern virtual function void check_ace_write_address(ovip_ace_trans tr);
	extern virtual function void check_snoop(ovip_ace_trans tr);

	// Small predicates shared by the checks.
	extern virtual function bit is_coherent_cacheable_read(bit [3:0] snoop);
	extern virtual function bit is_cache_line_transaction(bit [3:0] snoop);

endclass : ovip_ace_monitor



function void ovip_ace_monitor::build_phase(uvm_phase phase);
	super.build_phase(phase);
	if(!$cast(ace_cfg, cfg))
		`uvm_fatal("ACE_MON", "Monitor cfg must be an ovip_ace_agent_config")
	snoop_analysis_port = new("snoop_analysis_port", this);
endfunction : build_phase


task ovip_ace_monitor::run_phase(uvm_phase phase);
	// Set the ACE-only masks before the inherited run_phase spins up the
	// channel monitors. The idiom mirrors the AXI masks: shifting by the full
	// wire width wraps to 0, so (1<<W)-1 yields an all-ones mask.
	ACADDR_MASK = (ovip_ace_acaddr_t'(1) << ace_cfg.acaddr_width) - 1;
	CDDATA_MASK = (ovip_ace_cddata_t'(1) << ace_cfg.cddata_width) - 1;
	super.run_phase(phase);
endtask : run_phase


function ovip_axi_trans ovip_ace_monitor::new_transaction();
	ovip_ace_trans tr = ovip_ace_trans::type_id::create($sformatf("ace_tr_%0d", ++transaction_counter));
	tr.bus_width = cfg.bus_width;
	analysis_port_cont.write(tr);
	return tr;
endfunction : new_transaction


// ----------------------------------------------------------------------------------- //
//                              Channel sampling overrides                             //
// ----------------------------------------------------------------------------------- //

function void ovip_ace_monitor::sample_read_address(ovip_axi_trans tr);
	ovip_ace_trans ace_tr;
	super.sample_read_address(tr);
	if(!$cast(ace_tr, tr)) return;

	ace_tr.direction = OVIP_ACE_INITIATING;
	ace_tr.domain    = ovip_ace_domain_t'(vif.monitor_cb.ardomain);
	ace_tr.snoop     = vif.monitor_cb.arsnoop;
	ace_tr.bar       = ovip_ace_bar_t'(vif.monitor_cb.arbar);

	check_ace_read_address(ace_tr);
endfunction : sample_read_address


function void ovip_ace_monitor::sample_write_address(ovip_axi_trans tr);
	ovip_ace_trans ace_tr;
	super.sample_write_address(tr);
	if(!$cast(ace_tr, tr)) return;

	ace_tr.direction = OVIP_ACE_INITIATING;
	ace_tr.domain    = ovip_ace_domain_t'(vif.monitor_cb.awdomain);
	ace_tr.snoop     = {1'b0, vif.monitor_cb.awsnoop}; // AWSNOOP is 3 bits; MSB is 0
	ace_tr.bar       = ovip_ace_bar_t'(vif.monitor_cb.awbar);
	ace_tr.awunique  = vif.monitor_cb.awunique;

	check_ace_write_address(ace_tr);
endfunction : sample_write_address


function void ovip_ace_monitor::sample_read_data(ovip_axi_trans tr);
	ovip_ace_trans ace_tr;
	super.sample_read_data(tr); // captures rresp[1:0] into tr.resp on the last beat

	// RRESP[3:2] (IsShared / PassDirty) are constant across the burst (D3.2.1);
	// capture them alongside the final response. ACE-Lite ties [3:2] to 0.
	if(ace_cfg.profile == OVIP_ACE_PROFILE_ACE && tr.got_last_beat && $cast(ace_tr, tr))
	begin
		ace_tr.is_shared  = vif.monitor_cb.rresp[3];
		ace_tr.pass_dirty = vif.monitor_cb.rresp[2];
	end
endfunction : sample_read_data


// ----------------------------------------------------------------------------------- //
//                              ACE per-channel monitors                               //
// ----------------------------------------------------------------------------------- //

task ovip_ace_monitor::extra_forks();
	fork
		ace_handshake_signals_xz_monitor();
		// RACK/WACK and the snoop channels only exist in full ACE.
		if(ace_cfg.profile == OVIP_ACE_PROFILE_ACE)
		begin
			rack_wack_sequencing_monitor();
			snoop_channel_monitor();
		end
		`ifndef OVIP_AXI_DISABLE_XZ_AND_SIGNALS_STABILITY_CHECKS
			if(ace_cfg.profile == OVIP_ACE_PROFILE_ACE)
			begin
				ac_channel_signal_stability_check();
				cr_channel_signal_stability_check();
				cd_channel_signal_stability_check();
			end
		`endif
	join_none
endtask : extra_forks


task ovip_ace_monitor::snoop_channel_monitor();
	forever
	begin
		ovip_ace_trans snoop_tr;

		// AC handshake -- a new snoop request from the interconnect.
		@(vif.monitor_cb iff vif.monitor_cb.aresetn && vif.monitor_cb.acvalid && vif.monitor_cb.acready);

		snoop_tr = ovip_ace_trans::type_id::create($sformatf("ace_snoop_%0d", ++transaction_counter));
		snoop_tr.direction    = OVIP_ACE_SNOOP;
		snoop_tr.snoop_addr   = vif.monitor_cb.acaddr & ACADDR_MASK;
		snoop_tr.acsnoop_code = vif.monitor_cb.acsnoop;
		snoop_tr.acprot       = vif.monitor_cb.acprot;

		// CR handshake -- the master's snoop response.
		@(vif.monitor_cb iff vif.monitor_cb.crvalid && vif.monitor_cb.crready);
		snoop_tr.snoop_resp = '{
		    was_unique:    vif.monitor_cb.crresp[4],
		    is_shared:     vif.monitor_cb.crresp[3],
		    pass_dirty:    vif.monitor_cb.crresp[2],
		    error:         vif.monitor_cb.crresp[1],
		    data_transfer: vif.monitor_cb.crresp[0]
		};

		// CD -- optional snoop data, only when CRRESP.DataTransfer is set.
		if(snoop_tr.snoop_resp.data_transfer)
		begin
			forever
			begin
				@(vif.monitor_cb iff vif.monitor_cb.cdvalid && vif.monitor_cb.cdready);
				snoop_tr.snoop_data_beats.push_back(vif.monitor_cb.cddata & CDDATA_MASK);
				if(vif.monitor_cb.cdlast) break;
			end
		end

		check_snoop(snoop_tr);
		`uvm_info({MESSAGE_TAG, "ACE_MON/SNOOP"}, snoop_tr.convert2string(), UVM_LOW)
		snoop_analysis_port.write(snoop_tr);
	end
endtask : snoop_channel_monitor


task ovip_ace_monitor::rack_wack_sequencing_monitor();
	// D6.2: the master issues exactly one RACK per completed read (after the
	// RLAST beat is accepted) and one WACK per completed write (after BRESP is
	// accepted). RACK/WACK are single-cycle. We track how many acknowledges are
	// owed and flag a pulse that arrives with none pending, or that stays high
	// for more than one cycle.
	int unsigned owed_rack = 0;
	int unsigned owed_wack = 0;
	fork
		forever begin
			@(vif.monitor_cb iff vif.monitor_cb.aresetn && vif.monitor_cb.rvalid && vif.monitor_cb.rready && vif.monitor_cb.rlast);
			owed_rack++;
		end
		forever begin
			@(vif.monitor_cb iff vif.monitor_cb.aresetn && vif.monitor_cb.bvalid && vif.monitor_cb.bready);
			owed_wack++;
		end
		forever begin
			@(vif.monitor_cb iff vif.monitor_cb.aresetn && vif.monitor_cb.rack);
			if(owed_rack == 0)
				`uvm_error({MESSAGE_TAG, "ACE_MON/RACK"}, "RACK asserted with no completed read transaction awaiting acknowledge (D6.2)")
			else
				owed_rack--;
			@(vif.monitor_cb);
			if(vif.monitor_cb.rack)
				`uvm_error({MESSAGE_TAG, "ACE_MON/RACK"}, "RACK must be asserted for exactly one cycle (D3.3)")
		end
		forever begin
			@(vif.monitor_cb iff vif.monitor_cb.aresetn && vif.monitor_cb.wack);
			if(owed_wack == 0)
				`uvm_error({MESSAGE_TAG, "ACE_MON/WACK"}, "WACK asserted with no completed write transaction awaiting acknowledge (D6.2)")
			else
				owed_wack--;
			@(vif.monitor_cb);
			if(vif.monitor_cb.wack)
				`uvm_error({MESSAGE_TAG, "ACE_MON/WACK"}, "WACK must be asserted for exactly one cycle (D3.5)")
		end
	join
endtask : rack_wack_sequencing_monitor


task ovip_ace_monitor::ace_handshake_signals_xz_monitor();
	forever
	begin
		@(vif.monitor_cb iff vif.monitor_cb.aresetn);
		if(ace_cfg.profile != OVIP_ACE_PROFILE_ACE) continue;
		`OVIP_AXI_MON_XZ_CHECK(acvalid, ACVALID)
		`OVIP_AXI_MON_XZ_CHECK(acready, ACREADY)
		`OVIP_AXI_MON_XZ_CHECK(crvalid, CRVALID)
		`OVIP_AXI_MON_XZ_CHECK(crready, CRREADY)
		`OVIP_AXI_MON_XZ_CHECK(cdvalid, CDVALID)
		`OVIP_AXI_MON_XZ_CHECK(cdready, CDREADY)
		`OVIP_AXI_MON_XZ_CHECK(rack,    RACK)
		`OVIP_AXI_MON_XZ_CHECK(wack,    WACK)
	end
endtask : ace_handshake_signals_xz_monitor


`ifndef OVIP_AXI_DISABLE_XZ_AND_SIGNALS_STABILITY_CHECKS
task ovip_ace_monitor::ac_channel_signal_stability_check();
	// D3.6.2: ACADDR/ACSNOOP/ACPROT must be stable, and ACVALID must stay
	// asserted, from ACVALID HIGH until the ACREADY handshake.
	forever
	begin
		ovip_ace_acaddr_t s_addr;
		bit [3:0]         s_snoop;
		bit [2:0]         s_prot;

		@(vif.monitor_cb iff vif.monitor_cb.aresetn && vif.monitor_cb.acvalid);
		s_addr  = vif.monitor_cb.acaddr;
		s_snoop = vif.monitor_cb.acsnoop;
		s_prot  = vif.monitor_cb.acprot;

		while(!(vif.monitor_cb.acvalid && vif.monitor_cb.acready))
		begin
			@(vif.monitor_cb);
			if(!vif.monitor_cb.aresetn) break;
			if(!vif.monitor_cb.acvalid)
			begin
				`uvm_error({MESSAGE_TAG, "ACE_MON/AC_STABILITY"}, "ACVALID de-asserted before ACREADY (D3.6.2)")
				break;
			end
			if(vif.monitor_cb.acaddr !== s_addr || vif.monitor_cb.acsnoop !== s_snoop || vif.monitor_cb.acprot !== s_prot)
				`uvm_error({MESSAGE_TAG, "ACE_MON/AC_STABILITY"}, "AC payload (ACADDR/ACSNOOP/ACPROT) changed before ACREADY (D3.6.2)")
		end
	end
endtask : ac_channel_signal_stability_check


task ovip_ace_monitor::cr_channel_signal_stability_check();
	// CRRESP must be stable and CRVALID must stay asserted from CRVALID HIGH
	// until the CRREADY handshake.
	forever
	begin
		bit [4:0] s_resp;
		@(vif.monitor_cb iff vif.monitor_cb.aresetn && vif.monitor_cb.crvalid);
		s_resp = vif.monitor_cb.crresp;

		while(!(vif.monitor_cb.crvalid && vif.monitor_cb.crready))
		begin
			@(vif.monitor_cb);
			if(!vif.monitor_cb.aresetn) break;
			if(!vif.monitor_cb.crvalid)
			begin
				`uvm_error({MESSAGE_TAG, "ACE_MON/CR_STABILITY"}, "CRVALID de-asserted before CRREADY")
				break;
			end
			if(vif.monitor_cb.crresp !== s_resp)
				`uvm_error({MESSAGE_TAG, "ACE_MON/CR_STABILITY"}, "CRRESP changed before CRREADY")
		end
	end
endtask : cr_channel_signal_stability_check


task ovip_ace_monitor::cd_channel_signal_stability_check();
	// CDDATA/CDLAST must be stable and CDVALID must stay asserted from CDVALID
	// HIGH until the CDREADY handshake.
	forever
	begin
		ovip_ace_cddata_t s_data;
		bit               s_last;
		@(vif.monitor_cb iff vif.monitor_cb.aresetn && vif.monitor_cb.cdvalid);
		s_data = vif.monitor_cb.cddata;
		s_last = vif.monitor_cb.cdlast;

		while(!(vif.monitor_cb.cdvalid && vif.monitor_cb.cdready))
		begin
			@(vif.monitor_cb);
			if(!vif.monitor_cb.aresetn) break;
			if(!vif.monitor_cb.cdvalid)
			begin
				`uvm_error({MESSAGE_TAG, "ACE_MON/CD_STABILITY"}, "CDVALID de-asserted before CDREADY")
				break;
			end
			if(vif.monitor_cb.cddata !== s_data || vif.monitor_cb.cdlast !== s_last)
				`uvm_error({MESSAGE_TAG, "ACE_MON/CD_STABILITY"}, "CD payload (CDDATA/CDLAST) changed before CDREADY")
		end
	end
endtask : cd_channel_signal_stability_check
`endif


// ----------------------------------------------------------------------------------- //
//                                  Protocol checks                                    //
// ----------------------------------------------------------------------------------- //

function bit ovip_ace_monitor::is_coherent_cacheable_read(bit [3:0] snoop);
	// Reads that operate on a cache line and require a shareable domain.
	case(snoop)
		OVIP_ACE_ARSNOOP_READ_SHARED,
		OVIP_ACE_ARSNOOP_READ_CLEAN,
		OVIP_ACE_ARSNOOP_READ_NOT_SHARED_DIRTY,
		OVIP_ACE_ARSNOOP_READ_UNIQUE,
		OVIP_ACE_ARSNOOP_CLEAN_UNIQUE,
		OVIP_ACE_ARSNOOP_MAKE_UNIQUE: return 1;
		default: return 0;
	endcase
endfunction : is_coherent_cacheable_read


function bit ovip_ace_monitor::is_cache_line_transaction(bit [3:0] snoop);
	// Coherent + cache-maintenance reads address exactly one full cache line
	// (D3.1.6). ReadOnce/ReadNoSnoop (0b0000) and DVM are excluded.
	case(snoop)
		OVIP_ACE_ARSNOOP_READ_SHARED,
		OVIP_ACE_ARSNOOP_READ_CLEAN,
		OVIP_ACE_ARSNOOP_READ_NOT_SHARED_DIRTY,
		OVIP_ACE_ARSNOOP_READ_UNIQUE,
		OVIP_ACE_ARSNOOP_CLEAN_UNIQUE,
		OVIP_ACE_ARSNOOP_MAKE_UNIQUE,
		OVIP_ACE_ARSNOOP_CLEAN_SHARED,
		OVIP_ACE_ARSNOOP_CLEAN_INVALID,
		OVIP_ACE_ARSNOOP_MAKE_INVALID: return 1;
		default: return 0;
	endcase
endfunction : is_cache_line_transaction


function void ovip_ace_monitor::check_ace_read_address(ovip_ace_trans tr);
	ovip_ace_arsnoop_t s;
	string tag = {MESSAGE_TAG, "ACE_MON/RD"};

	// Legal ARSNOOP encoding (Table D3-7). $cast fails on a reserved value.
	if(!$cast(s, tr.snoop))
	begin
		`uvm_error(tag, $sformatf("Reserved ARSNOOP encoding 0b%4b (Table D3-7)", tr.snoop))
		tr.monitor_error = 1;
		return;
	end

	// Coherent reads require an Inner/Outer Shareable domain (D3.1.1).
	if(is_coherent_cacheable_read(tr.snoop) &&
	   !(tr.domain inside {OVIP_ACE_DOMAIN_INNER_SHAREABLE, OVIP_ACE_DOMAIN_OUTER_SHAREABLE}))
	begin
		`uvm_error(tag, $sformatf("%s must use Inner/Outer Shareable AxDOMAIN, got %s (D3.1.1)", tr.transaction_name(), tr.domain.name()))
		tr.monitor_error = 1;
	end

	// Cache-line transactions address exactly one aligned cache line (D3.1.6).
	if(is_cache_line_transaction(tr.snoop))
	begin
		int total_bytes = (tr.len + 1) * (1 << tr.size);
		if(tr.burst != OVIP_AXI_BURST_INCR)
		begin
			`uvm_error(tag, $sformatf("%s must use an INCR burst (D3.1.6)", tr.transaction_name()))
			tr.monitor_error = 1;
		end
		if(total_bytes != ace_cfg.cache_line_size)
		begin
			`uvm_error(tag, $sformatf("%s must transfer exactly one cache line (%0dB), got %0dB (D3.1.6)", tr.transaction_name(), ace_cfg.cache_line_size, total_bytes))
			tr.monitor_error = 1;
		end
		if(tr.addr % ace_cfg.cache_line_size != 0)
		begin
			`uvm_error(tag, $sformatf("%s start address 0x%0h must be aligned to the cache line size (%0dB) (D3.1.6)", tr.transaction_name(), tr.addr, ace_cfg.cache_line_size))
			tr.monitor_error = 1;
		end
	end

	// ACE-Lite masters have no cache: coherent cacheable reads are forbidden
	// (Table D11-1). ReadOnce/ReadNoSnoop and cache maintenance remain legal.
	if(ace_cfg.profile == OVIP_ACE_PROFILE_ACE_LITE && is_coherent_cacheable_read(tr.snoop))
	begin
		`uvm_error(tag, $sformatf("ACE-Lite master must not issue %s (Table D11-1)", tr.transaction_name()))
		tr.monitor_error = 1;
	end
endfunction : check_ace_read_address


function void ovip_ace_monitor::check_ace_write_address(ovip_ace_trans tr);
	ovip_ace_awsnoop_t s;
	string tag = {MESSAGE_TAG, "ACE_MON/WR"};

	// Legal AWSNOOP encoding (Table D3-8). $cast fails on a reserved value.
	if(!$cast(s, tr.snoop[2:0]))
	begin
		`uvm_error(tag, $sformatf("Reserved AWSNOOP encoding 0b%3b (Table D3-8)", tr.snoop[2:0]))
		tr.monitor_error = 1;
		return;
	end

	// Coherent writes (AWSNOOP != 0b000) require a shareable domain (D3.1.1).
	if(tr.snoop[2:0] != OVIP_ACE_AWSNOOP_WRITE_NO_SNOOP_OR_WRITE_UNIQUE &&
	   !(tr.domain inside {OVIP_ACE_DOMAIN_INNER_SHAREABLE, OVIP_ACE_DOMAIN_OUTER_SHAREABLE}))
	begin
		`uvm_error(tag, $sformatf("%s must use Inner/Outer Shareable AxDOMAIN, got %s (D3.1.1)", tr.transaction_name(), tr.domain.name()))
		tr.monitor_error = 1;
	end

	// AWUNIQUE is only meaningful on WriteEvict (Table D3-9); on any other
	// write it must be LOW.
	if(tr.awunique && tr.snoop[2:0] != OVIP_ACE_AWSNOOP_WRITE_EVICT)
	begin
		`uvm_error(tag, $sformatf("AWUNIQUE asserted on %s; only WriteEvict may set AWUNIQUE (Table D3-9)", tr.transaction_name()))
		tr.monitor_error = 1;
	end

	// WriteEvict requires the master to advertise support for it (D2.1.2).
	if(tr.snoop[2:0] == OVIP_ACE_AWSNOOP_WRITE_EVICT && !ace_cfg.supports_write_evict)
	begin
		`uvm_error(tag, "WriteEvict issued but cfg.supports_write_evict is 0 (D2.1.2)")
		tr.monitor_error = 1;
	end

	// ACE-Lite writes are limited to WriteNoSnoop / WriteUnique / WriteLineUnique
	// (Table D11-2).
	if(ace_cfg.profile == OVIP_ACE_PROFILE_ACE_LITE &&
	   !(tr.snoop[2:0] inside {OVIP_ACE_AWSNOOP_WRITE_NO_SNOOP_OR_WRITE_UNIQUE, OVIP_ACE_AWSNOOP_WRITE_LINE_UNIQUE}))
	begin
		`uvm_error(tag, $sformatf("ACE-Lite master must not issue %s (Table D11-2)", tr.transaction_name()))
		tr.monitor_error = 1;
	end
endfunction : check_ace_write_address


function void ovip_ace_monitor::check_snoop(ovip_ace_trans tr);
	ovip_ace_acsnoop_t s;
	string tag = {MESSAGE_TAG, "ACE_MON/SNOOP"};
	bit is_dvm;

	// Legal ACSNOOP encoding -- a strict subset of ARSNOOP (Table D3-19).
	if(!$cast(s, tr.acsnoop_code))
	begin
		`uvm_error(tag, $sformatf("Reserved ACSNOOP encoding 0b%4b (Table D3-19)", tr.acsnoop_code))
		tr.monitor_error = 1;
		return;
	end

	is_dvm = (s == OVIP_ACE_ACSNOOP_DVM_COMPLETE || s == OVIP_ACE_ACSNOOP_DVM_MESSAGE);

	// A DVM snoop never transfers snoop data (D5.4).
	if(is_dvm && tr.snoop_resp.data_transfer)
	begin
		`uvm_error(tag, "CRRESP.DataTransfer set on a DVM snoop; DVM must not transfer data (D5.4)")
		tr.monitor_error = 1;
	end

	// PassDirty is only meaningful when data is transferred (Table D3-21).
	if(tr.snoop_resp.pass_dirty && !tr.snoop_resp.data_transfer)
	begin
		`uvm_error(tag, "CRRESP.PassDirty set without CRRESP.DataTransfer (Table D3-21)")
		tr.monitor_error = 1;
	end

	// When data is transferred, the CD burst must carry exactly one cache line.
	if(tr.snoop_resp.data_transfer)
	begin
		int bytes_per_beat = ace_cfg.cddata_width / 8;
		int expected_beats = (bytes_per_beat > 0) ?
			(ace_cfg.cache_line_size + bytes_per_beat - 1) / bytes_per_beat : 0;
		if(tr.snoop_data_beats.size() != expected_beats)
			`uvm_error(tag, $sformatf("Snoop data transferred %0d CD beats; expected %0d (cache_line_size %0dB / cddata_width %0db)",
				tr.snoop_data_beats.size(), expected_beats, ace_cfg.cache_line_size, ace_cfg.cddata_width))
	end
endfunction : check_snoop

`endif
