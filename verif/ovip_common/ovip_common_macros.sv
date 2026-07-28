`ifndef OVIP_COMMON_MACROS__SV
`define OVIP_COMMON_MACROS__SV

// Family-wide fork idiom: run several checker/driver threads, kill them all
// as soon as the first one finishes. Used by every OVIP monitor/driver to
// multiplex reset handling against the long-running channel processes:
//
//     `OVIP_BEGIN_FIRST_OF
//         rst_monitor();
//         fork
//             checker_a();
//             checker_b();
//         join
//     `OVIP_END_FIRST_OF
//
// The OVIP_ prefix guarantees these cannot collide with (or be silently
// overridden by) same-named macros in a user environment. The per-VIP
// unprefixed BEGIN_FIRST_OF/END_FIRST_OF aliases are deprecated; new code
// should use the prefixed form.
`define OVIP_BEGIN_FIRST_OF fork begin fork
`define OVIP_END_FIRST_OF   join_any disable fork; end join

`endif
