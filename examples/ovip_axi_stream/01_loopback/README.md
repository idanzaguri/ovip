# Minimal AXI-Stream Loopback -- `ovip_axi_stream` hello-world

A single test that brings up one transmitter agent and one receiver agent on the same AXI-Stream interface, then sends four single-beat packets. A small subscriber on the receiver's monitor counts the packets and reports an error if anything but four arrive.

If everything works, the UVM Report Summary at the end shows:

```
UVM_ERROR :    0
UVM_FATAL :    0
```

That is the success criterion.

## Files

| | |
|---|---|
| `loopback_example.sv` | One file with: a small package (master sequence + counter subscriber + test class) and the `tb_top` module (clock, reset, interface, `run_test`). |
| `Makefile` | Compile and run with Modelsim/Questa, VCS, or Xcelium. |

## Running

```sh
make             # default: SIM=modelsim
```

## What to read next

- The `loopback_example.sv` source is tight (~150 lines) and reads top-to-bottom.
- For wiring received data into `ovip_mem` see [`../02_rx_to_mem/`](../02_rx_to_mem/).
- The "At a glance" matrix and "Integrating into your environment" section of [`verif/ovip_axi_stream/README.md`](../../../verif/ovip_axi_stream/README.md) cover the VIP's feature surface and the compile-line plumbing.
