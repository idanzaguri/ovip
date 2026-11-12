`ifndef OVIP_ACE_TRANS__SV
`define OVIP_ACE_TRANS__SV

// ovip_ace_trans -- adds the ACE additions to the AXI base. One trans carries
// either a master-initiated transaction (direction = INITIATING -- AR/AW
// originated, response on R/B + RACK/WACK) or an interconnect-initiated snoop
// (direction = SNOOP -- AC originated, master answers on CR + optionally CD).
//
// The constraints below keep the AR/AW fields of a randomized item inside the
// AxSNOOP / AxDOMAIN combinations of Tables D3-7 and D3-8 and the AWUNIQUE
// rules of Table D3-9, with AxBAR at 00 (no barriers). The item does not know
// the agent's config, so the caller constrains what depends on it: the cache
// line rules of Table D3-10 (address, AxLEN, AxSIZE, AxBURST) and the ACE-Lite
// subset of Tables D11-1 and D11-2. No driver checks an item before it goes
// on the wire: ovip_ace_monitor reports what it sees there.

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
	// The expected cache line state before and after the transaction, for a
	// monitor cross-check against the legal state tables. No effect in this
	// version: there is no cache model, and the VIP only copies these three
	// fields in do_copy.
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

	// A randomized item is a master-initiated transaction unless the caller
	// asks for a snoop with "direction == OVIP_ACE_SNOOP".
	constraint c_direction_default {
		soft direction == OVIP_ACE_INITIATING;
	}

	// The constraints below are on the AR/AW fields. They hold whatever the
	// direction is, so a with block that asks for a combination outside the
	// tables makes randomize() fail. A snoop item does not use these fields.

	// Snoop encoding sanity. Reads use ARSNOOP[3:0], writes use AWSNOOP[2:0]
	// (MSB must be 0). c_snoop_legal keeps the value to the encodings of
	// Tables D3-7 and D3-8.
	constraint c_snoop_msb {
		(tr_type == OVIP_AXI_WRITE_TRANS) ->
			(snoop[3] == 1'b0);
	}

	// The ARSNOOP encodings of Table D3-7 for a read and the AWSNOOP
	// encodings of Table D3-8 for a write. Every other value is Reserved.
	constraint c_snoop_legal {
		(tr_type == OVIP_AXI_READ_TRANS) ->
			(snoop inside {4'b0000, 4'b0001, 4'b0010, 4'b0011, 4'b0111, 4'b1000,
			               4'b1001, 4'b1011, 4'b1100, 4'b1101, 4'b1110, 4'b1111});
		(tr_type == OVIP_AXI_WRITE_TRANS) ->
			(snoop[2:0] inside {3'b000, 3'b001, 3'b010, 3'b011, 3'b100, 3'b101});
	}

	// BAR field: barriers are deprecated and not supported in v0.1.
	constraint c_no_barriers {
		bar == OVIP_ACE_BAR_NORMAL_RESPECT;
	}

	// AxDOMAIN per transaction type (Tables D3-7 and D3-8). AxSNOOP all zeros
	// is legal in every domain: ReadNoSnoop / WriteNoSnoop when Non-shareable
	// or System, ReadOnce / WriteUnique when Inner or Outer Shareable.
	constraint c_domain_consistent_with_snoop {
		// ReadShared, ReadClean, ReadNotSharedDirty, ReadUnique, CleanUnique,
		// MakeUnique and the DVM transactions: Inner or Outer Shareable.
		(tr_type == OVIP_AXI_READ_TRANS &&
		 (snoop inside {4'b0001, 4'b0010, 4'b0011, 4'b0111, 4'b1011, 4'b1100, 4'b1110, 4'b1111})) ->
			(domain inside {OVIP_ACE_DOMAIN_INNER_SHAREABLE, OVIP_ACE_DOMAIN_OUTER_SHAREABLE});
		// CleanShared, CleanInvalid and MakeInvalid: any domain but System.
		(tr_type == OVIP_AXI_READ_TRANS &&
		 (snoop inside {4'b1000, 4'b1001, 4'b1101})) ->
			(domain != OVIP_ACE_DOMAIN_SYSTEM);
		// WriteLineUnique and Evict: Inner or Outer Shareable.
		(tr_type == OVIP_AXI_WRITE_TRANS &&
		 (snoop[2:0] inside {3'b001, 3'b100})) ->
			(domain inside {OVIP_ACE_DOMAIN_INNER_SHAREABLE, OVIP_ACE_DOMAIN_OUTER_SHAREABLE});
		// WriteClean, WriteBack and WriteEvict: any domain but System.
		(tr_type == OVIP_AXI_WRITE_TRANS &&
		 (snoop[2:0] inside {3'b010, 3'b011, 3'b101})) ->
			(domain != OVIP_ACE_DOMAIN_SYSTEM);
	}

	// AWUNIQUE per Table D3-9: WriteEvict (AWSNOOP=0b101) must assert it and
	// WriteClean (AWSNOOP=0b010) must deassert it. Every other write may
	// assert it: it is LOW unless the caller constrains it to 1.
	constraint c_awunique_default {
		(tr_type == OVIP_AXI_WRITE_TRANS && snoop[2:0] == 3'b101) ->
			(awunique == 1'b1);
		(tr_type == OVIP_AXI_WRITE_TRANS && snoop[2:0] == 3'b010) ->
			(awunique == 1'b0);
		soft awunique == (tr_type == OVIP_AXI_WRITE_TRANS && snoop[2:0] == 3'b101);
	}


	// -- Helpers ------------------------------------------------------------

	// Pretty name for prints. Decodes {tr_type, snoop, domain} into a spec
	// transaction name (e.g. "ReadShared", "WriteBack", "CleanInvalid").
	virtual function string transaction_name();
		if(direction == OVIP_ACE_SNOOP)
		begin
			ovip_ace_acsnoop_t ac;
			if(!$cast(ac, acsnoop_code)) return $sformatf("Snoop:Reserved(%4b)", acsnoop_code);
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

	// A snoop prints its AC, CR and CD fields. It has no AXI part.
	virtual function string convert2string();
		string s;
		if(direction == OVIP_ACE_SNOOP)
			return $sformatf("(%s) ACE %s, DIR=%s, ACADDR=0x%0x, ACPROT=0b%3b, CRRESP={WU=%0b,IS=%0b,PD=%0b,Err=%0b,DT=%0b}, CD_BEATS=%0d",
				get_name(),
				transaction_name(),
				direction.name(),
				snoop_addr,
				acprot,
				snoop_resp.was_unique,
				snoop_resp.is_shared,
				snoop_resp.pass_dirty,
				snoop_resp.error,
				snoop_resp.data_transfer,
				snoop_data_beats.size());
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
		return s;
	endfunction : convert2string


	// Append the ACE coherency columns to the base per-transaction log line.
	// A snoop fills the columns of the base line that it has (dir "SN", the
	// snoop address, the number of CD beats) and leaves the others at "-".
	virtual function string log_line();
		string s;
		if(direction == OVIP_ACE_SNOOP)
			return $sformatf("%-3s %-6s %-12s %-6d %-5s %-6s %-7s %-11s %-11s %-11s %-11s | SNOOP %s prot=%3b CRRESP={IS=%0b,PD=%0b,DT=%0b}",
				"SN", "-", $sformatf("0x%08x", snoop_addr), snoop_data_beats.size(),
				"-", "-", "-", "-", "-", "-", "-",
				transaction_name(), acprot, snoop_resp.is_shared, snoop_resp.pass_dirty, snoop_resp.data_transfer);
		s = super.log_line();
		s = $sformatf("%s | %s dom=%s", s, transaction_name(), domain.name());
		if(tr_type == OVIP_AXI_READ_TRANS)
			s = $sformatf("%s IS=%0b PD=%0b", s, is_shared, pass_dirty);
		return s;
	endfunction : log_line

	virtual function string log_header();
		return {super.log_header(), " | ACE: name dom [IS PD]"};
	endfunction : log_header


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


	// Compare two ovip_ace_trans, by the fields that map to interface signals
	// (the policy of ovip_axi_trans::do_compare). The two must have the same
	// direction. A snoop compares its AC, CR and CD fields and none of the AXI
	// fields, which it does not use. A master-initiated transaction compares
	// the AXI fields and the ACE fields of its channels: AxDOMAIN, AxSNOOP and
	// AxBAR, AWUNIQUE on a write, IsShared and PassDirty (RRESP[3:2]) on a
	// read.
	virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
		ovip_ace_trans that;
		if(!$cast(that, rhs)) return 0;
		if(direction != that.direction) return 0;
		if(direction == OVIP_ACE_SNOOP)
			return snoop_addr       == that.snoop_addr
				&& acsnoop_code     == that.acsnoop_code
				&& acprot           == that.acprot
				&& snoop_resp       == that.snoop_resp
				&& snoop_data_beats == that.snoop_data_beats;
		if(!super.do_compare(rhs, comparer)) return 0;
		if(domain != that.domain || bar != that.bar) return 0;
		if(tr_type == OVIP_AXI_WRITE_TRANS)
			return snoop[2:0] == that.snoop[2:0]
				&& awunique   == that.awunique;
		return snoop      == that.snoop
			&& is_shared  == that.is_shared
			&& pass_dirty == that.pass_dirty;
	endfunction : do_compare


	// Per-field diff of the mismatches that do_compare sees, in the format of
	// ovip_axi_trans::diff: `this` is read as "expected", `rhs` as "actual".
	virtual function string diff(ovip_axi_trans rhs);
		ovip_ace_trans that;
		string s = "";
		if(!$cast(that, rhs))
			return "  type:       expected=ovip_ace_trans    actual is not an ovip_ace_trans\n";
		if(direction != that.direction)
			return $sformatf("  direction:  expected=%s       actual=%s\n", direction.name(), that.direction.name());
		if(direction == OVIP_ACE_SNOOP)
		begin
			if(snoop_addr       != that.snoop_addr      ) s = {s, $sformatf("  snoop_addr:       expected=0x%0h    actual=0x%0h\n", snoop_addr,       that.snoop_addr)};
			if(acsnoop_code     != that.acsnoop_code    ) s = {s, $sformatf("  acsnoop_code:     expected=0b%4b    actual=0b%4b\n", acsnoop_code,     that.acsnoop_code)};
			if(acprot           != that.acprot          ) s = {s, $sformatf("  acprot:           expected=0b%3b     actual=0b%3b\n", acprot,           that.acprot)};
			if(snoop_resp       != that.snoop_resp      ) s = {s, $sformatf("  snoop_resp:       expected=0b%5b   actual=0b%5b\n", snoop_resp,       that.snoop_resp)};
			if(snoop_data_beats != that.snoop_data_beats) s = {s, $sformatf("  snoop_data_beats: expected=%p       actual=%p\n",  snoop_data_beats, that.snoop_data_beats)};
			return s;
		end
		s = super.diff(rhs);
		if(domain != that.domain) s = {s, $sformatf("  domain:     expected=%s       actual=%s\n", domain.name(), that.domain.name())};
		if(bar    != that.bar   ) s = {s, $sformatf("  bar:        expected=%s       actual=%s\n", bar.name(),    that.bar.name())};
		if(tr_type == OVIP_AXI_WRITE_TRANS)
		begin
			if(snoop[2:0] != that.snoop[2:0]) s = {s, $sformatf("  snoop:      expected=0b%3b    actual=0b%3b\n", snoop[2:0], that.snoop[2:0])};
			if(awunique   != that.awunique  ) s = {s, $sformatf("  awunique:   expected=%0b      actual=%0b\n",   awunique,   that.awunique)};
		end
		else
		begin
			if(snoop      != that.snoop     ) s = {s, $sformatf("  snoop:      expected=0b%4b    actual=0b%4b\n", snoop,      that.snoop)};
			if(is_shared  != that.is_shared ) s = {s, $sformatf("  is_shared:  expected=%0b      actual=%0b\n",   is_shared,  that.is_shared)};
			if(pass_dirty != that.pass_dirty) s = {s, $sformatf("  pass_dirty: expected=%0b      actual=%0b\n",   pass_dirty, that.pass_dirty)};
		end
		return s;
	endfunction : diff

endclass : ovip_ace_trans

`endif
