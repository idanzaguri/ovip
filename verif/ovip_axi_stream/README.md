# OVIP AXI-Stream

UVM verification IP for the AMBA AXI-Stream protocols — **AXI4-Stream** and **AXI5-Stream** (ARM IHI 0051B). One transmitter agent and one receiver agent on a single point-to-point channel; the monitor performs X/Z and signal-stability checks plus the AXI-Stream-specific protocol checks (TKEEP/TSTRB reserved combination, TID/TDEST stability within a packet, TVALID-during-reset, exit-from-reset rule, AXI5 wake-up hold). Apache-2.0 licensed; same simulator portability story as the rest of the OVIP family.

### At a glance

| Area | Status |
|---|---|
| Protocols | AXI4-Stream, AXI5-Stream |
| Optional signals | TREADY, TDATA, TSTRB, TKEEP, TLAST, TID, TDEST, TUSER, TWAKEUP (AXI5) |
| TDATA width | 1 B – 128 B (override `OVIP_AXI_STREAM_MAX_DATA_WIDTH` for wider) |
| Byte qualifiers | TKEEP + TSTRB decoded per spec section 2.5.3; reserved combo flagged |
| Packet boundaries | TLAST, with packet-scope TID/TDEST stability enforced |
| TUSER | Per-byte (`tuser_bits_per_byte * tdata_width`), spec section 2.9 indexing |
| AXI5 wake-up | TWAKEUP with the "hold until TREADY" rule enforced by the monitor |
| AXI5 parity | Property declared (`Check_Type = Odd_Parity_Byte_All`); the `*chk` signals are wired through and reserved -- enforcement ships in a follow-up |
| TREADY back-pressure | Per-receiver `default_tready_pattern` (cycles[$] + loop), preempt-able per transaction or per-agent |
| Continuous-packets profile | Config flag enforces "no TSTRB, no nulls, no interleave" |
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

UVM 1.2 comes from your simulator's built-in library. Apply any [Compile-Time Defines](#compile-time-defines) below as additional `+define+...` arguments on the same compile line.

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

## Signal model

The interface (`ovip_axi_stream_agent_if`) carries the full superset of AXI4-Stream + AXI5-Stream signals at the MAX widths above. Each agent's runtime config selects which signals are *live* — the per-signal `*_en` flags drive the monitor's checks and the transmitter's drive logic. Unused signals stay at zero on the wire and aren't checked.

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
| `1` | `1` | **Data byte** — content is meaningful and must reach the receiver. |
| `1` | `0` | **Position byte** — placeholder; conveys structure but no data value. |
| `0` | `0` | **Null byte** — can be inserted/removed by the interconnect. |
| `0` | `1` | **Reserved** — must not be used. The monitor flags every occurrence via `AXIS_MON/BYTE_QUAL`. |

When `TSTRB` is absent on the interface, the spec defines `TSTRB ≡ TKEEP` (every transported byte is a data byte). When `TKEEP` is absent, every transported byte is also a data byte. **`ovip_axi_stream_trans::get_data_bytes()`** honors both defaults.

## Packet boundaries (TLAST)

A packet is a run of transfers between two consecutive `TLAST` assertions (or a single transfer if `TLAST` is asserted on every beat). The monitor accumulates beats into one `ovip_axi_stream_trans` and publishes the packet on its analysis port when `TLAST` is sampled. If `TLAST` is not enabled, each transfer is treated as a one-beat packet.

Per spec section 2.6, **TID and TDEST must not change within a packet**. The monitor takes the first beat's TID/TDEST as the packet's scope values and raises `AXIS_MON/PKT_SCOPE` on any subsequent beat that disagrees.

## TREADY patterns

The receiver-side TREADY is driven by an `ovip_axi_stream_ready_pattern_t`:

```systemverilog
typedef struct {
    int unsigned cycles[$]; // per-level cycle counts; level alternates with index (even=0, odd=1)
    bit          loop;      // 1 = repeat the cycles queue; 0 = play once and hold the last level
} ovip_axi_stream_ready_pattern_t;
```

Default: `'{cycles:'{0, 1}, loop:0}` — always-ready, no back-pressure.

Three delivery routes (same model as the ovip_axi ready patterns):
1. **Via `cfg.default_tready_pattern`** — picked up at agent build.
2. **Via the transaction** — set `tr.tready_pattern` to override for *future* incoming packets.
3. **Direct helper** — call `slave_agent.slave_drv.put_tready_pattern(cycles, loop)` from a test/sequence at any time.

All three routes feed the same per-channel mailbox; pushing a new pattern preempts the one currently running and restarts driving from its first element.

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

The receiver side is pattern-driven, not item-driven — `ovip_axi_stream_base_slave_sequence` pulls monitor-captured packets off the slave sequencer's `response_req_port` and exposes a `process_request(req)` hook for tests that want to react (push a new TREADY pattern, log, etc.).

## Reading further

This README covers the surface most users hit day-to-day. For the edge cases — every spec-rule monitor check in `src/ovip_axi_stream_monitor.sv`, the transmitter's per-beat lane handling in `src/ovip_axi_stream_master_driver.sv`, the scoreboard's per-TID FIFO policy in `src/ovip_axi_stream_scoreboard.sv` — **the code is the authoritative reference**. Every source file opens with a short header explaining what it does and where to look next. If you hit something the README should spell out and doesn't, an issue or PR is welcome.

## License

Licensed under the Apache License, Version 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
Copyright 2026 Idan Zaguri.
