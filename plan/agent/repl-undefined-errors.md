# REPL vs batch undefined-word errors

Status: possible task, not scheduled.

Date: 2026-11-08.

## Problem

The undefined-word fix (`c2c7471`) makes `xcompile_fail` in the Seed
and `undef` in the Sprout abort with exit 2. That is right for batch
compilation, but a typo in a REPL kills the session instead of
reporting the word and continuing.

## Suggested split

- Compile/definition bodies keep aborting. A bad word in a definition
  must still exit 2.
- Top-level `interpret` should print `word  undefined`, discard the
  rest of the current line, and continue with the next input line.
- Use a separate `repl_undef` handler for interpret mode; do not call
  the aborting `undef` there.
- Optional: set a `failed` flag on a top-level error, continue, and
  exit nonzero at EOF/`bye` for batch. Interactive use clears or
  ignores the flag.
- Optional: an explicit `-i`/`--interactive` or `repl` mode. Avoid
  `isatty`, which is not portable to the z80 or raw targets.

## Constraint

The existing negative test, `undefined_word_check`, covers a bad word
inside a definition body and expects exit 2 with one diagnostic. The
REPL change must not weaken that path; it only changes the top-level
`interpret`/`seedl`/`sproutl` behavior.

## Files

- `seed/src/seed-linux-{amd64,i386,aarch64}.seed`: `interpret`,
  `seedl`, `xcompile_fail`.
- `sprout/src/sprout-linux-{amd64,i386,aarch64}.seed`: `interpret`,
  `sproutl`, host and target `undef`.
- `plan/agent/TODO.md`: index.
