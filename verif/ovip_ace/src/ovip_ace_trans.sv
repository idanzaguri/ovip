`ifndef OVIP_ACE_TRANS__SV
`define OVIP_ACE_TRANS__SV

// ovip_ace_trans -- adds the ACE additions to the AXI base. One trans carries
// either a master-initiated transaction (direction = INITIATING -- AR/AW
// originated, response on R/B + RACK/WACK) or an interconnect-initiated snoop
// (direction = SNOOP -- AC originated, master answers on CR + optionally CD).
//
// The intra-class constraints below restrict {tr_type, domain, snoop, bar} to
// the rough legal envelope from Table D3-7 / D3-8 / G4-1. Fine-grained
// per-transaction constraints (cache-line-size constraints from Table D3-10,
// AWUNIQUE rules from Table D3-9, ACE-Lite restrictions from Tables D11-1/2)
// are enforced at runtime in the master driver's check_trans_validity hook so
// the constraint solver isn't asked to find the whole intersection.

class ovip_ace_trans extends ovip_axi_trans;

	// -- Common to both INITIATING and SNOOP --------------------------------
	rand ovip_ace_direction_t direction;

	// -- Master-initiated transaction (direction == INITIATING) -------------
	// AR/AW additions.
	rand ovip_ace_domain_t domain;
	rand bit [3:0]         snoop;    // ARSNOOP[3:0] for reads; AWSNOOP[2:0] for writes (MSB == 0)
	rand ovip_ace_bar_t    bar;
	rand bit               awunique;

	// R-channel extension (RRESP[3:2]): set by the slave/interconnect on the
	// response and populated by the master driver's sample_rd_response.
	rand bit               is_shared;
	rand bit               pass_dirty;

	// -- Interconnect-initiated snoop (direction == SNOOP) ------------------
	rand ovip_ace_acaddr_t snoop_addr;
	rand bit [3:0]         acsnoop_code;
	rand bit [2:0]         acprot;
	rand ovip_ace_crresp_t snoop_resp;
	rand ovip_ace_cddata_t snoop_data_beats[$];

	// -- Optional cache-state hint (D4 + D5 cross-check) --------------------
	// When the test populates these and cfg.cache_model == TRACK, the monitor
	// cross-checks observed state transitions against the legal tables. Both
	// are ignored when state_hint_valid is 0.
	ovip_ace_cache_state_t expected_start_state;
	ovip_ace_cache_state_t expected_end_state;
	bit                    state_hint_valid;


	`uvm_object_utils(ovip_ace_trans)

	function new(string name = "ovip_ace_trans");
		super.new(name);
		direction        = OVIP_ACE_INITIATING;
		domain           = OVIP_ACE_DOMAIN_NON_SHAREABLE;
		bar              = OVIP_ACE_BAR_NORMAL_RESPECT;
		snoop            = 4'b0000;
		awunique         = 1'b0;
		is_shared        = 1'b0;
		pass_dirty       = 1'b0;
		snoop_addr       = '0;
		acsnoop_code     = 4'b0000;
		acprot           = 3'b000;
		snoop_resp       = '0;
		state_hint_valid = 1'b0;
	endfunction : new


	// -- Constraints --------------------------------------------------------

	// Master-direction snoop encoding sanity. Reads use ARSNOOP[3:0], writes
	// use AWSNOOP[2:0] (MSB must be 0). Full Table D3-7 / D3-8 legality is
	// enforced by the driver's check_trans_validity at runtime.
	constraint c_snoop_msb {
		(direction == OVIP_ACE_INITIATING) ->
			((tr_type == OVIP_AXI_WRITE_TRANS) -> (snoop[3] == 1'b0));
	}

	// BAR field: barriers are deprecated and not supported in v0.1.
	constraint c_no_barriers {
		(direction == OVIP_ACE_INITIATING) -> (bar == OVIP_ACE_BAR_NORMAL_RESPECT);
	}

	// Non-snooping transactions (ReadNoSnoop / WriteNoSnoop) must use
	// AxDOMAIN in {Non-shareable, System}; coherent transactions must use
	// AxDOMAIN in {Inner Shareable, Outer Shareable}.
	constraint c_domain_consistent_with_snoop {
		(direction == OVIP_ACE_INITIATING && tr_type == OVIP_AXI_READ_TRANS && snoop == 4'b0000 && domain != OVIP_ACE_DOMAIN_NON_SHAREABLE) ->
			(domain == OVIP_ACE_DOMAIN_SYSTEM || domain == OVIP_ACE_DOMAIN_INNER_SHAREABLE || domain == OVIP_ACE_DOMAIN_OUTER_SHAREABLE);
		(direction == OVIP_ACE_INITIATING && tr_type == OVIP_AXI_WRITE_TRANS && snoop[2:0] == 3'b000 && domain != OVIP_ACE_DOMAIN_NON_SHAREABLE) ->
			(domain == OVIP_ACE_DOMAIN_SYSTEM || domain == OVIP_ACE_DOMAIN_INNER_SHAREABLE || domain == OVIP_ACE_DOMAIN_OUTER_SHAREABLE);
	}

	// AWUNIQUE meaningful only with WriteEvict (AWSNOOP=0b101). For other
	// write transactions Table D3-9 dictates per-trans rules; here we just
	// keep AWUNIQUE LOW by default. The driver may override for WriteEvict.
	constraint c_awunique_default {
		(direction == OVIP_ACE_INITIATING && tr_type == OVIP_AXI_WRITE_TRANS && snoop[2:0] != 3'b101) ->
			(awunique == 1'b0);
	}


	// -- Helpers ------------------------------------------------------------

	// Pretty name for prints. Decodes {tr_type, snoop, domain} into a spec
	// transaction name (e.g. "ReadShared", "WriteBack", "CleanInvalid").
	virtual function string transaction_name();
		if(direction == OVIP_ACE_SNOOP)
		begin
			ovip_ace_acsnoop_t ac;
			ac = ovip_ace_acsnoop_t'(acsnoop_code);
			return $sformatf("Snoop:%s", ac.name());
		end
		if(tr_type == OVIP_AXI_READ_TRANS)
		begin
			case(snoop)
				4'b0000: return (domain == OVIP_ACE_DOMAIN_NON_SHAREABLE || domain == OVIP_ACE_DOMAIN_SYSTEM)? "ReadNoSnoop" : "ReadOnce";
				4'b0001: return "ReadShared";
				4'b0010: return "ReadClean";
				4'b0011: return "ReadNotSharedDirty";
				4'b0111: return "ReadUnique";
				4'b1000: return "CleanShared";
				4'b1001: return "CleanInvalid";
				4'b1011: return "CleanUnique";
				4'b1100: return "MakeUnique";
				4'b1101: return "MakeInvalid";
				4'b1110: return "DVMComplete";
				4'b1111: return "DVMMessage";
				default: return $sformatf("ReservedRD(%4b)", snoop);
			endcase
		end
		else
		begin
			case(snoop[2:0])
				3'b000: return (domain == OVIP_ACE_DOMAIN_NON_SHAREABLE || domain == OVIP_ACE_DOMAIN_SYSTEM)? "WriteNoSnoop" : "WriteUnique";
				3'b001: return "WriteLineUnique";
				3'b010: return "WriteClean";
				3'b011: return "WriteBack";
				3'b100: return "Evict";
				3'b101: return "WriteEvict";
				default: return $sformatf("ReservedWR(%3b)", snoop[2:0]);
			endcase
		end
	endfunction : transaction_name

	virtual function string convert2string();
		string s;
		s = super.convert2string();
		s = $sformatf("%s | ACE %s, DIR=%s, DOMAIN=%s, BAR=%s",
			s,
			transaction_name(),
			direction.name(),
			domain.name(),
			bar.name());
		if(direction == OVIP_ACE_INITIATING && tr_type == OVIP_AXI_READ_TRANS)
			s = $sformatf("%s, IS=%0b, PD=%0b", s, is_shared, pass_dirty);
		if(direction == OVIP_ACE_INITIATING && tr_type == OVIP_AXI_WRITE_TRANS && awunique)
			s = $sformatf("%s, AWUNIQUE", s);
		if(direction == OVIP_ACE_SNOOP)
			s = $sformatf("%s, CRRESP={WU=%0b,IS=%0b,PD=%0b,Err=%0b,DT=%0b}",
				s,
				snoop_resp.was_unique,
				snoop_resp.is_shared,
				snoop_resp.pass_dirty,
				snoop_resp.error,
				snoop_resp.data_transfer);
		return s;
	endfunction : convert2string


	// Carry the ACE additions across copy(). Needed because the agent installs a
	// factory override (ovip_axi_trans -> ovip_ace_trans): the monitor's
	// slave-response path and the scoreboard copy transactions through an
	// ovip_axi_trans handle, so without this the ACE fields would be dropped.
	virtual function void do_copy(uvm_object rhs);
		ovip_ace_trans that;
		super.do_copy(rhs);
		if(!$cast(that, rhs)) return;
		direction            = that.direction;
		domain               = that.domain;
		snoop                = that.snoop;
		bar                  = that.bar;
		awunique             = that.awunique;
		is_shared            = that.is_shared;
		pass_dirty           = that.pass_dirty;
		snoop_addr           = that.snoop_addr;
		acsnoop_code         = that.acsnoop_code;
		acprot               = that.acprot;
		snoop_resp           = that.snoop_resp;
		snoop_data_beats     = that.snoop_data_beats;
		expected_start_state = that.expected_start_state;
		expected_end_state   = that.expected_end_state;
		state_hint_valid     = that.state_hint_valid;
	endfunction : do_copy

endclass : ovip_ace_trans

`endif
