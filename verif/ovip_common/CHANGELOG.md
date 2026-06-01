# Changelog — ovip_common

All notable changes to the `ovip_common` shared utilities are documented in
this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this package follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-05-31

Initial release. Extracted from `ovip_axi` so future OVIP family VIPs can
share the same utilities.

### Added

- `ovip_global_pkg` — shared typedefs (`bytestream`, `bitstream`).
- `ovip_mem_pkg` / `ovip_mem` — simple word-addressed associative-array
  memory model. Configurable word size, byte-enable writes, bytestream API,
  init-pattern or random fill on first access.
