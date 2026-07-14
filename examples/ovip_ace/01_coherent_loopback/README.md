# ovip_ace: coherent loopback

Smallest runnable example for the ACE VIP (full ACE profile).

> **:rotating_light: ovip_ace is AI-generated and NOT functionally verified.**
> See [`verif/ovip_ace/README.md`](../../../verif/ovip_ace/README.md).

## What it does

- Instantiates a master ACE agent and a slave/interconnect ACE agent on one
  `ovip_ace_agent_if` (no DUT -- pure VIP loopback).
- The master issues 4 `WriteUnique` then 4 `ReadOnce` transactions, carrying
  AxDOMAIN (Inner Shareable) and AxSNOOP, backed by `ovip_mem` loopback.
- The interconnect side injects one `ReadShared` snoop; the master is expected
  to answer on CR with the default "cache miss" response.

## Run

```sh
make SIM=modelsim     # or SIM=vcs / SIM=xcelium
make clean
```

## What is (and is not) confirmed

- **Confirmed:** the read/write path runs to `UVM_ERROR : 0`, and both monitors
  reconstruct the transactions with the correct ACE decode (`ReadOnce`,
  `WriteUnique`, `DOMAIN=INNER_SHAREABLE`).
- **NOT confirmed:** the injected snoop does **not** currently produce an
  observed snoop transaction (no `ACE_MON/SNOOP` line appears). The AC/CR/CD
  path is unverified -- debugging it is the top task in
  [`verif/ovip_ace/CONTRIBUTING.md`](../../../verif/ovip_ace/CONTRIBUTING.md).

## Note on the dummy AXI interface

`tb_top` instantiates an unused `ovip_axi_agent_if`. Because ovip_ace is built on
ovip_axi, the AXI package (with its plain `virtual ovip_axi_agent_if` handles) is
always elaborated; Questa needs at least one instance of that interface type to
exist to resolve the virtual-interface type, even though this pure-ACE testbench
never drives it.
