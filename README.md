# OVIP

Pronounced **"oh-veep"**. Think of it as "open VIPs" — a family of
openly-licensed UVM verification IPs for common interconnect protocols.

Right now that's just **AXI** (AXI3, AXI4, AXI4-Lite), but the plan is more —
AHB next, then APB, OCP, whatever the open hardware community ends up
needing. There isn't a lot in the way of well-maintained, openly-licensed,
multi-simulator UVM VIPs out there, and I think there should be.

Same shape for every VIP added here:

- Production-grade Modelsim/Questa, VCS, and Xcelium portability.
- One compile filelist, one env var — drops into your flow in two lines.
- Whatever's genuinely shared between VIPs (memory models, type helpers,
  sequence base classes) lives in [`verif/ovip_common/`](verif/ovip_common/)
  so the next VIP doesn't reinvent it.

## What's here

| | |
|---|---|
| [`verif/ovip_axi/`](verif/ovip_axi/) | The AXI verification IP — master + slave agents, monitor, configurable widths, sequence library. Start with the [VIP README](verif/ovip_axi/README.md). |
| [`verif/ovip_common/`](verif/ovip_common/) | Shared utilities — memory model, common type helpers. Imported by every VIP in the family. |
| [`examples/01_minimal_loopback/`](examples/01_minimal_loopback/) | The smallest runnable example. Clone, `make`, watch `UVM_ERROR : 0`. |
| [`examples/02_out_of_order_reads/`](examples/02_out_of_order_reads/) | Slave returns responses in reverse-issued order (3, 2, 1, 0). Demonstrates `rd_out_of_order_depth`, `rd_scheduling_alg`, and per-transaction `data_delay`. |
| [`examples/03_axi3_write_interleaving/`](examples/03_axi3_write_interleaving/) | Two AXI3 writes whose W beats interleave on the bus; a live watcher prints `wid` per beat. Demonstrates `wr_interleave_depth` and the AXI3-only `wid` field. |
| [`examples/04_response_timing/`](examples/04_response_timing/) | Slave inserts a configurable `bresp_delay` after WLAST and a per-beat `data_delay[]` staircase on reads; channel watcher logs `t=…` on every handshake. |

## Quickstart

You need a UVM-1.2-capable simulator (Modelsim/Questa, VCS, or Xcelium).

```sh
cd examples/01_minimal_loopback
make SIM=modelsim       # or SIM=vcs / SIM=xcelium
```

That's it — the loopback runs and prints the UVM Report Summary.

> **Free-simulator path:** the loopback example has been validated on **Modelsim** (Intel/Altera FPGA Starter Edition is free). The VCS and Xcelium make targets are wired up but require a commercial license to actually run.

## Integrating a VIP into your testbench

Each VIP ships a single compile filelist. For AXI, it's [`verif/ovip_axi/ovip_axi.f`](verif/ovip_axi/ovip_axi.f).
Set one env var, add one `-f` flag to your compile, and you're done:

```sh
export OVIP_ROOT=/path/to/this/repo
vlog -sv -mfcu -f $OVIP_ROOT/verif/ovip_axi/ovip_axi.f   # Modelsim/Questa
vcs  -sverilog -ntb_opts uvm-1.2 -f $OVIP_ROOT/verif/ovip_axi/ovip_axi.f   # VCS
xrun -uvm -uvmhome CDNS-1.2 -sv  -f $OVIP_ROOT/verif/ovip_axi/ovip_axi.f   # Xcelium
```

Full details in [`verif/ovip_axi/README.md`](verif/ovip_axi/README.md).

## Verification environment

The testbench, regression suites, runner scripts, and per-VIP self-checking test sets live in the companion repo [`idanzaguri/ovip-dev`](https://github.com/idanzaguri/ovip-dev). Look there if you want to see how the VIPs are exercised, or want the runner stack as a reference for your own flow.

## Contributing

Issues and PRs welcome. The "wanted features" list in each VIP's
`CONTRIBUTING.md` (e.g. [`verif/ovip_axi/CONTRIBUTING.md`](verif/ovip_axi/CONTRIBUTING.md))
is a good place to find things that aren't done yet.

## License

Apache-2.0 — see [LICENSE](LICENSE). Inbound contributions are under the same
terms.
