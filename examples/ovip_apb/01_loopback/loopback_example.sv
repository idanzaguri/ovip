// Minimal hello-world for the ovip_apb VIP.
//
// What this shows:
//   - A requester + completer agent instantiated on the same interface
//     (APB is point-to-point, no DUT in the middle).
//   - The memory-backed base slave sequence answering every request from an
//     ovip_mem instance (writes commit, reads return the stored word).
//   - A small requester sequence that writes 4 words and reads each one
//     back; because the master driver samples PRDATA into the item, the
//     sequence self-checks the read data as soon as apb_read returns.
//
// Nothing in this file is required from the in-repo testbench
// (`verif/ovip_apb_testbench/`). Everything that comes from outside is the
// VIP packages and UVM-1.2.

`timescale 1ns/1ps

package apb_loopback_pkg;
    import uvm_pkg::*;
    import ovip_global_pkg::*;
    import ovip_mem_pkg::*;
    import ovip_apb_pkg::*;
    `include "uvm_macros.svh"

    class apb_loopback_seq extends ovip_apb_base_master_sequence;
        `uvm_object_utils(apb_loopback_seq)
        function new(string name = "apb_loopback_seq"); super.new(name); endfunction
        virtual task body();
            ovip_apb_data_t rdata;
            bit slverr;
            for(int ii = 0; ii < 4; ii++)
            begin
                apb_write(ii*4, 32'hBEEF_0000 | ii, , , slverr);
                if(slverr) `uvm_error("LOOPBACK", $sformatf("unexpected SLVERR on write #%0d", ii))
            end
            for(int ii = 0; ii < 4; ii++)
            begin
                apb_read(ii*4, rdata, slverr);
                if(slverr)
                    `uvm_error("LOOPBACK", $sformatf("unexpected SLVERR on read #%0d", ii))
                else if(rdata !== (32'hBEEF_0000 | ii))
                    `uvm_error("LOOPBACK", $sformatf("read-back mismatch at 0x%0h: expected 0x%08h, got 0x%08h",
                        ii*4, 32'hBEEF_0000 | ii, rdata))
                else
                    `uvm_info("LOOPBACK", $sformatf("read-back #%0d ok: [0x%0h] = 0x%08h", ii, ii*4, rdata), UVM_LOW)
            end
        endtask
    endclass

    class apb_loopback_test extends uvm_test;
        `uvm_component_utils(apb_loopback_test)
        ovip_apb_agent_config req_cfg, comp_cfg;
        ovip_apb_agent req_agent, comp_agent;
        ovip_mem mem;

        function new(string name = "apb_loopback_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            req_cfg  = ovip_apb_agent_config::type_id::create("req_cfg");
            comp_cfg = ovip_apb_agent_config::type_id::create("comp_cfg");
            req_cfg.agent_type  = OVIP_APB_REQUESTER;
            req_cfg.is_active   = UVM_ACTIVE;
            req_cfg.addr_width  = 16; req_cfg.data_width = 4;
            comp_cfg.agent_type = OVIP_APB_COMPLETER;
            comp_cfg.is_active  = UVM_ACTIVE;
            comp_cfg.addr_width = 16; comp_cfg.data_width = 4;

            req_agent  = ovip_apb_agent::type_id::create("req_agent",  this); req_agent.cfg  = req_cfg;
            comp_agent = ovip_apb_agent::type_id::create("comp_agent", this); comp_agent.cfg = comp_cfg;
            mem = ovip_mem::type_id::create("mem", this);
        endfunction

        virtual task reset_phase(uvm_phase phase);
            super.reset_phase(phase);
            phase.raise_objection(this);
            @(posedge req_agent.mon.vif.presetn);
            phase.drop_objection(this);
        endtask

        virtual task run_phase(uvm_phase phase);
            ovip_apb_base_slave_sequence slave_seq =
                ovip_apb_base_slave_sequence::type_id::create("slave_seq");
            super.run_phase(phase);
            slave_seq.mem = mem;
            fork slave_seq.start(comp_agent.slave_sqr); join_none
        endtask

        virtual task main_phase(uvm_phase phase);
            apb_loopback_seq seq = apb_loopback_seq::type_id::create("seq");
            super.main_phase(phase);
            phase.raise_objection(this);
            seq.start(req_agent.master_sqr);
            #200ns;
            phase.drop_objection(this);
        endtask
    endclass
endpackage : apb_loopback_pkg


module tb_top;
    import uvm_pkg::*;
    import apb_loopback_pkg::*;

    logic pclk = 0;
    logic presetn = 0;
    always #500ps pclk = ~pclk;

    ovip_apb_agent_if apb_if(pclk, presetn);

    initial begin
        uvm_config_db#(virtual ovip_apb_agent_if)::set(null, "*.req_agent*",  "vif", apb_if);
        uvm_config_db#(virtual ovip_apb_agent_if)::set(null, "*.comp_agent*", "vif", apb_if);
        run_test("apb_loopback_test");
    end

    initial begin
        repeat(2) @(posedge pclk);
        presetn = 1;
    end
endmodule : tb_top
