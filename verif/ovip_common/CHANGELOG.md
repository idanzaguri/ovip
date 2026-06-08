# Changelog — ovip_common

All notable changes to the `ovip_common` shared utilities are documented in
this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this package follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] — 2026-06-08

### Changed (breaking)

- Renamed the shared public typedefs `bytestream` → `ovip_bytestream` and
  `bitstream` → `ovip_bitstream` in `ovip_global_pkg`, and updated the
  `ovip_mem` bytestream API signatures (`read_bytestream`/`write_bytestream`,
  `empty_bitstream`) to use them. Unprefixed type names in a wildcard-imported
  package collide with user/other-library symbols; the `ovip_`-prefix is
  collision-safe and consistent with the rest of OVIP. The function/member
  names themselves are unchanged — only the type names moved.

## [0.1.0] — 2026-05-31

Initial release. Extracted from `ovip_axi` so future OVIP family VIPs can
share the same utilities.

### Added

- `ovip_global_pkg` — shared typedefs (`bytestream`, `bitstream`).
- `ovip_mem_pkg` / `ovip_mem` — simple word-addressed associative-array
  memory model. Configurable word size, byte-enable writes, bytestream API,
  init-pattern or random fill on first access.
