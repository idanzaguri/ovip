// Minimal hello-world for the ovip_axi_stream VIP.
//
// What this shows:
//   - A transmitter + receiver agent instantiated on the same interface
//     (AXI-Stream is point-to-point, no DUT in the middle).
//   - A small master sequence that sends 4 single-beat packets.
//   - The receiver's monitor publishes each packet on its analysis port; a
//     subscriber in the test counts them and asserts on the count.
//
// Nothing in this file is required from the in-repo testbench
// (`verif/ovip_axi_stream_testbench/`). Everything that comes from outside
// is the VIP packages and UVM-1.2.

`timescale 1ns/1ps

package axis_loopback_pkg;
    import uvm_pkg::*;
    import ovip_global_pkg::*;
    import ovip_mem_pkg::*;
    import ovip_axi_stream_pkg::*;
    `include "uvm_macros.svh"

    class axis_loopback_seq extends ovip_axi_stream_base_master_sequence;
        `uvm_object_utils(axis_loopback_seq)
        function new(string name = "axis_loopback_seq"); super.new(name); endfunction
        virtual task body();
            for(int ii = 0; ii < 4; ii++)
            begin
                ovip_axi_stream_trans tr = ovip_axi_stream_trans::type_id::create($sformatf("tr_%0d", ii));
                tr.id   = ii;
                tr.dest = 0;
                tr.data_beats = '{32'hDEAD_0000 | ii};
                tr.keep_beats = '{4'hF};
                tr.strb_beats = '{4'hF};
                send(tr);
            end
        endtask
    endclass

    class axis_loopback_counter extends uvm_subscriber#(ovip_axi_stream_trans);
        `uvm_component_utils(axis_loopback_counter)
        int count = 0;
        function new(string name = "axis_loopback_counter", uvm_component parent);
            super.new(name, parent);
        endfunction
        virtual function void write(ovip_axi_stream_trans t);
            count++;
            `uvm_info("LOOPBACK", $sformatf("rx packet #%0d id=%0d data=0x%08h", count, t.id, t.data_beats[0]), UVM_LOW)
        endfunction
        virtual function void report_phase(uvm_phase phase);
            if(count != 4)
                `uvm_error("LOOPBACK", $sformatf("expected 4 packets at the receiver, got %0d", count))
        endfunction
    endclass

    class axis_loopback_test extends uvm_test;
        `uvm_component_utils(axis_loopback_test)
        ovip_axi_stream_agent_config tx_cfg, rx_cfg;
        ovip_axi_stream_agent tx_agent, rx_agent;
        axis_loopback_counter rx_count;

        function new(string name = "axis_loopback_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            tx_cfg = ovip_axi_stream_agent_config::type_id::create("tx_cfg");
            rx_cfg = ovip_axi_stream_agent_config::type_id::create("rx_cfg");
            tx_cfg.agent_type  = OVIP_AXI_STREAM_TRANSMITTER;
            tx_cfg.is_active   = UVM_ACTIVE;
            tx_cfg.tdata_width = 4; tx_cfg.tlast_en = 1; tx_cfg.tkeep_en = 1; tx_cfg.tstrb_en = 1;
            tx_cfg.tid_en      = 1; tx_cfg.tid_width = 8;
            rx_cfg.agent_type  = OVIP_AXI_STREAM_RECEIVER;
            rx_cfg.is_active   = UVM_ACTIVE;
            rx_cfg.tdata_width = 4; rx_cfg.tlast_en = 1; rx_cfg.tkeep_en = 1; rx_cfg.tstrb_en = 1;
            rx_cfg.tid_en      = 1; rx_cfg.tid_width = 8;

            tx_agent = ovip_axi_stream_agent::type_id::create("tx_agent", this); tx_agent.cfg = tx_cfg;
            rx_agent = ovip_axi_stream_agent::type_id::create("rx_agent", this); rx_agent.cfg = rx_cfg;
            rx_count = axis_loopback_counter::type_id::create("rx_count", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            rx_agent.mon.analysis_port.connect(rx_count.analysis_export);
        endfunction

        virtual task reset_phase(uvm_phase phase);
            super.reset_phase(phase);
            phase.raise_objection(this);
            @(posedge tx_agent.mon.vif.aresetn);
            phase.drop_objection(this);
        endtask

        virtual task main_phase(uvm_phase phase);
            axis_loopback_seq seq = axis_loopback_seq::type_id::create("seq");
            super.main_phase(phase);
            phase.raise_objection(this);
            seq.start(tx_agent.master_sqr);
            #200ns;
            phase.drop_objection(this);
        endtask
    endclass
endpackage : axis_loopback_pkg


module tb_top;
    import uvm_pkg::*;
    import axis_loopback_pkg::*;

    logic aclk = 0;
    logic aresetn = 0;
    always #500ps aclk = ~aclk;

    ovip_axi_stream_agent_if axis_if(aclk, aresetn);

    initial begin
        uvm_config_db#(virtual ovip_axi_stream_agent_if)::set(null, "*.tx_agent*", "vif", axis_if);
        uvm_config_db#(virtual ovip_axi_stream_agent_if)::set(null, "*.rx_agent*", "vif", axis_if);
        run_test("axis_loopback_test");
    end

    initial begin
        repeat(2) @(posedge aclk);
        aresetn = 1;
    end
endmodule : tb_top
