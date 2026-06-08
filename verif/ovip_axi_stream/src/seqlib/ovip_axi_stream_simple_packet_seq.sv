`ifndef OVIP_AXI_STREAM_SIMPLE_PACKET_SEQ__SV
`define OVIP_AXI_STREAM_SIMPLE_PACKET_SEQ__SV

// Builds and sends N packets with configurable length, TID, TDEST, and a
// caller-supplied data pattern. Each packet is single-TLAST (only the last
// beat asserts TLAST), TKEEP/TSTRB are all-ones across all live byte lanes,
// and TUSER is zero. Use this for generic round-trip / back-pressure /
// scoreboard-pairing tests where the per-packet content doesn't matter.
class ovip_axi_stream_simple_packet_seq extends ovip_axi_stream_base_master_sequence;
	`uvm_object_utils(ovip_axi_stream_simple_packet_seq)

	// Number of packets to send.
	rand int num_packets = 1;

	// Per-packet beat count. The base value is replicated across all packets;
	// override by populating `lens[]` with one entry per packet.
	rand int beats_per_packet = 1;
	rand int lens[$];

	// Per-packet TID / TDEST values; if shorter than num_packets, the last
	// element is reused for the remaining packets. Default leaves them at 0.
	rand ovip_axi_stream_id_t   ids[$];
	rand ovip_axi_stream_dest_t dests[$];

	// Bytes-per-lane configuration is taken from the sequencer's tx agent;
	// the bus width is inferred at runtime from the agent config via the
	// driver. Set tdata_width if the seq is started on a sequencer that
	// hasn't already published cfg.
	int tdata_width = 4;

	// Optional scoreboard snapshot hook: when non-null, each packet's
	// expected snapshot (a deep copy after build, before send) is pushed
	// into `sb_ref.exp_ap` so a test can pair expected/actual
	// deterministically without a separate predictor component.
	ovip_axi_stream_scoreboard sb_ref;

	function new(string name = "ovip_axi_stream_simple_packet_seq");
		super.new(name);
	endfunction

	virtual task body();
		for(int pp = 0; pp < num_packets; pp++)
		begin
			ovip_axi_stream_trans tr  = ovip_axi_stream_trans::type_id::create($sformatf("tr_%0d", pp));
			int                   len = (pp < lens.size())  ? lens[pp]  : beats_per_packet;
			tr.id   = (pp < ids.size())   ? ids[pp]   : 0;
			tr.dest = (pp < dests.size()) ? dests[pp] : 0;

			for(int bb = 0; bb < len; bb++)
			begin
				ovip_axi_stream_data_t data = 0;
				ovip_axi_stream_keep_t keep = (ovip_axi_stream_keep_t'(1) << tdata_width) - 1;
				ovip_axi_stream_strb_t strb = (ovip_axi_stream_strb_t'(1) << tdata_width) - 1;
				// Distinct payload per (packet, beat) so a scoreboard mismatch
				// at the wire level is immediately recognizable.
				data = 32'hA5A5_0000 | (pp << 8) | bb;
				tr.data_beats.push_back(data);
				tr.keep_beats.push_back(keep);
				tr.strb_beats.push_back(strb);
			end

			if(sb_ref != null)
			begin
				ovip_axi_stream_trans exp = ovip_axi_stream_trans::type_id::create($sformatf("exp_%0d", pp));
				exp.copy(tr);
				sb_ref.exp_ap.write(exp);
			end
			send(tr);
		end
	endtask
endclass

`endif
