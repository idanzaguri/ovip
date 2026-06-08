// AXI-Stream receiver -> ovip_mem.
//
// What this shows:
//   - A transmitter sends two multi-beat packets carrying a mix of data,
//     position, and null bytes.
//   - The receiver's monitor publishes the completed packets; a subscriber
//     in the test pulls just the *valid* bytes via ovip_axi_stream_trans::
//     get_data_bytes() (TKEEP / TSTRB filtering applied per the spec) and
//     pushes them into an ovip_mem at a running write address.
//   - After both packets have landed, the test reads the bytes back from
//     ovip_mem via mem.read_bytestream() and verifies they match the data
//     bytes the transmitter intended to deliver.
//
// This is the canonical "rx -> memory" pipeline for any stream protocol:
// the monitor sees every transfer, the trans helper drops null/position
// bytes, and the memory model stores the byte payload at a destination
// address chosen by the consumer.

`timescale 1ns/1ps

package axis_rx_to_mem_pkg;
    import uvm_pkg::*;
    import ovip_global_pkg::*;
    import ovip_mem_pkg::*;
    import ovip_axi_stream_pkg::*;
    `include "uvm_macros.svh"


    // Sequence: build two packets directly so we can illustrate the byte
    // qualifiers. Each beat is 4 bytes; we mark some bytes as null (TKEEP=0)
    // so get_data_bytes() drops them, and mark all the rest as data (TSTRB=1).
    class axis_rx_to_mem_seq extends ovip_axi_stream_base_master_sequence;
        `uvm_object_utils(axis_rx_to_mem_seq)
        ovip_bytestream sent_bytes;

        function new(string name = "axis_rx_to_mem_seq"); super.new(name); endfunction

        virtual task body();
            // Packet 1: 3 beats, all 4 bytes per beat are data.
            begin
                ovip_axi_stream_trans tr = ovip_axi_stream_trans::type_id::create("tr0");
                tr.id = 0; tr.dest = 0;
                tr.data_beats = '{32'h0403_0201, 32'h0807_0605, 32'h0C0B_0A09};
                tr.keep_beats = '{4'b1111, 4'b1111, 4'b1111};
                tr.strb_beats = '{4'b1111, 4'b1111, 4'b1111};
                for(int i = 1; i <= 12; i++) sent_bytes.push_back(i);
                send(tr);
            end

            // Packet 2: 2 beats; in beat 0, byte 1 is a null byte (TKEEP=0).
            // get_data_bytes() must drop that byte from the output.
            begin
                ovip_axi_stream_trans tr = ovip_axi_stream_trans::type_id::create("tr1");
                tr.id = 1; tr.dest = 0;
                tr.data_beats = '{32'hAAAA_BBBB, 32'hCCCC_DDDD};
                //                              null vvvv
                tr.keep_beats = '{4'b1101, 4'b1111};
                tr.strb_beats = '{4'b1101, 4'b1111};
                sent_bytes.push_back(8'hBB); // byte 0 of beat 0 (kept)
                // byte 1 of beat 0 (TKEEP=0, dropped)
                sent_bytes.push_back(8'hAA); // byte 2
                sent_bytes.push_back(8'hAA); // byte 3
                sent_bytes.push_back(8'hDD); // beat 1 byte 0
                sent_bytes.push_back(8'hDD); // beat 1 byte 1
                sent_bytes.push_back(8'hCC); // beat 1 byte 2
                sent_bytes.push_back(8'hCC); // beat 1 byte 3
                send(tr);
            end
        endtask
    endclass


    // Subscriber: for every published packet, extract the valid bytes and
    // append them into ovip_mem at the running write address.
    class axis_rx_to_mem_writer extends uvm_subscriber#(ovip_axi_stream_trans);
        `uvm_component_utils(axis_rx_to_mem_writer)

        ovip_mem mem;
        protected int unsigned write_addr = 0;
        ovip_bytestream received_bytes;

        function new(string name = "axis_rx_to_mem_writer", uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual function void write(ovip_axi_stream_trans t);
            ovip_bytestream bytes = t.get_data_bytes(); // null + position bytes dropped
            `uvm_info("RX2MEM", $sformatf("got id=%0d, %0d data bytes -> mem[%0d..%0d]",
                t.id, bytes.size(), write_addr, write_addr + bytes.size() - 1), UVM_LOW)
            mem.write_bytestream(write_addr, bytes);
            foreach(bytes[i]) received_bytes.push_back(bytes[i]);
            write_addr += bytes.size();
        endfunction
    endclass


    class axis_rx_to_mem_test extends uvm_test;
        `uvm_component_utils(axis_rx_to_mem_test)

        ovip_axi_stream_agent_config tx_cfg, rx_cfg;
        ovip_axi_stream_agent tx_agent, rx_agent;
        ovip_mem mem;
        axis_rx_to_mem_writer writer;

        function new(string name = "axis_rx_to_mem_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            mem    = ovip_mem::type_id::create("mem", this);
            writer = axis_rx_to_mem_writer::type_id::create("writer", this);

            tx_cfg = ovip_axi_stream_agent_config::type_id::create("tx_cfg");
            rx_cfg = ovip_axi_stream_agent_config::type_id::create("rx_cfg");
            tx_cfg.agent_type  = OVIP_AXI_STREAM_TRANSMITTER; tx_cfg.is_active = UVM_ACTIVE;
            tx_cfg.tdata_width = 4; tx_cfg.tlast_en = 1; tx_cfg.tkeep_en = 1; tx_cfg.tstrb_en = 1;
            tx_cfg.tid_en      = 1; tx_cfg.tid_width = 8;
            rx_cfg.agent_type  = OVIP_AXI_STREAM_RECEIVER;    rx_cfg.is_active = UVM_ACTIVE;
            rx_cfg.tdata_width = 4; rx_cfg.tlast_en = 1; rx_cfg.tkeep_en = 1; rx_cfg.tstrb_en = 1;
            rx_cfg.tid_en      = 1; rx_cfg.tid_width = 8;

            tx_agent = ovip_axi_stream_agent::type_id::create("tx_agent", this); tx_agent.cfg = tx_cfg;
            rx_agent = ovip_axi_stream_agent::type_id::create("rx_agent", this); rx_agent.cfg = rx_cfg;
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            writer.mem = mem;
            rx_agent.mon.analysis_port.connect(writer.analysis_export);
        endfunction

        virtual task reset_phase(uvm_phase phase);
            super.reset_phase(phase);
            phase.raise_objection(this);
            @(posedge tx_agent.mon.vif.aresetn);
            phase.drop_objection(this);
        endtask

        virtual task main_phase(uvm_phase phase);
            axis_rx_to_mem_seq seq = axis_rx_to_mem_seq::type_id::create("seq");
            ovip_bytestream readback;
            super.main_phase(phase);
            phase.raise_objection(this);

            seq.start(tx_agent.master_sqr);
            #200ns;

            // Now read the bytes back out of mem and verify against what the
            // sequence intended to deliver (sent_bytes lists the bytes the
            // transmitter marked as data after TKEEP/TSTRB filtering).
            readback = mem.read_bytestream(0, seq.sent_bytes.size());
            if(readback != seq.sent_bytes)
                `uvm_error("RX2MEM", $sformatf("mem readback mismatches the sent data bytes.\n  sent     = %p\n  readback = %p",
                    seq.sent_bytes, readback))
            else
                `uvm_info ("RX2MEM", $sformatf("%0d bytes round-tripped through ovip_mem cleanly", readback.size()), UVM_LOW)

            phase.drop_objection(this);
        endtask
    endclass
endpackage : axis_rx_to_mem_pkg


module tb_top;
    import uvm_pkg::*;
    import axis_rx_to_mem_pkg::*;

    logic aclk = 0;
    logic aresetn = 0;
    always #500ps aclk = ~aclk;

    ovip_axi_stream_agent_if axis_if(aclk, aresetn);

    initial begin
        uvm_config_db#(virtual ovip_axi_stream_agent_if)::set(null, "*.tx_agent*", "vif", axis_if);
        uvm_config_db#(virtual ovip_axi_stream_agent_if)::set(null, "*.rx_agent*", "vif", axis_if);
        run_test("axis_rx_to_mem_test");
    end

    initial begin
        repeat(2) @(posedge aclk);
        aresetn = 1;
    end
endmodule : tb_top
