# OVIP

Pronounced **"oh-veep"**. Think of it as "open VIPs" -- a family of
openly-licensed UVM verification IPs for common interconnect protocols.

Right now that's **AXI** (AXI3, AXI4, AXI4-Lite), **AXI-Stream**
(AXI4-Stream, AXI5-Stream), and **APB** (APB3, APB4), but the plan is more --
AHB next, then OCP, whatever the open hardware community ends up needing. There isn't a lot in the way of well-maintained, openly-licensed,
multi-simulator UVM VIPs out there, and I think there should be.

Same shape for every VIP added here:

- Production-grade Modelsim/Questa, VCS, and Xcelium portability. Verilator
  runs the examples and the APB and AXI test suites too; see
  [Running on Verilator](#running-on-verilator) for the requirements.
- One compile filelist, one env var -- drops into your flow in two lines.
- Whatever's genuinely shared between VIPs (memory models, type helpers,
  sequence base classes) lives in [`verif/ovip_common/`](verif/ovip_common/)
  so the next VIP doesn't reinvent it.

## What's here

| | |
|---|---|
| [`verif/ovip_axi/`](verif/ovip_axi/) | The AXI verification IP -- master + slave agents, monitor, configurable widths, sequence library. Start with the [VIP README](verif/ovip_axi/README.md). |
| [`verif/ovip_axi_stream/`](verif/ovip_axi_stream/) | The AXI-Stream verification IP -- transmitter + receiver agents, monitor with the full set of spec-rule checks, scoreboard, sequence library. Covers AXI4-Stream and AXI5-Stream. Start with the [VIP README](verif/ovip_axi_stream/README.md). |
| [`verif/ovip_apb/`](verif/ovip_apb/) | The APB verification IP -- requester + completer agents, reactive memory-backed completer, monitor with the full set of spec-rule checks, scoreboard, transaction logging, sequence library. Covers APB3 and APB4. Start with the [VIP README](verif/ovip_apb/README.md). |
| [`verif/ovip_ace/`](verif/ovip_ace/) | **:warning: EXPERIMENTAL, AI-GENERATED, UNVERIFIED.** The ACE / ACE-Lite verification IP, built as an extension of ovip_axi. Compiles and runs basic coherent traffic; the snoop channels and protocol checks are not yet confirmed. Read the [VIP README](verif/ovip_ace/README.md) banner before using. |
| [`verif/ovip_common/`](verif/ovip_common/) | Shared utilities -- memory model, common type helpers. Imported by every VIP in the family. |
| [`examples/ovip_axi/01_minimal_loopback/`](examples/ovip_axi/01_minimal_loopback/) | The smallest runnable example. Clone, `make`, watch `UVM_ERROR : 0`. |
| [`examples/ovip_axi/02_out_of_order_reads/`](examples/ovip_axi/02_out_of_order_reads/) | Slave returns responses in reverse-issued order (3, 2, 1, 0). Demonstrates `rd_out_of_order_depth`, `rd_scheduling_alg`, and per-transaction `data_delay`. |
| [`examples/ovip_axi/03_axi3_write_interleaving/`](examples/ovip_axi/03_axi3_write_interleaving/) | Two AXI3 writes whose W beats interleave on the bus; a live watcher prints `wid` per beat. Demonstrates `wr_interleave_depth` and the AXI3-only `wid` field. |
| [`examples/ovip_axi/04_response_timing/`](examples/ovip_axi/04_response_timing/) | Slave inserts a configurable `bresp_delay` after WLAST and a per-beat `data_delay[]` staircase on reads; channel watcher logs `t=…` on every handshake. |
| [`examples/ovip_axi_stream/01_loopback/`](examples/ovip_axi_stream/01_loopback/) | Smallest AXI-Stream hello-world: transmitter + receiver on the same interface, 4 single-beat packets, success when `UVM_ERROR : 0`. |
| [`examples/ovip_axi_stream/02_rx_to_mem/`](examples/ovip_axi_stream/02_rx_to_mem/) | Receiver-side subscriber pulls `trans.get_data_bytes()` (null/position bytes filtered out per the spec) and writes the resulting byte stream into `ovip_mem`. Round-trip verified by reading the mem back. |
| [`examples/ovip_apb/01_loopback/`](examples/ovip_apb/01_loopback/) | Smallest APB hello-world: requester + memory-backed completer on the same interface, 4 writes + self-checking read-backs, success when `UVM_ERROR : 0`. |
| [`examples/ovip_ace/01_coherent_loopback/`](examples/ovip_ace/01_coherent_loopback/) | **:warning: AI-generated, unverified VIP.** Master + interconnect ACE agents; coherent writes/reads with AxDOMAIN/AxSNOOP run to `UVM_ERROR : 0`. The snoop path is not yet confirmed. |

## Quickstart

You need a UVM-1.2-capable simulator (Modelsim/Questa, VCS, or Xcelium), or Verilator with a UVM source tree (see [Running on Verilator](#running-on-verilator)).

```sh
cd examples/ovip_axi/01_minimal_loopback
make SIM=modelsim       # or SIM=vcs / SIM=xcelium
```

That's it -- the loopback runs and prints the UVM Report Summary.

> **Free-simulator path:** the loopback example has been validated on **Modelsim** (Intel/Altera FPGA Starter Edition is free). The VCS and Xcelium make targets are wired up but require a commercial license to actually run.

## Running on Verilator

Verilator compiles and runs the VIPs. Validated on 2026-10-25:

| What | Verilator | Result |
|---|---|---|
| `examples/ovip_apb/01_loopback`, `examples/ovip_axi_stream/01_loopback` | 5.052 | `UVM_ERROR : 0` |
| `examples/ovip_axi/01_minimal_loopback` | git main after 5.052 | `UVM_ERROR : 0` (5.052 miscompiles a parameterized class with a virtual-interface type parameter; fixed upstream after 5.052) |
| `ovip_apb_testbench` (7 tests), `ovip_axi_testbench` (52 tests) in [ovip-dev](https://github.com/idanzaguri/ovip-dev) | git main after 5.052 | all pass, except the X-injection test: Verilator is 2-state |

What you need:

- **A UVM source tree.** Verilator ships no UVM. `UVM_HOME` below is a UVM 1.2
  source tree (the Accellera `uvm-1.2` release, or the copy your simulator
  installs). [verilator/uvm](https://github.com/verilator/uvm) (UVM 2020-3.1)
  also compiles and runs the APB example.
- **`--timing`** and `+define+UVM_NO_DPI` when you use only the VIPs. Tests
  that call `uvm_hdl_force` need `--vpi`, UVM's `dpi/uvm_dpi.cc`, and the
  forced signals marked `forceable` in a Verilator config file; UVM 1.2 has no
  Verilator backend for `uvm_hdl_*`, the one from verilator/uvm
  (`uvm_hdl_verilator.c`) drops in.
- **An SMT solver** on the `PATH` or in `VERILATOR_SOLVER` (z3, cvc5, yices-smt2
  or bitwuzla). Verilator calls it at run time for every `randomize()` with
  constraints; without it `randomize()` returns 0.

```sh
verilator --binary --timing -j 8 -Wno-fatal -Wno-lint -Wno-style \
    +define+UVM_NO_DPI +incdir+$UVM_HOME/src $UVM_HOME/src/uvm_pkg.sv \
    -f $OVIP_ROOT/verif/ovip_apb/ovip_apb.f \
    +incdir+examples/ovip_apb/01_loopback examples/ovip_apb/01_loopback/loopback_example.sv \
    --top-module tb_top -o Vtb_top
./obj_dir/Vtb_top +UVM_NO_RELNOTES
```

Build time is dominated by UVM: about 3.5 minutes on 12 cores per
testbench. One build serves every test of a testbench through
`+UVM_TESTNAME`. Limits: Verilator is 2-state, so X/Z injection and the
monitors' X/Z checks have no effect, and the VIP code compiles with
`-Wno-lint -Wno-style` (width and unused-signal warnings remain).

## Integrating a VIP into your testbench

Each VIP ships a single compile filelist. For AXI, it's [`verif/ovip_axi/ovip_axi.f`](verif/ovip_axi/ovip_axi.f).
Set one env var, add one `-f` flag to your compile, and you're done:

```sh
export OVIP_ROOT=/path/to/this/repo
vlog -sv -mfcu -f $OVIP_ROOT/verif/ovip_axi/ovip_axi.f   # Modelsim/Questa
vcs  -sverilog -ntb_opts uvm-1.2 -f $OVIP_ROOT/verif/ovip_axi/ovip_axi.f   # VCS
xrun -uvm -uvmhome CDNS-1.2 -sv  -f $OVIP_ROOT/verif/ovip_axi/ovip_axi.f   # Xcelium
verilator --binary --timing +define+UVM_NO_DPI +incdir+$UVM_HOME/src $UVM_HOME/src/uvm_pkg.sv -f $OVIP_ROOT/verif/ovip_axi/ovip_axi.f <your files> --top-module <top>   # Verilator
```

Full details in [`verif/ovip_axi/README.md`](verif/ovip_axi/README.md).

## Verification environment

The testbench, regression suites, runner scripts, and per-VIP self-checking test sets live in the companion repo [`idanzaguri/ovip-dev`](https://github.com/idanzaguri/ovip-dev). Look there if you want to see how the VIPs are exercised, or want the runner stack as a reference for your own flow.

## Contributing

Issues and PRs welcome. The "wanted features" list in each VIP's
`CONTRIBUTING.md` (e.g. [`verif/ovip_axi/CONTRIBUTING.md`](verif/ovip_axi/CONTRIBUTING.md))
is a good place to find things that aren't done yet.

## License

Apache-2.0 -- see [LICENSE](LICENSE). Inbound contributions are under the same
terms.
