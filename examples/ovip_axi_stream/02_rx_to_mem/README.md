# AXI-Stream → `ovip_mem` -- capture stream into a memory model

Wires a receiver-side subscriber into `ovip_mem.write_bytestream`, so every AXI-Stream packet that arrives at the receiver is appended into a memory at a running write address. After the stimulus completes, the test reads the bytes back out of `ovip_mem` and verifies they match the data bytes the transmitter intended to deliver.

This is the canonical "rx → memory" pipeline:

```
transmitter -> [valid/data/qualifiers/last] -> receiver monitor
                                                    |
                                                    | analysis_port
                                                    v
                                          trans.get_data_bytes()  (drops null + position bytes)
                                                    |
                                                    v
                                          mem.write_bytestream(addr, bytes)
                                                    |
                                                    v
                                          mem.read_bytestream(0, N)  (verify)
```

## What it demonstrates

- **`ovip_axi_stream_trans::get_data_bytes()`** -- returns a flat `ovip_bytestream` of the packet's *valid* bytes only:
  - bytes with `TKEEP = 0` (null bytes) are dropped automatically
  - bytes with `TKEEP = 1, TSTRB = 0` (position bytes) are dropped by default; pass `include_position_bytes = 1` to keep them
  - the per-beat ordering is preserved
- **`ovip_mem::write_bytestream(addr, data)`** -- appends a byte queue into the memory at a chosen address; subsequent writes can continue at `addr + data.size()`.
- **`ovip_mem::read_bytestream(addr, size)`** -- reads a span back as a byte queue so the test can compare against the producer's intent.

The example feeds two packets:
1. A 3-beat packet with all-data bytes.
2. A 2-beat packet whose first beat marks one byte as a *null byte* (TKEEP=0). The subscriber's `mem.write_bytestream` only ever sees the kept bytes, so the memory layout stays contiguous.

If everything works, the log ends with `UVM_ERROR : 0` and the `RX2MEM` info line confirming how many bytes round-tripped.

## Files

| | |
|---|---|
| `rx_to_mem_example.sv` | Sequence + subscriber + test + `tb_top`. |
| `Makefile` | `SIM=modelsim/vcs/xcelium` knob. |

## Running

```sh
make             # default: SIM=modelsim
```

## What to read next

- The `get_data_bytes` semantics (TKEEP / TSTRB filtering, defaults when qualifiers are absent) are documented in the *Byte qualifiers* section of [`verif/ovip_axi_stream/README.md`](../../../verif/ovip_axi_stream/README.md).
- `ovip_mem` itself is documented in [`verif/ovip_common/README.md`](../../../verif/ovip_common/README.md).
