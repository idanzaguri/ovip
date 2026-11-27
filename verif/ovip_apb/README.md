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
| Check reports | Every check has a message ID of its own. `cfg.set_check_severity()` and `cfg.set_check_action()` change how one agent reports one check, see [Check Reports](#check-reports) |
| Idle values | 0 on every idle cycle (`cfg.drive_reset_values_when_idle`, on by default), the last value, or random payload on a requester (`cfg.randomize_idle_payload`) |

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
| Verilator       | `verilator --binary --timing +define+UVM_NO_DPI +incdir+$UVM_HOME/src $UVM_HOME/src/uvm_pkg.sv -f $OVIP_ROOT/verif/ovip_apb/ovip_apb.f` |

UVM 1.2 comes from your simulator's built-in library. Verilator has none:
`UVM_HOME` is a UVM 1.2 source tree, and `randomize()` needs an SMT solver
(z3, cvc5, yices-smt2 or bitwuzla) at run time. See
[Running on Verilator](../../README.md#running-on-verilator).

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

`cfg.is_active` alone decides whether an agent is active. An `is_active`
given to the agent through the UVM config DB is not used. `cfg.clone()` and
`copy()` carry every field of a config.

A requester with `req_cfg.randomize_idle_payload = 1` drives random PADDR,
PWRITE, PWDATA, PSTRB and PPROT while PSEL is LOW, at reset and after every
transfer. APB gives them a meaning only while PSEL is HIGH, so a completer
that takes one too early shows it. It is off by default.

The monitor checks PWDATA for X/Z and for stability on the byte lanes whose
PSTRB bit is HIGH, the lanes that must be valid in a write (spec Appendix
A.1). An agent with `pstrb_en = 0` has every lane active. Set
`cfg.check_undefined_data_lanes = 1` on an agent to make its monitor check
every lane inside the data width, whatever PSTRB says. It is off by default.

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

`apb_write` and `apb_read` build their items directly. A sequence that
randomizes an `ovip_apb_trans` constrains it to the agent's configuration
itself, because the item does not know the cfg: `addr` inside `addr_width`
bits and aligned to the data bus width, and on an 8-bit or 16-bit bus `wdata`
and `strb` inside the `data_width` bytes. The item keeps `strb` at 0 on a
read by itself. The master driver warns about a field that is too wide and
masks it, and the base slave sequence warns about an unaligned address
(`APB_SLAVE_SEQ/UNALIGNED_PADDR`). A bench that drives an unaligned address
on purpose changes the report of that warning, see
[Check Reports](#check-reports).

```systemverilog
// addr_width = 16, data_width = 4
if(!tr.randomize() with { addr < (1 << 16); addr % 4 == 0; })
    `uvm_error("MY_SEQ", "randomize failed")
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

The wait-state range can also be set by assigning `slave_seq.min_ws` and
`slave_seq.max_ws`, or by randomizing the sequence, before `start()`. A knob
that nobody set (it is left at `WS_FROM_CFG`) takes
`cfg.default_min_wait_states` / `cfg.default_max_wait_states` when the
sequence starts. A subclass with a `body()` of its own calls
`apply_default_wait_states()` first.

A memory with valid ranges (`mem.add_valid_range`) makes the completer answer PSLVERR outside them (OKAY on an agent with `pslverr_en = 0`), memory untouched, reported as `SLAVE_SEQ/OUT_OF_RANGE` unless `report_out_of_range` is cleared. Override `get_slverr(req)` / `get_num_wait_states(req)` /
`populate_data_from_mem(req)` / `write_transaction_to_mem(req)` for error
injection, directed wait states, or a register-model completer.

## Check Reports

A check is a rule that the VIP tests and reports as a `UVM_ERROR` or a `UVM_WARNING`. Every check has a message ID of its own, so the message ID names the check.

A bench that breaks a rule on purpose changes the report of that check, for one agent, on the agent's config:

```systemverilog
// The bench drives an unaligned PADDR on purpose: print the warning as UVM_INFO.
comp_cfg.set_check_severity("APB_SLAVE_SEQ/UNALIGNED_PADDR", UVM_INFO);
// Or print nothing and count nothing.
comp_cfg.set_check_action("APB_SLAVE_SEQ/UNALIGNED_PADDR", UVM_NO_ACTION);
```

| `cfg` method | Meaning |
|---|---|
| `set_check_severity(id, severity)` | The agent reports the check `id` with `severity` (`UVM_INFO`, `UVM_WARNING`, `UVM_ERROR` or `UVM_FATAL`) in place of its default severity. |
| `set_check_action(id, action)` | The report of the check `id` gets the UVM action `action`. `UVM_NO_ACTION` prints nothing and counts nothing. |

- Give the ID as the tables below show it, without `cfg.agent_tag`. The agent adds the tag where a component uses it.
- Call the methods before the agent's `connect_phase`, where you set the other `cfg` fields. The agent applies them in `connect_phase` to its monitor, its driver and its sequencer. A sequence reports through the sequencer it runs on, so the checks of a sequence are covered.
- Only the report changes. The check still runs, and what it does beside the report stays.
- The setting is per agent. The other agents report the check as before.
- The methods use the UVM report overrides of the components (`set_report_severity_id_override`, `set_report_severity_id_action`). You can call these on a component yourself, for example to change a report during the run. Then give the full ID, with the agent tag: `REQ/APB_MON/READ_STRB`.
- A `UVM_FATAL` is not a check: `set_check_severity()` does not change it (`set_check_action()` also sets the `UVM_FATAL` action for the ID so a check promoted to `UVM_FATAL` keeps its configured action).

### Monitor checks

All are `UVM_ERROR`.

| Message ID | The monitor reports |
|---|---|
| `APB_MON/XZ_CHECK` | An X or a Z on a signal that must have a value. |
| `APB_MON/STABILITY` | PADDR, PWRITE, PPROT, PWDATA or PSTRB that changed during the transfer. |
| `APB_MON/READ_STRB` | A PSTRB bit that is high during a read transfer. |
| `APB_MON/FSM_ACCESS_NO_SETUP` | PSEL and PENABLE high with no SETUP cycle before. |
| `APB_MON/FSM_SETUP_ABORTED` | PSEL low on the cycle after SETUP. |
| `APB_MON/FSM_SETUP_LENGTH` | PENABLE low on the cycle after SETUP. |
| `APB_MON/FSM_ACCESS_ABORTED` | PSEL or PENABLE low while PREADY is low. |
| `APB_MON/FSM_PENABLE_HELD` | PENABLE still high on the cycle after the transfer. |

### Driver and sequence checks

| Message ID | Severity | Reported by | Reports |
|---|---|---|---|
| `APB_DRV/TR_CHK/WIDTH` | `UVM_WARNING` | master driver | A field of the item that does not fit the configured width of its signal. |
| `APB_DRV/TR_CHK/READ_STRB` | `UVM_WARNING` | master driver | A read item with `strb` not 0. PSTRB is driven low. |
| `APB_SLAVE_DRV/OFF_EDGE` | `UVM_WARNING` | slave driver | A slave sequence that returned an item off the clock edge. |
| `APB_SLAVE_SEQ/UNALIGNED_PADDR` | `UVM_WARNING` | base slave sequence | A PADDR that is not aligned to the data bus width. The sequence aligns it down. |
| `SLAVE_SEQ/OUT_OF_RANGE` | `UVM_ERROR` | base slave sequence | A request that touches an address outside the valid ranges of the memory. |
| `APB_RW_SEQ/SLVERR` | `UVM_ERROR` | `ovip_apb_simple_rw_seq` | A SLVERR on a write or a read of the sequence. |
| `APB_RW_SEQ/MISMATCH` | `UVM_ERROR` | `ovip_apb_simple_rw_seq` | Read data that differs from the data the sequence wrote. |
| `APB_LOG` | `UVM_WARNING` | `ovip_apb_trans_logger` | A transaction log file that could not be opened. |

## Compile-Time Defines

| Define | Default | Purpose |
|---|---|---|
| `OVIP_APB_MAX_ADDR_WIDTH` | 32 | Physical PADDR wire width (spec maximum) |
| `OVIP_APB_MAX_DATA_WIDTH` | 32 | Physical PWDATA/PRDATA wire width (spec maximum) |
| `OVIP_APB_MAX_STRB_WIDTH` | `OVIP_APB_MAX_DATA_WIDTH/8` | Physical PSTRB wire width, one bit per byte of the data bus |
| `OVIP_APB_WAIT_STATES_MAX` | 15 | Soft cap on randomized `num_wait_states` |
| `OVIP_APB_DELAY_UNTIL_NEXT_TRANS_MAX` | 30 | Soft cap on randomized inter-transfer gaps |
| `OVIP_APB_INCLUDE_USER_DEFINES` | off | Include a user-supplied `ovip_apb_user_defines.sv` first |
| `OVIP_INPUT_SKEW` | `1step` | Input skew of the interface's clocking blocks (`monitor_cb`, `master_cb`, `slave_cb`): the value from before the clock edge. Shared by every OVIP VIP (`ovip_common/ovip_common_defines.sv`). |
| `OVIP_OUTPUT_SKEW` | `0` | Output skew of the same clocking blocks. |
