# AArch64 call/return convention: possible experiment

Status: idea / possible task, not scheduled.

Context: the AArch64 Seed and Sprout ports,
`seed/src/seed-linux-aarch64.seed` and
`sprout/src/sprout-linux-aarch64.seed`.

## Question

Does the port use the usual AArch64 (AAPCS64) call and return
conventions? Why is `ret,` 8 bytes long? Can it be 4 bytes by
using `bl`/`ret`?

## Current design (a deliberate custom ABI)

The port does not follow AAPCS64 internally; only the Linux syscall
ABI at `svc` is followed. The header of the AArch64 Seed states:

- `X0` = TOS
- `X19` = data stack pointer
- `X29` = shadow call stack (the Seed return stack)
- `SP` = hardware stack pointer, kept 16-byte aligned
- `X30` = unused

A call is emitted as:

```text
mov  x16, <return address>     ; 8 bytes (movz + movk)
str  x16, [x29, #-8]!          ; 4 bytes
b    <target>                  ; 4 bytes
```

so `xcall_size` is 16.

A return is:

```text
ldr  x16, [x29], #8            ; 4 bytes
br   x16                       ; 4 bytes
```

so `ret,` is 8 bytes.

The `push`/`pop` macros use `X29`, not `SP`:

```forth
{: push ( reg -- ) 8FA0 or F81F x32, }   \ str xN,[x29,#-8]!
{: pop  ( reg -- ) 87A0 or F840 x32, }   \ ldr xN,[x29],#8
```

At startup the code does `X29 = SP` and never moves the hardware
`SP`, so the kernel always sees a 16-byte-aligned `SP`.

`ret,` is a target-side emitter, not the ARM `ret` instruction. It
emits the two instructions above.

## Why 8 bytes

AArch64 has no "pop and branch" instruction. `ret` and `ret xN`
only branch to a register; they do not pop. With a stack-based
return, the minimum is a load plus a branch, 8 bytes.

The 4-byte ARM `ret` (`D65F03C0`) branches to `X30`, which this ABI
leaves unused.

## The usual ABI alternative

Using AAPCS64-style `bl` (4 bytes) and `ret` (4 bytes) would make
`ret,` 4 bytes and a call site 4 bytes instead of 16. But it is an
ABI redesign, not a local size tweak:

1. `X30` is caller-saved in AAPCS64. Every helper that calls another
   helper must spill and restore `X30`; non-leaf words need a
   prologue/epilogue. The current contract says `X30` is unused, so
   no helper saves it.
2. `handle`, `|`, `cut`, and `}~fail` use `X29` as the failure
   frame and jump to handlers with `br`. If returns use `X30`, the
   failure restore would not restore `X30`; a handler ending in
   `ret,` could return to a stale address. The frame would need a
   saved `X30` slot, or handlers would have to be tail calls.
3. `{{`/`}}` push and pop the quotation body address on `X29` as
   data. This can coexist with `X30` calls, but the model becomes
   mixed.
4. Tail calls (`}~`, `}~self`, `tailcomp`, `endcomp`) are branches.
   With `X30` calls, a tail call must leave `X30` as the caller's
   return address, which requires every non-leaf target to preserve
   it.
5. It changes `xcall_size`, `xquote_open_size`, the `create` stub
   size and payload offset, and every emitted binary. AArch64 would
   become unlike the other ports, which use stack returns.

## Possible work, if pursued

1. Prototype only on AArch64, in a branch:
   - `call` = `bl`; `ret,` = `D65F03C0`; `callcomp` = `bl`;
     `tailcomp` = `b`; `xcall_size` and `xquote_open_size` = 4.
   - Save/restore `X30` in every helper that calls; add a saved
     `X30` slot to the failure frame and adjust
     `handle`/`}~fail`/`|`/`cut`.
   - Decide how `{{`/`}}` and `}~self` interact with `X30`.
2. Measure image size, code size per definition, self-host
   fixpoint, cross-compilation from z80/amd64/i386, ELF validity,
   and runtime probes.
3. Compare with the current ABI and document the tradeoff in
   `seed/PORTING.md` and the source header.
4. If adopted, update the geometry constants, stub sizes, and
   rebuild all committed binaries. If not, record the decision and
   keep the current comment.

## Recommendation

Keep the current stack ABI for now. Eight bytes is the minimum for
a pop-and-branch return, and the current model keeps calls,
quotations, and failure frames on one return stack. Revisit only if
image size becomes a priority and the `X30`/failure-frame redesign
is justified.

## References

- `seed/src/seed-linux-aarch64.seed`: header contract;
  `push`/`pop`, `call`, `ret`, `ret,`, `callcomp`, `tailcomp`,
  `handle`, `}~fail`, startup `X29 = SP`.
- `seed/PORTING.md`: target ABI versus syscall ABI;
  `xcall_size`/`xquote_open_size`.
- `AGENTS.md`: a port defines its own internal ABI; the platform
  ABI is followed only at syscalls.
