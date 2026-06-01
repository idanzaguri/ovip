`ifndef OVIP_AXI_OUT_OF_ORDER_QUEUE__SV
`define OVIP_AXI_OUT_OF_ORDER_QUEUE__SV

class ovip_axi_out_of_order_queue extends uvm_object;

	int reorder_depth;
	int interleaving_depth;
	bit q_type_is_wr_data;
	ovip_axi_scheduling_algorithm_t scheduling_alg;

	typedef struct {
		ovip_axi_trans tr;
		int delays[$];
		bit in_flight;
	} tr_context_t;

	tr_context_t tr_q[$];
	int interleaved_ids[*];
	int sch_rr_idx;

	mailbox #(ovip_axi_trans) tr_fifo;

	`uvm_object_utils(ovip_axi_out_of_order_queue)

	function new(string name="ovip_axi_out_of_order_queue");
		super.new(name);
		reorder_depth = 1;
		interleaving_depth = 1;
		q_type_is_wr_data = 0;
		sch_rr_idx = -1;
		scheduling_alg = OVIP_AXI_SCH_ALG_RANDOM;
		tr_fifo = new(); // unbounded
	endfunction : new

	virtual function void reset();
		sch_rr_idx = -1;
		tr_q.delete();
		interleaved_ids.delete();
		tr_fifo = new(); // drop any queued items
	endfunction : reset

	virtual task wait_until_not_empty();
		wait (tr_q.size());
	endtask : wait_until_not_empty

	virtual function bit is_empty();
		return (tr_q.size() == 0);
	endfunction : is_empty

	virtual task pop(ref ovip_axi_trans tr);
		tr_fifo.get(tr);
	endtask : pop

	function void push(ovip_axi_trans tr, int delay_q[$], int len=0);
		tr_context_t tr_context;
		tr_context.tr = tr;
		tr_context.in_flight = 0;
		tr_context.delays = delay_q;

		// Adjust the size of the delays array to match the specified length
		if(tr_context.delays.size() > len)
			tr_context.delays = tr_context.delays[0:len];
		else
			while(tr_context.delays.size() <= len) tr_context.delays.push_back(0);

		// Add an extra cycle to each delay because the delay between beats is
		// measured from the readiness of the previous beat, not from the sample point.
		for (int ii = 1; ii < tr_context.delays.size(); ii++) ++tr_context.delays[ii];

		tr_q.push_back(tr_context);
	endfunction : push


	function void tick_delays();
		foreach(tr_q[ii])
		begin
			if(
				q_type_is_wr_data
				&&
				tr_q[ii].tr.data_start_event == OVIP_AXI_DATA_START_EV_ADDR_SAMPLED
				&&
				!tr_q[ii].tr.valid_address_phase
			)
				continue;

			if(tr_q[ii].delays.size() && tr_q[ii].delays[0])
				--tr_q[ii].delays[0];
		end
	endfunction


	// Returns a position (0..N) within the per-cycle ready set. NOTE: the round-robin
	// modes rotate over ready-set positions, not over a stable per-ID identity, so they
	// spread selection but are not a strict per-ID fairness guarantee (see README
	// "Out-of-Order, Interleaving & Scheduling"). The exact rotation order here is a
	// golden reference for ovip_axi_rd_interleaving_test / ovip_axi3_wr_interleaving_test
	// (their expected_errors encode it) -- changing it will require regenerating those.
	virtual function int pick_index(int N);
		case (scheduling_alg)
			OVIP_AXI_SCH_ALG_RANDOM:
			begin
				return $urandom_range(N,0);
			end
			OVIP_AXI_SCH_ALG_ROUND_ROBIN:
			begin
				if(sch_rr_idx < 0 || sch_rr_idx > N) sch_rr_idx = 0;
				return sch_rr_idx++;
			end
			OVIP_AXI_SCH_ALG_ROUND_ROBIN_REVERSED:
			begin
				if(sch_rr_idx < 0 || sch_rr_idx > N) sch_rr_idx = N;
				return sch_rr_idx--;
			end
			OVIP_AXI_SCH_ALG_ALWAYS_LAST:
			begin
				return N;
			end
			OVIP_AXI_SCH_ALG_ALWAYS_FIRST:
				return 0;
			default:
				return 0;
		endcase
	endfunction : pick_index

	function void schedule_next();
		bit pending_ids[*]; // Array to hold all pending IDs, needed to enforce ordering for the same ID
		int ready_indices[$]; // Array to hold all indices in tr_q that are ready for driving

		// Stage I: Identify all transactions that are ready for driving
		for (int ii = 0; ii < tr_q.size() && ii < reorder_depth; ii++)
		begin
			int id = tr_q[ii].tr.id;
			if (tr_q[ii].delays.size() == 0) continue; // Skip transactions that are already finished (i.e., have no remaining delays)
			if (
				tr_q[ii].delays[0] == 0 // Next data beat can be driven
				&&
				!pending_ids.exists(id) // No pending transactions with the same ID
				&&
				(
					tr_q[ii].in_flight
					||
					(!tr_q[ii].in_flight && interleaved_ids.num() < interleaving_depth) // Ensure interleaving depth is respected
				)
			) begin
				ready_indices.push_back(ii); // Mark this transaction as ready for driving
			end
			pending_ids[id] = 1; // Record this ID to enforce ordering among transactions with the same ID
		end

		if (ready_indices.size() == 0) return; // Exit if there are no transactions ready for driving

		// Stage II: Select a transaction to drive from the ready transactions
		begin
			ovip_axi_trans tr;
			int idx;

			// Select an index of a ready transaction from the ready indices
			idx = ready_indices[pick_index(ready_indices.size()-1)];

			tr_q[idx].in_flight = 1; // Mark the transaction as in-flight
			tr = tr_q[idx].tr;
			interleaved_ids[tr.id] = 1; // Record the transaction ID for interleaving

			tr_q[idx].delays.delete(0); // Remove the first delay entry for the selected transaction

			// Remove the transaction ID from interleaved_ids if there are no more delays(i.e, transaction finished)
			if (tr_q[idx].delays.size() == 0)
				interleaved_ids.delete(tr.id);

			// Remove finished transactions from the beginning of the queue to maintain reorder depth
			while (tr_q.size() && tr_q[0].delays.size() == 0)
				tr_q.delete(0);

			// Add the selected transaction to the ready transaction fifo
			void'(tr_fifo.try_put(tr)); // unbounded -> always succeeds
		end

	endfunction : schedule_next
endclass

`endif
