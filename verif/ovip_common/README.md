# ovip_common

Shared utilities for the OVIP family of verification IPs. Code that needs to
be reusable across multiple protocol VIPs (AXI, AHB, OCP, ...) lives here.

## Contents

| Package | Purpose |
|---|---|
| [`ovip_global_pkg`](ovip_global_pkg.sv) | Shared typedefs (e.g. `bytestream`, `bitstream`). |
| [`mem/ovip_mem_pkg`](mem/ovip_mem_pkg.sv) | Word-addressed associative-array memory model with byte-enable writes, bytestream API, and configurable word size. |

## Using

These packages are dependencies of the protocol VIPs in this repository. You
typically don't compile `ovip_common` standalone -- the per-VIP filelist
(e.g. [`../ovip_axi/ovip_axi.f`](../ovip_axi)) pulls in what it needs.

If you're integrating manually, the compile order is:

```
ovip_common/ovip_global_pkg.sv     ← first
ovip_common/mem/ovip_mem_pkg.sv    ← second
<your protocol VIP package>        ← imports the above
```

## License

Apache-2.0 -- see the repository root `LICENSE` file.
