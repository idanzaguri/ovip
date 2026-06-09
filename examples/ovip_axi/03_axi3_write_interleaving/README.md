# AXI3 W-Channel Interleaving -- `ovip_axi` example

Demonstrates the AXI3 write-channel interleaving feature: two writes with different IDs can have their data beats interleaved on the bus, with each beat tagged by `wid`. AXI4 dropped this feature; on AXI4 the W beats of one write must complete before the next can start.

## What it demonstrates

- **`cfg.protocol_type = OVIP_PROTOCOL_AXI3`** -- required; setting `wr_interleave_depth > 1` with AXI4 raises a config error.
- **`cfg.wr_interleave_depth`** -- how many distinct write IDs may have their W beats in flight concurrently. `1` = no interleaving (back-to-back).
- **`cfg.wr_out_of_order_depth`** -- reorder window for the master driver's W scheduler; must be at least the interleave depth.
- **`cfg.wr_scheduling_alg`** -- `OVIP_AXI_SCH_ALG_ROUND_ROBIN` here, which alternates between IDs cycle-by-cycle.
- **Matching slave config** -- the slave's monitor enforces `wr_interleave_depth` and `wr_out_of_order_depth` against observed traffic; both must be at least as big as what the master actually does or you'll see `AXI_MON/WDATA_OOO` errors.
- **Live W-channel watcher** -- a small `forever` thread in the test prints `wid, wdata, wlast` for every accepted W handshake, making the interleave pattern visible in the log.

## Files

| | |
|---|---|
| `interleave_example.sv` | Master sequence + base slave sequence (loopback) + test with the W-channel watcher + `tb_top`. |
| `Makefile` | Same `SIM=modelsim/vcs/xcelium` knob as the other examples. |

## Running

```sh
make             # default: SIM=modelsim
```

## Expected output

The watcher output makes the interleaving obvious -- `wid` alternates 0,1,0,1,... and the data field embeds the write ID and the beat index:

```
[ITLV_MST] issuing wr id=0 addr=0x0,  4 beats
[ITLV_MST] issuing wr id=1 addr=0x40, 4 beats
[ITLV_WATCH] W beat: wid=0 wdata=0xaabb0000 wlast=0
[ITLV_WATCH] W beat: wid=1 wdata=0xaabb0010 wlast=0
[ITLV_WATCH] W beat: wid=0 wdata=0xaabb0001 wlast=0
[ITLV_WATCH] W beat: wid=1 wdata=0xaabb0011 wlast=0
[ITLV_WATCH] W beat: wid=0 wdata=0xaabb0002 wlast=0
[ITLV_WATCH] W beat: wid=1 wdata=0xaabb0012 wlast=0
[ITLV_WATCH] W beat: wid=0 wdata=0xaabb0003 wlast=1
[ITLV_WATCH] W beat: wid=1 wdata=0xaabb0013 wlast=1
UVM_ERROR : 0
UVM_FATAL : 0
```

`UVM_ERROR : 0` is the success criterion. After the interleaved writes complete, the master reads every address back; a subscriber on the master's analysis port checks each read returned the value originally written, confirming the slave's monitor reassembled the per-ID streams correctly despite the interleaving.

## What to read next

- **Out-of-order, interleaving & scheduling** -- the corresponding section in the VIP README covers eligibility rules, the five scheduling algorithms, and the AXI3-vs-AXI4 differences.
- **Per-channel scheduler** is implemented in `verif/ovip_axi/src/ovip_axi_out_of_order_queue.sv` if you want to see the exact pick algorithm.
