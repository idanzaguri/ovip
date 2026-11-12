`ifndef OVIP_AXI_SCOREBOARD__SV
`define OVIP_AXI_SCOREBOARD__SV

// Reference scoreboard for ovip_axi traffic. It takes "expected" transactions
// on exp_ap (from a predictor, or from the monitor on one side of a DUT) and
// "actual" transactions on act_ap (from the monitor on the other side) and
// pairs them off per direction and per ID, in the order each side delivers
// them: AXI keeps the transactions of one ID in order.
//
// The two sides may arrive in any order. An item whose partner is not there
// yet waits in a per-(tr_type, id) FIFO and is compared when the partner
// arrives. So it does not matter which monitor publishes a transaction first,
// or how long the DUT takes between its two sides.
//
// A pair that differs raises a UVM_ERROR (AXI_SB/MISMATCH) built from
// ovip_axi_trans::diff(), so the log shows which interface-signal fields
// disagreed and what each side had. What never paired up is reported at
// check_phase: an expected item with no actual one as AXI_SB/ORPHAN, an
// actual item with no expected one as AXI_SB/UNEXPECTED. report_phase prints
// the four counters.
//
// Typical wiring:
//     master_agent.mon.analysis_port.connect(scoreboard.exp_ap);   // or a predictor
//     slave_agent.mon.analysis_port.connect(scoreboard.act_ap);


class ovip_axi_scoreboard extends uvm_component;
	`uvm_analysis_imp_decl(_exp)
	`uvm_analysis_imp_decl(_act)

	`uvm_component_utils(ovip_axi_scoreboard)

	uvm_analysis_imp_exp#(ovip_axi_trans, ovip_axi_scoreboard) exp_ap;
	uvm_analysis_imp_act#(ovip_axi_trans, ovip_axi_scoreboard) act_ap;

	// Per-ID FIFOs of expected transactions, split by direction.
	protected ovip_axi_trans expected_wr[ovip_axi_id_t][$];
	protected ovip_axi_trans expected_rd[ovip_axi_id_t][$];

	// Per-ID FIFOs of actual transactions that arrived before their expected
	// one, split by direction. For one direction and ID only one side waits.
	protected ovip_axi_trans actual_wr[ovip_axi_id_t][$];
	protected ovip_axi_trans actual_rd[ovip_axi_id_t][$];

	// When set, write_exp stores a deep copy of the incoming transaction
	// rather than the handle itself. Default 0 -- assumes a well-behaved
	// predictor that builds a fresh ovip_axi_trans per prediction and never
	// mutates a handle after publishing it. Flip to 1 if the producer reuses
	// transaction objects between writes.
	bit defensive_copy_expected = 0;

	// End-of-test counters.
	int matched    = 0;
	int mismatches = 0;
	int unexpected = 0;
	int orphans    = 0;

	function new(string name = "ovip_axi_scoreboard", uvm_component parent = null);
		super.new(name, parent);
		exp_ap = new("exp_ap", this);
		act_ap = new("act_ap", this);
	endfunction


	// Compare an expected transaction with its actual one. A mismatch goes
	// through uvm_error so the caller's report server gates pass/fail.
	protected virtual function void compare_pair(ovip_axi_trans exp, ovip_axi_trans act);
		if(exp.compare(act)) begin
			matched++;
		end else begin
			mismatches++;
			`uvm_error("AXI_SB/MISMATCH",
				$sformatf("trans mismatch (%s):\n%s",
					exp.convert2string(), exp.diff(act)))
		end
	endfunction


	// Pair an expected transaction with the oldest actual one that waits for
	// its (tr_type, id), or keep it until that one arrives. Stores the handle
	// directly by default; set `defensive_copy_expected = 1` to deep-copy
	// first if the producer reuses transaction objects.
	virtual function void write_exp(ovip_axi_trans t);
		ovip_axi_trans entry;
		if(defensive_copy_expected) begin
			entry = ovip_axi_trans::type_id::create("exp_cp");
			entry.copy(t);
		end
		else begin
			entry = t;
		end
		case(entry.tr_type)
			OVIP_AXI_WRITE_TRANS: begin
				if(actual_wr.exists(entry.id) && actual_wr[entry.id].size())
					compare_pair(entry, actual_wr[entry.id].pop_front());
				else
					expected_wr[entry.id].push_back(entry);
			end
			OVIP_AXI_READ_TRANS: begin
				if(actual_rd.exists(entry.id) && actual_rd[entry.id].size())
					compare_pair(entry, actual_rd[entry.id].pop_front());
				else
					expected_rd[entry.id].push_back(entry);
			end
			default: `uvm_error("AXI_SB/UNKNOWN_TYPE",
				$sformatf("ignoring expected trans, unsupported tr_type=%s", entry.tr_type.name()))
		endcase
	endfunction


	// Pair an actual transaction with the oldest expected one that waits for
	// its (tr_type, id), or keep its handle until that one arrives. An actual
	// that is still waiting at check_phase is reported there.
	virtual function void write_act(ovip_axi_trans t);
		case(t.tr_type)
			OVIP_AXI_WRITE_TRANS: begin
				if(expected_wr.exists(t.id) && expected_wr[t.id].size())
					compare_pair(expected_wr[t.id].pop_front(), t);
				else
					actual_wr[t.id].push_back(t);
			end
			OVIP_AXI_READ_TRANS: begin
				if(expected_rd.exists(t.id) && expected_rd[t.id].size())
					compare_pair(expected_rd[t.id].pop_front(), t);
				else
					actual_rd[t.id].push_back(t);
			end
			default: begin
				`uvm_error("AXI_SB/UNKNOWN_TYPE",
					$sformatf("ignoring actual trans, unsupported tr_type=%s",
						t.tr_type.name()))
			end
		endcase
	endfunction


	// Anything left in the queues at check_phase never paired up: an expected
	// transaction is an orphan, an actual one is unexpected.
	virtual function void check_phase(uvm_phase phase);
		ovip_axi_trans tr;
		super.check_phase(phase);
		foreach(expected_wr[id]) while(expected_wr[id].size()) begin
			tr = expected_wr[id].pop_front();
			`uvm_error("AXI_SB/ORPHAN", $sformatf("expected WR never arrived: %s",
				tr.convert2string()))
			orphans++;
		end
		foreach(expected_rd[id]) while(expected_rd[id].size()) begin
			tr = expected_rd[id].pop_front();
			`uvm_error("AXI_SB/ORPHAN", $sformatf("expected RD never arrived: %s",
				tr.convert2string()))
			orphans++;
		end
		foreach(actual_wr[id]) while(actual_wr[id].size()) begin
			tr = actual_wr[id].pop_front();
			`uvm_error("AXI_SB/UNEXPECTED",
				$sformatf("WR id=%0d arrived with no expected match: %s",
					tr.id, tr.convert2string()))
			unexpected++;
		end
		foreach(actual_rd[id]) while(actual_rd[id].size()) begin
			tr = actual_rd[id].pop_front();
			`uvm_error("AXI_SB/UNEXPECTED",
				$sformatf("RD id=%0d arrived with no expected match: %s",
					tr.id, tr.convert2string()))
			unexpected++;
		end
	endfunction


	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		`uvm_info("AXI_SB/REPORT",
			$sformatf("matched=%0d mismatches=%0d unexpected=%0d orphans=%0d",
				matched, mismatches, unexpected, orphans), UVM_LOW)
	endfunction

endclass

`endif
