# TODO

## Open tasks

- [seed-undefined-word-crash.md](seed-undefined-word-crash.md): an
  undefined word in a compile-mode definition makes the Seed segfault
  instead of reporting an error. The file records the root cause,
  constraints, attempted fixes, and the planned interpret/compile
  boundary fix.

## Decisions

- **Use the smarter x86 assembler in Seed?** Resolved: no. Keep the
  x86 Seeds on the explicit fixed long-branch macros (`rlabel`,
  `rlabel_s`, ...); the amd64/i386 Sprouts keep the automatic
  short/long selection (`label_offset`, `short_rlabel?`, `maybe_rs`).
  The decision is recorded in `seed/PORTING.md`.
