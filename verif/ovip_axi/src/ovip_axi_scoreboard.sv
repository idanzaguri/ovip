`ifndef OVIP_AXI_SCOREBOARD__SV
`define OVIP_AXI_SCOREBOARD__SV

// Reference scoreboard for ovip_axi traffic. Receives "expected" transactions
// (typically from a predictor or a master-side mirror) and "actual" transactions
// (typically from the slave-side monitor's analysis port) and pairs them off
// per direction and per ID. Expected entries are sorted into per-(tr_type, id)
// FIFOs so AXI's same-ID in-order response rule is respected.
//
// Mismatches raise a UVM_ERROR built from ovip_axi_trans::diff(), so the log
// shows exactly which interface-signal fields disagreed and what each side
// expected / saw. Orphans (expected with no matching actual) and unexpected
// actuals are counted separately and reported at end-of-test.
//
// Typical wiring:
//     predictor.analysis_port.connect(scoreboard.exp_ap);
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


	// Sort an expected transaction into the right per-(tr_type, id) queue.
	// Stores the handle directly by default; set `defensive_copy_expected = 1`
	// to deep-copy first if the producer reuses transaction objects.
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
			OVIP_AXI_WRITE_TRANS: expected_wr[entry.id].push_back(entry);
			OVIP_AXI_READ_TRANS:  expected_rd[entry.id].push_back(entry);
			default: `uvm_error("AXI_SB/UNKNOWN_TYPE",
				$sformatf("ignoring expected trans, unsupported tr_type=%s", entry.tr_type.name()))
		endcase
	endfunction


	// Match an actual against the front of the expected queue for its
	// (tr_type, id). Mismatches and orphans go through uvm_error so the
	// caller's report server gates pass/fail accordingly.
	virtual function void write_act(ovip_axi_trans t);
		ovip_axi_trans exp;

		case(t.tr_type)
			OVIP_AXI_WRITE_TRANS: begin
				if(!expected_wr.exists(t.id) || expected_wr[t.id].size() == 0) begin
					`uvm_error("AXI_SB/UNEXPECTED",
						$sformatf("WR id=%0d arrived with no expected match: %s",
							t.id, t.convert2string()))
					unexpected++;
					return;
				end
				exp = expected_wr[t.id].pop_front();
			end
			OVIP_AXI_READ_TRANS: begin
				if(!expected_rd.exists(t.id) || expected_rd[t.id].size() == 0) begin
					`uvm_error("AXI_SB/UNEXPECTED",
						$sformatf("RD id=%0d arrived with no expected match: %s",
							t.id, t.convert2string()))
					unexpected++;
					return;
				end
				exp = expected_rd[t.id].pop_front();
			end
			default: begin
				`uvm_error("AXI_SB/UNKNOWN_TYPE",
					$sformatf("ignoring actual trans, unsupported tr_type=%s",
						t.tr_type.name()))
				return;
			end
		endcase

		if(exp.compare(t)) begin
			matched++;
		end else begin
			mismatches++;
			`uvm_error("AXI_SB/MISMATCH",
				$sformatf("trans mismatch (%s):\n%s",
					exp.convert2string(), exp.diff(t)))
		end
	endfunction


	// Anything left in the expected queues at check_phase never paired up.
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
	endfunction


	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		`uvm_info("AXI_SB/REPORT",
			$sformatf("matched=%0d mismatches=%0d unexpected=%0d orphans=%0d",
				matched, mismatches, unexpected, orphans), UVM_LOW)
	endfunction

endclass

`endif
