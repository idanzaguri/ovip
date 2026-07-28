# OVIP APB

UVM verification IP for the AMBA APB protocol -- **APB3** and **APB4**
(ARM IHI 0024E). One requester agent and one completer agent on a single
point-to-point interface; the monitor performs X/Z and signal-stability checks
plus the APB-specific protocol checks (SETUP-is-one-cycle, PENABLE FSM rules,
request stability under wait states, PSTRB-low-on-reads). Apache-2.0 licensed;
same simulator portability story as the rest of the OVIP family.

The APB5 additions (PWAKEUP, user signaling, interface parity, PNSE/RME) are
intentionally out of scope -- see [CONTRIBUTING.md](CONTRIBUTING.md) if you
want to add them.

### At a glance

| Area | Status |
|---|---|
| Protocols | APB3, APB4 |
| Optional signals | PSLVERR (APB3+), PSTRB + PPROT (APB4) |
| PADDR width | 1 - 32 bits (`cfg.addr_width`) |
| Data width | 8 / 16 / 32 bits (`cfg.data_width` in bytes: 1, 2, 4) |
| Wait states | Completer-driven via `num_wait_states` on the response item |
| Back-to-back | Direct completion-to-SETUP transitions (no IDLE cycle) when the sequence keeps items ready |
| Error response | PSLVERR injection via slave-sequence hook; sampled back into the requester's item |
| Completer model | Reactive memory-backed base slave sequence (`ovip_mem`), or override the hooks for a register model |
| Scoreboard | `ovip_apb_scoreboard`, in-order, `trans.diff()`-formatted mismatch reports |
| Transaction logging | Per-agent + combined-file text log via `cfg.enable_trans_log` |

Full list of known limitations lives in [CHANGELOG.md](CHANGELOG.md);
wanted-features in [CONTRIBUTING.md](CONTRIBUTING.md).

## Integrating into your environment

The VIP ships a single compile filelist, [`ovip_apb.f`](ovip_apb.f). Add it to
your simulator command and you're done:

```sh
# 1) Tell the filelist where this repo is.
export OVIP_ROOT=/path/to/ovip

# 2) Add ovip_apb.f to your existing compile step.
```

| Simulator | Command |
|---|---|
| Modelsim/Questa | `vlog -sv -mfcu -f $OVIP_ROOT/verif/ovip_apb/ovip_apb.f` |
| VCS             | `vcs -sverilog -ntb_opts uvm-1.2 -f $OVIP_ROOT/verif/ovip_apb/ovip_apb.f` |
| Xcelium         | `xrun -uvm -uvmhome CDNS-1.2 -sv -f $OVIP_ROOT/verif/ovip_apb/ovip_apb.f` |

UVM 1.2 comes from your simulator's built-in library.

## Instantiating the agents

```systemverilog
import ovip_apb_pkg::*;

ovip_apb_agent_config req_cfg = ovip_apb_agent_config::type_id::create("req_cfg");
req_cfg.agent_type = OVIP_APB_REQUESTER;
req_cfg.is_active  = UVM_ACTIVE;
req_cfg.addr_width = 16;
req_cfg.data_width = 4;          // bytes: 8/16/32-bit bus = 1/2/4
req_cfg.pstrb_en   = 1;          // APB4
req_cfg.pprot_en   = 1;          // APB4

ovip_apb_agent req_agent = ovip_apb_agent::type_id::create("req_agent", this);
req_agent.cfg = req_cfg;
// ... and the same with OVIP_APB_COMPLETER for the completer side.
```

Bind the interface once per agent scope:

```systemverilog
ovip_apb_agent_if apb_if(pclk, presetn);
initial uvm_config_db#(virtual ovip_apb_agent_if)::set(null, "*.req_agent*",  "vif", apb_if);
initial uvm_config_db#(virtual ovip_apb_agent_if)::set(null, "*.comp_agent*", "vif", apb_if);
```

## Writing sequences

Requester side -- `apb_write` / `apb_read` block until the wire-level
transfer completes and return the response:

```systemverilog
class my_seq extends ovip_apb_base_master_sequence;
    virtual task body();
        ovip_apb_data_t rdata;
        bit slverr;
        apb_write('h10, 32'hDEAD_BEEF, , , slverr);
        apb_read ('h10, rdata, slverr);
    endtask
endclass
```

Completer side -- start the memory-backed base slave sequence (or a subclass)
on the completer agent's `slave_sqr`. It must answer each request in zero
simulation time (see the class header):

```systemverilog
ovip_apb_base_slave_sequence slave_seq = ovip_apb_base_slave_sequence::type_id::create("slave_seq");
slave_seq.mem = mem;                       // ovip_mem instance
slave_seq.set_wait_states(0, 4);           // optional; defaults come from cfg
fork slave_seq.start(comp_agent.slave_sqr); join_none
```

Override `get_slverr(req)` / `get_num_wait_states(req)` /
`populate_data_from_mem(req)` / `write_transaction_to_mem(req)` for error
injection, directed wait states, or a register-model completer.

## Compile-Time Defines

| Define | Default | Purpose |
|---|---|---|
| `OVIP_APB_MAX_ADDR_WIDTH` | 32 | Physical PADDR wire width (spec maximum) |
| `OVIP_APB_MAX_DATA_WIDTH` | 32 | Physical PWDATA/PRDATA wire width (spec maximum) |
| `OVIP_APB_WAIT_STATES_MAX` | 15 | Soft cap on randomized `num_wait_states` |
| `OVIP_APB_DELAY_UNTIL_NEXT_TRANS_MAX` | 30 | Soft cap on randomized inter-transfer gaps |
| `OVIP_APB_INCLUDE_USER_DEFINES` | off | Include a user-supplied `ovip_apb_user_defines.sv` first |
