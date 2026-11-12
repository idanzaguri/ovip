# ovip_ace: coherent loopback

Smallest runnable example for the ACE VIP (full ACE profile).

> **:rotating_light: ovip_ace is AI-generated and NOT functionally verified.**
> See [`verif/ovip_ace/README.md`](../../../verif/ovip_ace/README.md).

## What it does

- Instantiates a master ACE agent and a slave/interconnect ACE agent on one
  `ovip_ace_agent_if` (no DUT -- pure VIP loopback).
- The master issues 4 `WriteUnique` then 4 `ReadOnce` transactions, carrying
  AxDOMAIN (Inner Shareable) and AxSNOOP, backed by `ovip_mem` loopback. The
  sequence waits for the write responses before it reads, and reports a
  `uvm_error` if a read does not return the data that was written.
- The interconnect side injects one `ReadShared` snoop; the master answers on
  CR with the default "cache miss" response. An `ovip_ace_scoreboard` on the
  master monitor's `snoop_analysis_port` counts the snoops, and the test
  reports a `uvm_error` if the count is not 1.

## Run

```sh
make SIM=modelsim     # or SIM=vcs / SIM=xcelium
make clean
```

## What is (and is not) confirmed

- **Confirmed:** the read/write path runs to `UVM_ERROR : 0`, each read
  returns the written data, and both monitors reconstruct the transactions
  with the correct ACE decode (`ReadOnce`, `WriteUnique`,
  `DOMAIN=INNER_SHAREABLE`).
- **Confirmed:** the injected snoop completes with the default response
  (CRRESP = 0, no data), and both monitors report it with an `ACE_MON/SNOOP`
  line.
- **Confirmed:** every read gets its RACK and every write its WACK: the
  monitors report an acknowledge that is still owed at the end of the test.
- **NOT confirmed:** a snoop response with data on CD, and everything else
  that the example does not drive. See
  [`verif/ovip_ace/CONTRIBUTING.md`](../../../verif/ovip_ace/CONTRIBUTING.md).

## Note on the dummy AXI interface

`tb_top` instantiates an unused `ovip_axi_agent_if`. Because ovip_ace is built on
ovip_axi, the AXI package (with its plain `virtual ovip_axi_agent_if` handles) is
always elaborated; Questa needs at least one instance of that interface type to
exist to resolve the virtual-interface type, even though this pure-ACE testbench
never drives it.
