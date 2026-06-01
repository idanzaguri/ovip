# Minimal Loopback — `ovip_axi` hello-world

A single test that brings up one master agent and one slave agent on the same interface, then sends four writes followed by four matching reads. The slave responds out of an `ovip_mem` (the VIP's built-in word-addressed memory model), so the reads return whatever the writes put in.

If everything works, the UVM Report Summary at the end shows:

```
UVM_ERROR :    0
UVM_FATAL :    0
```

That is the success criterion.

## Files

| | |
|---|---|
| `loopback_example.sv` | One file with: a small package (test class + master sequence) and the `tb_top` module (clock, reset, interface, `run_test`). |
| `Makefile` | Compile and run with Modelsim/Questa, VCS, or Xcelium. |

No external Python, no YAML, no Jinja2. Just `make` and a simulator.

## Running

```sh
make             # default: SIM=modelsim
make SIM=vcs
make SIM=xcelium
make clean
```

The Makefile assumes `vlog`/`vsim` / `vcs` / `xrun` are on your `PATH`. The example pulls the VIP sources directly from `../../verif/ovip_axi/src/` via `+incdir+`.

> **Free simulator:** this example has been validated on **Modelsim** (the Intel/Altera FPGA Starter Edition is free). The VCS and Xcelium targets are provided for users who already have a commercial license — they're wired up but not validated as part of every change.

## What to read next

- The `loopback_example.sv` source is intentionally tight (~150 lines) and reads top-to-bottom.
- For the full VIP feature surface, every test under `verif/ovip_axi_testbench/src/*_test.sv` has a header comment describing what it verifies — that's the comprehensive set.
- The "Writing Sequences" section of [`verif/ovip_axi/README.md`](../../verif/ovip_axi/README.md) covers the get/put model used by the master driver and the zero-time-response rule for slave sequences.
