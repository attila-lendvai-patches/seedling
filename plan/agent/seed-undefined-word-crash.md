# Seed: undefined word in compile mode segfaults

Status: open. Investigation done; fix not implemented. Use `abort`
for fatal reporting; `EXIT_CODE` was rolled back.

Date: 2026-11-08.

## Symptom

An undefined word inside a target definition can make the Seed segfault
instead of reporting an error. It is specific to a definition of a
compile-mode behavior: a bad word in `}}` crashes, while a bad word in
`literal`, `{{`, or `stdok` is reported as ` fail` and compilation
continues.

The Sprout reports the same kind of error cleanly:

```
xrel_size undefined
```

The Seed dies with SIGSEGV.

## Reproducer

Not reasonably short or self-contained, so no test was committed. Generate
the bad source from the amd64 Seed source:

```sh
sed '0,/swap 4 - d!/s//swap nosuchword - d!/' \
    seed/src/seed-linux-amd64.seed > /tmp/bad.seed
./seed/bin/seed-linux-amd64 < /tmp/bad.seed > /tmp/bad.out
```

Result: exit 139, empty output.

A later bad word is handled cleanly:

```sh
# replace the body of stdok instead
sed 's/{: stdok$/{: stdok\nnosuchword/' ...
```

Result: ` fail` followed by an ELF image, exit 0.

## Root cause

1. `{:` starts a target definition and calls `compile`.
2. An undefined token makes `compile` fail.
3. `{:`'s `'id|` handler catches that failure, exactly as it catches
   the normal `}` terminator, and returns.
4. `interpret` resumes at the rest of the same line in interpret mode.
   In the `}}` case the rest is `- d!`, so `d!` executes with the
   compiler's leftover data stack.

GDB at the crash:

```
0x10615: mov %eax,(%rcx)     # d! 32-bit store
rcx = 0xffffffffffff0af2     # bogus target address
```

The word is `d!` (entry 0x105f0, token 0x1060b); the return address is
inside `handle` (0x10bcb), i.e. the token was executed by `interpret`,
not compiled. `PAD` contained the tail of the undefined token (`"ord"`),
confirming that the input pointer was left mid-word.

## Constraints discovered

- Host geometry constants cannot be used inside target word bodies. A
  bare `xrel_size`/`xinst_size` in `}}` produces `xrel_size undefined`
  (Sprout) or a Seed crash.
- `[ foo xliteral ]` is the right idiom elsewhere, but is unavailable in
  `{{`/`}}`: `[` is defined later and depends on
  `interpret` -> `"` -> `quotate` -> `{{`.
- The compiler's `{:` is also used for Part I host macros. Aborting on
  every token that is not `}` breaks self-hosting with `jc_s undefined`,
  because host-only words such as `jc_s` legitimately appear there.
- The normal `}` termination is itself a failure; the `'id|` handler is
  what makes it a clean end of definition. It cannot simply be replaced
  by an abort handler.

## Attempts and results

- `[ xrel_size xliteral ]` in `}}`: compiles a truncated image
  (` fail` + ELF); `[` is not available at that point.
- Bare host constant / bogus word in `}}`: Seed SIGSEGV; Sprout prints
  `undefined`, exit 0.
- `compile` fallback with `bye` / `undef`: not reached; the failure is
  caught by `{:`'s terminator handler instead.
- `checkfail` word using `pad c@ 7D =`: correct idea, but self-hosting
  aborts on Part I host macros (`jc_s undefined`).
- `checkfail` that also searches the host vocabulary (`SEED @ search`):
  the existing bootstrap crashes while compiling the check word.
- Flushing the rest of the line after `{:`:
  `[ TIB_BUF xliteral ] [ TIB_BUF_LEN xliteral ] + tib !`.
  This self-hosts byte-identically (gen1/gen2 match), but does not fix
  the `}}` crash because `d!` executes before `{:` returns.
- Startup failure-frame layout: checked and correct. The saved DSP is
  at `ERR_SP + 3`; `push` uses `rsp`, so the subtraction yields the
  frame base. This is not the cause.

## Current state

- `abort` exists in every port and exits with code 2. `seedl` already
  calls it on a failed line; `interpret`'s undefined-word path still
  calls `bye`.
- Oversized-image guards are in place, and the test harness now checks
  compiler output size and format.
- z80-built amd64/i386/aarch64 Seed images are executed for a
  self-bootstrap, not only compared.
- `EXIT_CODE` was rolled back; do not reintroduce it.

## Next step

Fix at the `interpret`/`compile` boundary rather than inside `{:`:

- distinguish a compile-mode failure from the normal `}` terminator;
- on a real failure, report it with `abort` (exit 2) and either discard
  the remainder of the definition (resync to its closing `}`) or abort
  the compilation immediately;
- keep the Part I host-macro path working;
- make the diagnostic include the failing word where possible.

Possible mechanism: a flag/variable set by `{:` on a non-terminator
failure, checked by `interpret`, or a resync loop in `interpret` that
consumes tokens through the definition's closing `}`.

## Validation

- Valid sources must still self-host byte-for-byte for at least two
  generations.
- All eight Seed/Sprout sources must still compile byte-identically
  (except for the intended compiler change and rebuilt bootstraps).
- z80 roots must still match; the z80-built images are now executed as
  well as compared.
- Rebuild every committed `seed/bin/seed-*` in the same series.
- Keep the harness output size/format check passing.
- The generated bad source must print an error, exit 2 via `abort`, and
  must not emit a truncated ELF or die from a signal.

## Open question

Is a clean abort acceptable for the Seed, or must it continue after an
undefined word like the Sprout? The Seed's `seedl` already aborts on a
failed line, so aborting is consistent with the current Seed behaviour
and simpler.
