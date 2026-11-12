# OVIP AXI-Stream

UVM verification IP for the AMBA AXI-Stream protocols -- **AXI4-Stream** and **AXI5-Stream** (ARM IHI 0051B). One transmitter agent and one receiver agent on a single point-to-point channel; the monitor performs X/Z and signal-stability checks plus the AXI-Stream-specific protocol checks (TKEEP/TSTRB reserved combination, no interleaved packets and no null bytes within a packet with `continuous_packets`, TVALID-during-reset, exit-from-reset rule, AXI5 wake-up hold). Apache-2.0 licensed; same simulator portability story as the rest of the OVIP family.

### At a glance

| Area | Status |
|---|---|
| Protocols | AXI4-Stream, AXI5-Stream |
| Optional signals | TREADY, TDATA, TSTRB, TKEEP, TLAST, TID, TDEST, TUSER, TWAKEUP (AXI5) |
| TDATA width | 1 B - 128 B (override `OVIP_AXI_STREAM_MAX_DATA_WIDTH` for wider) |
| Byte qualifiers | TKEEP + TSTRB decoded per spec section 2.5.3; reserved combo flagged |
| Packet boundaries | TLAST. The monitor keeps one open packet per TID and TDEST pair, so interleaved streams (spec section 2.7) come out as separate packets |
| TUSER | Per-byte (`tuser_bits_per_byte * tdata_width`), spec section 2.9 indexing |
| AXI5 wake-up | TWAKEUP with the "hold until TREADY" rule enforced by the monitor |
| AXI5 parity | Not supported. The interface has no check signals, and nothing generates or checks parity. `parity_en` is read only by `check_config`, which rejects it on AXI4-Stream |
| TREADY back-pressure | Per-receiver `default_tready_pattern` (cycles[$] + loop), preempt-able per-agent |
| Continuous-packets profile | With `continuous_packets`, `check_config` rejects TSTRB and the monitor reports interleaved packets (`AXIS_MON/PKT_SCOPE`) and null bytes within a packet (`AXIS_MON/NULL_BYTE`) |
| Scoreboard | `ovip_axi_stream_scoreboard` with per-TID FIFOs, `defensive_copy_expected` knob, `trans.diff()`-formatted mismatch reports |

Full list of known limitations lives in [CHANGELOG.md](CHANGELOG.md); wanted-features in [CONTRIBUTING.md](CONTRIBUTING.md).

## Integrating into your environment

The VIP ships a single compile filelist, [`ovip_axi_stream.f`](ovip_axi_stream.f). Add it to your simulator command and you're done:

```sh
# 1) Tell the filelist where this repo is.
export OVIP_ROOT=/path/to/ovip

# 2) Add ovip_axi_stream.f to your existing compile step.
```

| Simulator | Command |
|---|---|
| Modelsim/Questa | `vlog -sv -mfcu -f $OVIP_ROOT/verif/ovip_axi_stream/ovip_axi_stream.f` |
| VCS             | `vcs -sverilog -ntb_opts uvm-1.2 -f $OVIP_ROOT/verif/ovip_axi_stream/ovip_axi_stream.f` |
| Xcelium         | `xrun -uvm -uvmhome CDNS-1.2 -sv -f $OVIP_ROOT/verif/ovip_axi_stream/ovip_axi_stream.f` |
| Verilator       | `verilator --binary --timing +define+UVM_NO_DPI +incdir+$UVM_HOME/src $UVM_HOME/src/uvm_pkg.sv -f $OVIP_ROOT/verif/ovip_axi_stream/ovip_axi_stream.f` |

UVM 1.2 comes from your simulator's built-in library; Verilator has none, so `UVM_HOME` is a UVM 1.2 source tree and `randomize()` needs an SMT solver at run time, see [Running on Verilator](../../README.md#running-on-verilator). Apply any [Compile-Time Defines](#compile-time-defines) below as additional `+define+...` arguments on the same compile line.

The minimal runnable example is [`examples/ovip_axi_stream/01_loopback/`](../../examples/ovip_axi_stream/01_loopback/); for the receiver-into-memory pipeline see [`examples/ovip_axi_stream/02_rx_to_mem/`](../../examples/ovip_axi_stream/02_rx_to_mem/).

## Compile-Time Defines

| Define | Default | Used for |
|---|---|---|
| `OVIP_AXI_STREAM_MAX_DATA_WIDTH` | `128*8` (= 1024) | TDATA wire width. Must be ≥ `tdata_width * 8` of any agent. |
| `OVIP_AXI_STREAM_MAX_STRB_WIDTH` | `MAX_DATA_WIDTH/8` | TSTRB wire width. Derived; override only for non-default ratios. |
| `OVIP_AXI_STREAM_MAX_KEEP_WIDTH` | `MAX_DATA_WIDTH/8` | TKEEP wire width. Same story as TSTRB. |
| `OVIP_AXI_STREAM_MAX_ID_WIDTH`   | `8` | TID wire width (spec recommends ≤ 8). |
| `OVIP_AXI_STREAM_MAX_DEST_WIDTH` | `8` | TDEST wire width (spec recommends ≤ 8). |
| `OVIP_AXI_STREAM_MAX_USER_WIDTH` | `1024` | TUSER wire width. Sized to allow large per-byte payloads on wide buses. |
| `OVIP_AXI_STREAM_DELAY_BETWEEN_BEATS_MAX` | `30` | Soft cap on randomized per-beat gap. |
| `OVIP_AXI_STREAM_DELAY_UNTIL_NEXT_TRANS_MAX` | `30` | Soft cap on randomized inter-packet gap. |
| `OVIP_INPUT_SKEW` | `1step` | Input skew of the interface's clocking blocks (`monitor_cb`, `master_cb`, `slave_cb`): the value from before the clock edge. Shared by every OVIP VIP (`ovip_common/ovip_common_defines.sv`). |
| `OVIP_OUTPUT_SKEW` | `0` | Output skew of the same clocking blocks. |

## Signal model

The interface (`ovip_axi_stream_agent_if`) carries the full superset of AXI4-Stream + AXI5-Stream signals at the MAX widths above. Each agent's runtime config selects which signals are *live* -- the per-signal `*_en` flags drive the monitor's checks and the transmitter's drive logic. Unused signals stay at zero on the wire and aren't checked (an unused TREADY is not driven at all, see [TREADY patterns](#tready-patterns)). Within a live signal the monitor looks at the configured width only (`tdata_width`, `tid_width`, `tdest_width`, `tuser_bits_per_byte`), so a DUT port wired to the low bits of a wire may leave the upper bits undriven. The master driver drives the configured width only as well: a field of an item that is wider than its signal is cut to that width, and the driver reports it with an `AXIS_DRV/TR_CHK` warning.

Three clocking blocks:

| | |
|---|---|
| `monitor_cb` | all signals are inputs (snoop) |
| `master_cb`  | drives everything except `tready` (transmitter) |
| `slave_cb`   | drives only `tready` (receiver) |

## Byte qualifiers (TKEEP, TSTRB)

Per spec section 2.5.3, the four legal combinations of TKEEP and TSTRB are:

| TKEEP | TSTRB | Meaning |
|:---:|:---:|---|
| `1` | `1` | **Data byte** -- content is meaningful and must reach the receiver. |
| `1` | `0` | **Position byte** -- placeholder; conveys structure but no data value. |
| `0` | `0` | **Null byte** -- can be inserted/removed by the interconnect. |
| `0` | `1` | **Reserved** -- must not be used. The monitor flags every occurrence via `AXIS_MON/BYTE_QUAL`. |

When `TSTRB` is absent on the interface, the spec defines `TSTRB ≡ TKEEP` (every transported byte is a data byte). When `TKEEP` is absent, every transported byte is also a data byte. **`ovip_axi_stream_trans::get_data_bytes()`** honors both defaults. The master driver uses the same defaults for a beat that the item has no `keep_beats` or `strb_beats` entry for: it drives TKEEP all HIGH, and TSTRB equal to the TKEEP of that beat.

The monitor's X/Z check and its stability check look at TDATA on the lanes of data bytes only (TKEEP HIGH and TSTRB HIGH, with the two defaults above for an absent signal), and at TUSER on the lanes of data bytes and position bytes (TKEEP HIGH). The TDATA of a position byte or a null byte is not valid (spec section 2.5.2) and the TUSER bits of a null byte are not transferred (spec section 2.9), so a transmitter may leave those lanes X, or change them while the beat waits for TREADY. Set `check_undefined_data_lanes = 1` in the agent config to make both checks cover every lane inside the configured widths.

## Packet boundaries (TLAST)

A packet is a run of transfers of one stream between two consecutive `TLAST` assertions of that stream (or a single transfer if `TLAST` is asserted on every beat). The monitor accumulates beats into one `ovip_axi_stream_trans` and publishes the packet on its analysis port when `TLAST` is sampled. If `TLAST` is not enabled, each transfer is treated as a one-beat packet.

A stream is a TID and TDEST pair, and streams may interleave transfer by transfer (spec sections 2.7 and 4.1). The monitor keeps one open packet per TID and TDEST pair (one for the channel when neither `tid_en` nor `tdest_en` is set). A transfer with another TID or TDEST while `TLAST` is LOW belongs to another stream and goes into the open packet of that stream. It is an error, `AXIS_MON/PKT_SCOPE`, only when `cfg.continuous_packets` is 1 (spec section 3.3). A reset drops every open packet.

With `cfg.continuous_packets = 1` and TKEEP present the monitor also reports a null byte within a packet, `AXIS_MON/NULL_BYTE` (spec section 3.3): a TKEEP bit LOW in a transfer with `TLAST` LOW, or a null byte below a data byte in a transfer with `TLAST` HIGH. Null bytes above all the data bytes of the last transfer are legal.

The transmitter driver sends one item as one packet, its beats in a row. It does not interleave streams.

## TREADY patterns

The receiver-side TREADY is driven by an `ovip_axi_stream_ready_pattern_t`:

```systemverilog
typedef struct {
    int unsigned cycles[$]; // per-level cycle counts; level alternates with index (even=0, odd=1)
    bit          loop;      // 1 = repeat the cycles queue; 0 = play once and hold the last level
} ovip_axi_stream_ready_pattern_t;
```

Default: `'{cycles:'{0, 1}, loop:0}` -- always-ready, no back-pressure.

Two delivery routes (same model as the ovip_axi ready patterns):
1. **Via `cfg.default_tready_pattern`** -- picked up at agent build.
2. **Direct helper** -- call `slave_agent.slave_drv.put_tready_pattern(cycles, loop)` from a test/sequence at any time.

Both routes feed the same per-channel mailbox; pushing a new pattern preempts the one currently running and restarts driving from its first element. A pattern whose cycle counts sum to 0 has no level to hold: the driver plays always-ready instead and reports an `AXIS_DRV/TREADY_PATTERN` warning.

With `tready_en = 0` the interface has no TREADY. The transmitter driver and the monitor take it as HIGH (spec section 3.1.1), so every cycle with TVALID HIGH is a transfer. The receiver driver does not drive the wire and plays no pattern, and `put_tready_pattern` only reports a warning.

## Writing sequences

The transmitter driver uses the standard `get_next_item` / `item_done` model. `send(tr)` from `ovip_axi_stream_base_master_sequence` returns once the *wire-level* packet has been driven completely, so the sequence's `body()` blocks transparently:

```systemverilog
class my_seq extends ovip_axi_stream_base_master_sequence;
    `uvm_object_utils(my_seq)
    function new(string name = "my_seq"); super.new(name); endfunction

    virtual task body();
        ovip_axi_stream_trans tr = ovip_axi_stream_trans::type_id::create("tr");
        tr.id = 0; tr.dest = 0;
        tr.data_beats = '{32'hC0DE_0001, 32'hC0DE_0002, 32'hC0DE_0003};
        tr.keep_beats = '{4'hF, 4'hF, 4'hF};
        tr.strb_beats = '{4'hF, 4'hF, 4'hF};
        send(tr);
    endtask
endclass
```

An `ovip_axi_stream_trans` can be randomized as well. Its constraints cover the queue sizes, the delays and the byte qualifiers: `c_no_reserved_byte_qualifier` allows no TSTRB bit where the TKEEP bit of the same beat is clear (turn it off with `tr.c_no_reserved_byte_qualifier.constraint_mode(0)` to send the reserved combination on purpose). The item does not know the agent's configuration. So after a bare `randomize()` the user still has to keep `id`, `dest` and the bits of `data_beats`, `keep_beats`, `strb_beats` and `user_beats` inside the configured widths, and `wakeup` at 0 on an agent without TWAKEUP: in the `with { ... }` block, or by masking the fields before `send()`. On Verilator (seen with 5.053 and yices) the elements of a queue that a constraint names come back with almost no variety, so `keep_beats` and `strb_beats` are 0 on every beat after a bare `randomize()`: fill them by hand there.

The receiver side is pattern-driven, not item-driven -- `ovip_axi_stream_base_slave_sequence` pulls monitor-captured packets off the slave sequencer's `response_req_port` and exposes a `process_request(req)` hook for tests that want to react (push a new TREADY pattern, log, etc.). The monitor queues packets for that port only after the first `get()` call on it: a packet that completes before a slave sequence runs is not delivered to it, and with no slave sequence nothing is queued. Start the slave sequence before the traffic it has to see.

The monitor fills `keep_beats`, `strb_beats` and `user_beats` of the packets it publishes only for a signal that is on the interface (`tkeep_en`, `tstrb_en`, `tuser_en`). `ovip_axi_stream_trans::compare()`, which the scoreboard uses, compares each of these queues only when both items filled it. So an expected item may carry a queue for an absent signal, or leave out a queue for a present one. `diff()` follows the same rule.

## Reset

The drivers and the monitor see a reset at the first clock edge where their clocking block samples ARESETn LOW. At that edge:

- The master driver drives the reset values (TVALID LOW, every payload signal 0). It completes the item it holds with `item_done()`, also an item that it has taken and not started, and drops it: it does not send that item again after the release. The packet on the wire stays cut.
- The receiver drives TREADY LOW until the release. After the release it plays `cfg.default_tready_pattern` again. A pattern that was playing when the reset came is not resumed. A pattern given with `put_tready_pattern` during the reset is played after the release.
- The monitor drops every open packet. A packet that the reset cut is not written to `analysis_port`.

A test that calls `stop_sequences()` on the transmitter's sequencer at a reset must call it after the master driver has seen the reset: not between the ARESETn falling edge and the next clock edge of the driver, and not in the time step of that clock edge. Two edges of `vif.master_cb` after ARESETn falls are enough. If the call comes earlier, the sequencer no longer holds the item when the driver completes it, and UVM ends the run with the fatal "Item_done() called with no outstanding requests".

Call `put_tready_pattern` from a thread that is synchronized to the interface clocking block (`@(vif.slave_cb)` or `@(vif.monitor_cb)`). From a thread that waits on the raw clock edge (`@(posedge aclk)`), or that calls between two clock edges, the first element of the new pattern is one cycle short while the receiver holds the last level of a one-shot pattern. The default pattern is one-shot: with it, `'{6, 1}` gives 5 LOW cycles.

## Reading further

This README covers the surface most users hit day-to-day. For the edge cases -- every spec-rule monitor check in `src/ovip_axi_stream_monitor.sv`, the transmitter's per-beat lane handling in `src/ovip_axi_stream_master_driver.sv`, the scoreboard's per-TID FIFO policy in `src/ovip_axi_stream_scoreboard.sv` -- **the code is the authoritative reference**. Every source file opens with a short header explaining what it does and where to look next. If you hit something the README should spell out and doesn't, an issue or PR is welcome.

## License

Licensed under the Apache License, Version 2.0 -- see [LICENSE](LICENSE) and [NOTICE](NOTICE).
Copyright 2026 Idan Zaguri.
