# Changelog -- ovip_common

All notable changes to the `ovip_common` shared utilities are documented in
this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this package follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] -- 2026-10-05

### Added

- `ovip_mem_space` in `mem/ovip_mem_space.sv`: a memory built from
  `ovip_mem` instances with an address map. The masters of a system see
  one address space; each slave sees its own linear space; the map
  between them is the system's. A region of the system space lands on
  one sub-memory at an offset (`add_region`), or is striped over several
  in round-robin chunks (`add_striped_region`, memory interleaving). The
  system-space `write_bytestream`, `read_bytestream`, `write`, `read` and
  `fill_random` split a range at every map boundary and gather the pieces;
  `resolve` and `covers` answer where a byte lives; two regions on one
  sub-memory with one base are an alias; a hole reports `MEM_SPACE/HOLE`
  and does nothing; `compare` checks a space against its shadow sub by
  sub. The slaves keep using their own `ovip_mem` untouched.
- `ovip_mem`: `num_lines`, `line_exists`, `get_lines`, and `compare`
  (a word that differs, or a line one side touched and the other did not,
  is a mismatch; the first `max_report` are reported as `MEM/COMPARE`).
- `ovip_mem` valid ranges: `add_valid_range`, `num_valid_ranges`,
  `is_valid`. With none set every address is valid, as before. Once any
  is set, a `write`, `read`, `write_bytestream` or `read_bytestream` that
  touches a byte outside all of them reports `MEM/OUT_OF_RANGE` and does
  nothing, so a slave's memory is bounded to what the slave owns and a
  transaction delivered to the wrong place is named when it arrives.
  `ovip_mem_space.add_region` and `add_striped_region` set them on the
  sub-memory from the region (on a striped region, the chunks each sub
  holds, the partial last one included).

### Fixed

- `ovip_mem::write_bytestream` counted the full words after the first,
  partial one as ceil((size - offset) / WORD_SIZE) - 1: one short for a
  large offset (the last-word branch then indexed past the word) and one
  too many for a small one (a zero byte was written past the stream). The
  count is now what is left after the first word, in whole words.
  `ovip_mem_test` checks every offset and size up to three words.

## [0.3.0] -- 2026-07-28

### Added

- `ovip_common_macros.sv` with `OVIP_BEGIN_FIRST_OF` / `OVIP_END_FIRST_OF` --
  the "run these threads, keep the first one that finishes, kill the rest" fork
  pattern that each VIP had been open-coding. Used by `ovip_axi` and `ovip_apb`.

## [0.2.0] -- 2026-06-08

### Changed (breaking)

- Renamed the shared public typedefs `bytestream` → `ovip_bytestream` and
  `bitstream` → `ovip_bitstream` in `ovip_global_pkg`, and updated the
  `ovip_mem` bytestream API signatures (`read_bytestream`/`write_bytestream`,
  `empty_bitstream`) to use them. Unprefixed type names in a wildcard-imported
  package collide with user/other-library symbols; the `ovip_`-prefix is
  collision-safe and consistent with the rest of OVIP. The function/member
  names themselves are unchanged -- only the type names moved.

## [0.1.0] -- 2026-05-31

Initial release. Extracted from `ovip_axi` so future OVIP family VIPs can
share the same utilities.

### Added

- `ovip_global_pkg` -- shared typedefs (`bytestream`, `bitstream`).
- `ovip_mem_pkg` / `ovip_mem` -- simple word-addressed associative-array
  memory model. Configurable word size, byte-enable writes, bytestream API,
  init-pattern or random fill on first access.
