# TODO

## Possible tasks

- [repl-undefined-errors.md](repl-undefined-errors.md): a typo in the
  REPL aborts the session; split interpret-mode reporting from batch
  abort.

## Resolved

- [seed-undefined-word-crash.md](seed-undefined-word-crash.md): fixed
  by `c2c7471`; compile-mode definitions abort with exit 2.

## Triaged

- `_float_*` in the Linux Sprouts: WIP, not important now; leave it
  alone.
- `x' }~fail does`: the code is correct at top level. `x'` is
  interpret-only, so the TODO is replaced by a comment.
- `}~ compile`: `}~self` builds a compiler that crashes because a
  `{::` entry is patched after the body. Keep the named tail call;
  the TODO is replaced by a comment.

## Decisions

- **Use the smarter x86 assembler in Seed?** Resolved: no. Keep the
  x86 Seeds on the explicit fixed long-branch macros (`rlabel`,
  `rlabel_s`, ...); the amd64/i386 Sprouts keep the automatic
  short/long selection (`label_offset`, `short_rlabel?`, `maybe_rs`).
  The decision is recorded in `seed/PORTING.md`.
