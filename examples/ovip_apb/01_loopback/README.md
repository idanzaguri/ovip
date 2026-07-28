# Minimal APB Loopback -- `ovip_apb` hello-world

A single test that brings up one requester agent and one completer agent on the same APB interface. The completer runs the memory-backed base slave sequence (an `ovip_mem` behind the bus); the requester writes four words and reads each one back, self-checking the returned data -- the master driver samples PRDATA into the sequence item, so `apb_read` returns the data directly.

If everything works, the UVM Report Summary at the end shows:

```
UVM_ERROR :    0
UVM_FATAL :    0
```

That is the success criterion.

## Files

| | |
|---|---|
| `loopback_example.sv` | One file with: a small package (requester sequence + test class) and the `tb_top` module (clock, reset, interface, `run_test`). |
| `Makefile` | Compile and run with Modelsim/Questa, VCS, or Xcelium. |

## Running

```sh
make             # default: SIM=modelsim
```

## What to read next

- The `loopback_example.sv` source is tight (~120 lines) and reads top-to-bottom.
- The "At a glance" matrix and "Writing sequences" section of [`verif/ovip_apb/README.md`](../../../verif/ovip_apb/README.md) cover the VIP's feature surface, the wait-state / SLVERR hooks on the slave sequence, and the compile-line plumbing.
