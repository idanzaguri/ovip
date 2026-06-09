# Response Timing -- `ovip_axi` example

Demonstrates the two main slave-side response-timing knobs and makes their effect directly visible in the simulation log:

| Knob | Where set | Meaning |
|---|---|---|
| `bresp_delay` | per-transaction on the slave seq (via `get_bresp_delay()` hook) | cycles between WLAST sample and BRESP drive |
| `data_delay[$]` | per-transaction on the slave seq (via `set_read_trans_delays()` hook) | element 0 is the AR-handshake → first-R-beat gap; subsequent elements are inter-beat gaps |

## What it demonstrates

- A `timing_slave_seq` subclasses `ovip_axi_base_slave_sequence` and overrides:
  - `get_bresp_delay()` → returns `BRESP_GAP = 10`
  - `set_read_trans_delays(tr)` → fills `tr.data_delay` with `[RDATA_GAP0=6, RDATA_GAPN=2, 2, 2]`
- A fork-join thread in the test watches every channel handshake (AW, W, AR, R, B) and prints `t=...` on each, so the gaps are readable straight from the log.
- The data path is plain loopback so any timing-driven bug surfaces as a data-mismatch UVM_ERROR.

One non-obvious detail the example also shows: the master sequence calls `wait_for_responses()` between the write and the read. Without that, the read's AR handshake fires the same cycle as the write's AW (the get/put model accepts items in zero time), and the slave's read-response sequence samples `mem` *before* the write has committed. With the default `wr_mem_update_on_bresp = 1`, the read would return the pre-write value. This is the canonical gotcha for new users.

## Files

| | |
|---|---|
| `timing_example.sv` | Custom slave sequence, master sequence with explicit `wait_for_responses` between W and R, channel watcher, test, and `tb_top`. |
| `Makefile` | Same `SIM=modelsim/vcs/xcelium` knob as the other examples. |

## Running

```sh
make             # default: SIM=modelsim
```

## Expected output

```
[TIMING_MST] issuing wr addr=0x0, 4 beats
[WATCH_AW] aw handshake          t=5000
[WATCH_W ] w beat wdata=...0000  t=5000
[WATCH_W ] w beat wdata=...0001  t=6000
[WATCH_W ] w beat wdata=...0002  t=7000
[WATCH_W ] w beat wdata=...0003 wlast=1 t=8000
[WATCH_B ] bresp                 t=19000        <- WLAST + 11 cycles (BRESP_GAP=10 + 1 dispatch)
[TIMING_MST] issuing rd addr=0x0, 4 beats
[WATCH_AR] ar handshake          t=21000
[WATCH_R ] r beat rdata=...0000  t=28000        <- AR + 7 cycles (RDATA_GAP0=6 + 1 dispatch)
[WATCH_R ] r beat rdata=...0001  t=31000        <- +3 cycles (RDATA_GAPN=2 + 1 dispatch)
[WATCH_R ] r beat rdata=...0002  t=34000        <- +3 cycles
[WATCH_R ] r beat rdata=...0003 rlast=1 t=37000 <- +3 cycles
UVM_ERROR : 0
UVM_FATAL : 0
```

Adjust the `BRESP_GAP`, `RDATA_GAP0`, `RDATA_GAPN` `localparam`s at the top of the file and re-run to see the timestamps shift accordingly.

## What to read next

- **"Slave sequences (zero-time response rule)"** in the VIP README explains *why* delays are expressed on the transaction rather than inline in the sequence body.
- **"Ready Patterns"** in the same README covers the other half of slave-side timing: when `awready`/`arready`/`wready` are deasserted to throttle the master.
- **`wr_mem_update_on_bresp`** controls *when* a write actually commits to memory (after BRESP vs. immediately on WLAST). The base slave sequence documents both modes near its definition.
