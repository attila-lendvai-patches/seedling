# Porting a Seed

This is a practical checklist for adding a Seed port, not a language
tutorial. Read `README.md`, `RATIONALE.md`, `seed/README.md`,
`sprout/EXECUTION.md`, and `syntax/PRINCIPLES.md` first. Start from the
closest existing port and keep target-specific code in `[port]` blocks.

## What "done" means

A port is not finished because it builds on amd64. It is finished when:

1. a 16-bit host compiles it;
2. every capable Seed/Sprout produces byte-identical output for it;
3. it self-hosts for at least two generations;
4. every emitted ELF passes `eu-elflint -q`;
5. the z80 roots still match: z80 self-host and z80 -> amd64,
   z80 -> i386, z80 -> aarch64, and all four Sprout sources.

Sprout follows the same rules, but a Seed port can land first.

## Start from the closest port

| port | source | notes |
| --- | --- | --- |
| amd64 | `seed/src/seed-linux-amd64.seed` | trusted bootstrap |
| i386 | `seed/src/seed-linux-i386.seed` | 32-bit x86 |
| aarch64 | `seed/src/seed-linux-aarch64.seed` | 64-bit cells, 4-byte code alignment |
| z80 | `seed/src/seed-z80-fictional.seed` | 16-bit threaded code, raw binary |

Copy the nearest source, then change only what the target requires.
Keep shared logic common and describe the *target* geometry; never
derive it from the compiling host.

## The z80 model

The z80 is not a conventional token/comp port. Cells are 16-bit, code
is threaded, and a word entry is the link cell, the zero-terminated
name, then the threaded code or payload. `CREATE` appends a call to
`DAT,`; `NEXT` is `JP (IX)`.

The ABI is: `BC` is TOS, `DE` is the data stack pointer and grows up
from `STK_BOT`, `SP` is the return stack and grows down from
`STK_TOP`, `IX` is the threaded-code pointer, and `A`/`F` are scratch
with `CF` as the Seed carry flag. The data and return stacks share
`E000..FF00`; keep them apart.

The image is a raw binary loaded at 0. The heap grows up from
`DICTIONARY` to `STK_BOT`, so keep the largest image below `STK_BOT`;
the AArch64 Sprout needed `STK_BOT` raised to `E000`. Port 0 is the
input and output channel; there is no ELF segment.

## Source shape

A Seed source starts with `OUTPUT` on the first line. The usual order is:

1. requirements, assembler scope, TOS/register roles;
2. `[port]` image base and target geometry;
3. Part I: host-side assembler macros (`W,`, `D,`, `A,`, opcode
   emitters, labels, calls, literals);
4. the cross-compiler (`XCOMPILE`, `XCOMPS`, `XCREATE`, `X'`, `DOES`);
5. `CREATE ELF`, the ELF header, and the initial machine code;
6. Part II: target-side words (`LITERAL`, `{{`, `}}`, `RET,`,
   `CREATE`, the seed loop);
7. the final `OUTPUT` path.

Part I runs while the source is being compiled. Part II is the target
program that will compile the next generation. Do not use a target word
at compile time unless it is also defined as a host word.

## Host and target names

The source is read twice. In Part I the names below are host words that
build the target image. In Part II the same name may be a target word
in the image. The later definition shadows the earlier one for the
rest of the source.

| name | Part I, host | Part II, target |
| --- | --- | --- |
| `{` | emit via `XCOMPILE` | build at `HERE` |
| `{:`, `{::` | create a target entry | create a runtime entry |
| `CONSTANT` | emit a target constant | create a runtime constant |
| `EFFECT` | emit a target effect | create a runtime effect |
| `DOES` | patch the compile field | set compile behavior |
| `IMMEDIATE` | set the compile field | set compile behavior |
| `POSTPONE` | emit a forward entry | postpone a definition |
| `NATIVE` | emit a target entry | host only |
| `LITERAL` | use `XLITERAL` | emit a target literal |
| `{{`, `}}` | use `X{{`, `X}}` | emit and patch |

Read the definitions in order: a name is the host version only until
its target definition is executed. The `X` prefix marks host-side
cross-compiler words; `_` marks hidden target words.

## Target geometry

Put a geometry block in `[port]` and make every value true for the
target, not for the host:

```forth
xcell_bits  xcelllog  xcell  xcell1-  xcell_mask
xcells  xalign  xcell+
xcode_align_bytes     \ only where instructions need alignment
xinst_size            \ one target instruction word
xcall_size            \ host/xcompile call site
xquote_open_size      \ host quotation opener
xjump_size            \ forward jump placeholder, where it differs
xliteral_size         \ bytes emitted by the target literal
xret_size             \ bytes emitted by ret,
xstub_size            \ xliteral_size xret_size +, the create payload
xrel_size
xword_comp  xname_from_token
```

Typical definitions (AArch64):

```forth
40 constant xcell_bits          \ 64 bits
3  constant xcelllog            \ log2(8)
xcell_bits 3 rshift constant xcell
xcell 1 - constant xcell1-
xcell1- invert constant xcell_mask
{: xcells  xcelllog lshift }
{: xalign  xcell1- + xcell_mask and }
{: xcell+  xcell + }

4 constant xcode_align_bytes
4 constant xinst_size
xcell 2 * constant xword_comp
xcell 2 * constant xname_from_token
10 constant xcall_size
10 constant xquote_open_size
18 constant xliteral_size
8 constant xret_size
xliteral_size xret_size + constant xstub_size
4 constant xrel_size
```

`XCELL` is the target cell size in bytes. `XALIGN` aligns an address
to a target cell. `XCODE_ALIGN_BYTES` is the *instruction* boundary,
which may be different from the cell size.

### Compile-time substitution

Target code cannot read a host constant directly: a bare name is
compiled as a target call. Put the host constant in brackets to
evaluate it while compiling and emit it as a target literal:

```forth
here [ xstub_size xliteral ] +
```

The bracket runs at compile time and `XLITERAL` emits the same bytes as
a numeric literal. The image does not grow, and the source names the
invariant instead of repeating a number. Prefer this to a target-side
constant word, which would add a runtime dictionary entry and image
bytes.

`[` is a target word and must be defined before the words that use it.
The interpreter is therefore defined before `CREATE`. The quotation
emitters `{{` and `}}` still precede `[`, so their size literals stay
numeric with a comment naming `XQUOTE_OPEN_SIZE` or `XREL_SIZE`. Do not
move the interpreter above the quotations: it uses `"`, which uses
`QUOTATE`, which uses `{{`; moving the target number parser that far
also shadows the host parser used for literals.

The other bracket user is the target `LINK` alignment. It has only
one caller, `CREATE`, so its definition moves just before `CREATE`,
after `[`. It computes the padding as the aligned address minus the
start, matching the host `XALIGN` definition:

```forth
here dup
[ xcell1- xliteral ] +
[ xcell1- xliteral ] invert and
swap - allot
```

`DUP` keeps the start address, so the padding does not depend on a
second `HERE` read and cannot be disturbed by an `ALLOT` between the
reads. `XCELL1-` fits in 16 bits, and the target `INVERT` builds the
full align-up mask, so no wide host value is emitted. `XCELL_MASK`
remains the host `XALIGN` mask; do not inject it into target code.

### Code alignment

Where instructions need alignment, do not repeat the size in the
target words. Emit `XCODE_ALIGN_BYTES` as a target constant and derive
the two target-side words from it:

```forth
native xcode_align_bytes
xcode_align_bytes xliteral
ret

{: xcode_align_addr
xcode_align_bytes + 1-
xcode_align_bytes 1- invert and }

{: xcode_align
here xcode_align_addr here - allot }
```

`XCODE_ALIGN_ADDR` aligns an address. `XCODE_ALIGN` aligns the code
pointer (`HERE`). Both are target-side words. The host constant and the
target word share the name `XCODE_ALIGN_BYTES`; `NATIVE` emits a target
word that pushes the same value. The host itself uses
`XCODE_ALIGN_BYTES ALIGN`.

The z80 has threaded code and byte-aligned code, so it has no
instruction alignment and no `XCODE_ALIGN_BYTES`. Do not force x86-style
link/token/comp cells onto it.

### Word entry layout

For a conventional port, `CURRENT` points at the link cell:

```
+0              link
+xcell          token / xt (code address)
+2 cells        compile-mode behavior
+3 cells        zero-terminated name
code ...        aligned to xcode_align_bytes
```

`XWORD_COMP` is the offset of the compile-mode field.
`XNAME_FROM_TOKEN` is the offset of the name from the token field.
The z80 uses a different, threaded layout; keep its `XWORD_NAME` and
`XREL_SIZE` local.

## Target ABI and call convention

A port defines its own internal ABI. The platform ABI is followed only
at the syscall boundary; do not assume the platform's C ABI for the
port's own words. The conventional register roles are:

| port | TOS | data stack | return stack | carry |
| --- | --- | --- | --- | --- |
| amd64 | `RAX` | `RBX` | `RSP` | `CF` |
| i386 | `EAX` | `EBX` | `ESP` | `CF` |
| aarch64 | `X0` | `X19` | `X29`, with `SP` aligned | `X18` |
| z80 | `BC` | `DE` | `SP` | `F` |

On x86, `RSP`/`ESP` is both the Seed return stack and the process
stack. On AArch64, `SP` stays 16-byte aligned for the kernel and `X29`
is the Seed return stack; the startup copies `SP` to `X29`. On z80,
the data stack grows up from `STK_BOT` and `SP` grows down from
`STK_TOP`.

A call pushes a return address on the return stack and jumps to the
callee; a return pops it and jumps. The ISA's native return is not the
Seed return: on AArch64 the 4-byte `RET` branches to `X30`, which the
port leaves unused, while `RET,` emits `LDR X16,[X29],#8; BR X16`.
On x86 the two happen to coincide, but port code must not rely on it.

`CALL` and `RET,` are the emitters. `CALLCOMP` emits a call to a
compile-time xt, `TAILCOMP` emits a tail branch, and `ENDCOMP` is
`TAILCOMP` plus a failure. The geometry carries the sizes a port uses:
`XCALL_SIZE`, `XRET_SIZE`, `XSTUB_SIZE` = `XLITERAL_SIZE` +
`XRET_SIZE`, `XQUOTE_OPEN_SIZE`, and `XJUMP_SIZE`.

A helper called in the middle of a word preserves TOS, the data stack
pointer, the return-stack pointer (`X29` on AArch64, `SP` or `ESP`
elsewhere), `SP` alignment, and the carry flag. It may clobber the
registers its contract names; the caller saves anything else. The
AArch64 source header is the model for an exact register and clobber
table; the x86 and z80 headers state theirs.

At the syscall boundary, x86-64 uses `SYSCALL` with the number in
`RAX`, arguments in `RDI`, `RSI`, `RDX`, `R10`, `R8`, and `R9`, and
return in `RAX`; the kernel clobbers `RCX` and `R11`. i386 uses
`INT 0x80` with the number in `EAX` and arguments in `EBX`, `ECX`,
`EDX`, `ESI`, `EDI`, and `EBP`; the wrapper saves `EBX` because the
Seed keeps its data stack pointer there. AArch64 uses `SVC` with the
number in `X8` and arguments in `X0-X5`. The z80 uses port 0.

## 16-bit-cell rules

The host may have 16-bit cells. The target may have wider cells. A
value the host holds while *emitting* a target instruction must be
truncated to 16 bits before it affects emitted bytes. A literal wider
than 16 bits is fine when the code truncates it before use; do not rely
on a wide host value for arithmetic, comparisons, or control flow.

### Emit wide values in halves

Host-side:

```forth
\ low16 high16 --                         (4 bytes, little-endian)
{: x32,   swap w, w, }

\ low16 high16 addr --                    (store 4 bytes)
{: x32!   >r swap r> dup 2 + >r w! r> w! }
```

Target-side, for an ISA whose instruction word is 32 bits:

```forth
native x32,
binary
X3 10 shl_rr,s          \ high half
X0 X3 or_rr,rr
x' d, call
ret

native x32!
binary
X17 X0 mov_rr,rr
tos_load
X17 10 shl_rr,s
X0 X17 or_rr,rr
X17 X3 mov_rr,rr
tos_store
X0 X17 mov_rr,rr
x' d! call
ret
```

`X32,` expects `( low16 high16 -- )`, with the high half on top of the
data stack. Getting this order wrong byte-swaps every instruction.

For addresses, keep only the low 16 bits in the host and let
`XIMAGE_BASE_HI` supply the rest:

```forth
1 constant ximage_base_hi
{: a,   w, ximage_base_hi w, 0 d, }      \ 64-bit target address
```

On i386, `A,` is 4 bytes (`W, XIMAGE_BASE_HI W,`). On a raw-binary
target such as the z80, there is no `A,`.

### Split fields that cross bit 15

Do not build a full 32-bit instruction in a host cell. Split the field
and emit the two halves:

| field | low half | high half |
| --- | --- | --- |
| MOVZ/MOVK imm16 | low 11 bits | high 5 bits |
| ADD/SUB/CMP imm12 | low 6 bits | high 6 bits |
| shl/shr immr | keep out of the low half | `immr` beside the opcode |
| branch imm26 | low 16 bits | bits 16..25 beside the opcode |
| 32-bit literal | low 16 bits | high 16 bits |

For a plain 32-bit value:

```forth
\ value -- low16 high16
dup FFFF and
swap 10 rshift FFFF and
x32,
```

For a branch, put the opcode in the high half and mask the field:

```forth
\ offset -- low16 high16
dup FFFF and
swap 10 rshift 3FF and 1400 or
x32,
```

A 16-bit host cannot hold the 32-bit intermediate. Compute the halves
separately, as the AArch64 `SHL_RR,S`/`SHR_RR,S` do, rather than
shifting a value that already overflowed the host cell.

### Target computation is not host computation

Code emitted by a literal or an assembler macro runs on the target at
runtime, where cells may be 64-bit. A logical `RSHIFT` of a negative
target value still leaves ones in the high bits, which is what the
branch decoder needs. The host only has to emit the literals; it does
not evaluate that computation. The exception is anything the host
executes while compiling (address arithmetic, label offsets, word
layout) — keep those 16-bit-safe.

## Addressing and tokens

`HERE` is the host emission pointer. `$` is the target offset:

```forth
0 variable offset
{: $     here offset @ - }
{: org   here swap - offset ! }
```

`0 ORG` records the host address that corresponds to target address 0.
After that, `$` is the target offset and `HERE - OFFSET` recovers the
host address.

A target token is usually the target code address. In the AArch64 port
the entry stores only the low 16 bits of the token; the high half is
always `XIMAGE_BASE_HI`. This is why:

- `W@`/`W!` are 16-bit;
- `X'` returns the low half;
- `DOES` overwrites only the low half of the compile field;
- `A,` writes the full address when a full address is needed.

Do not mix host heap addresses and target image addresses. The image is
built in the host heap and dumped as target bytes; the two are related
only through `OFFSET`.

## Branch displacements

A relative branch has two independent facts: the width of the field
(`XREL_SIZE`) and the address the displacement is measured from.

- x86 measures from the end of the instruction: the displacement is
  `target - (site + instruction_size)`, where the instruction size is
  `XCALL_SIZE` or `XJUMP_SIZE` (or the actual branch length).
- AArch64 measures from the instruction address: an imm26 is
  `(target - site) >> 2`.
- The z80 `JR` measures from the end of the instruction; `JP` and
  `CALL` take an absolute address.

Do not copy a branch formula between ports. Check the host
`RLABEL`/`JMP` macros and the target `CALLCOMP`/`TAILCOMP` emitters.
`XJUMP_SIZE` and `XCALL_SIZE` are instruction sizes, not displacement
bases.

The x86 Seeds keep the explicit fixed long-branch macros (`RLABEL`,
`RLABEL_F`, ...). The amd64/i386 Sprouts select a short or long branch
with `LABEL_OFFSET`, `SHORT_RLABEL?`, and `MAYBE_RS`. Keep the Seeds on
the simpler fixed form; do not port the Sprout selection machinery
unless that tradeoff changes.

## Cross-compilation

The compile-mode behavior of a target word cannot be executed on the
host. The AArch64 port keeps a small association list (`XCOMPS`) of
host-side compile behaviors and uses `XCOMPILE` for the default case:

```forth
{: xcompile
word
{ pad c@ 0= drop }
{ input word }
while
{ xfind w@
  { pad xcomps recall }
  { ' call }
}~|
{ pad s>number ' xliteral }
|
execute
}~self
```

Key consequences:

- A target word must exist in the target vocabulary before a target
  definition that calls it. A forward reference fails compilation.
- The default compile behavior emits a call (`CALLCOMP`). Words whose
  compile behavior differs (for example `}`, `}~`, `}~FAIL`, `}~SELF`,
  `}~|`, `[`, `{`, `"`, `\`, `(`) are listed in `XCOMPS`.
- `LITERAL` emits a target literal; `{{`/`}}` emit a quotation and
  patch its branch; `RET,` emits a return.
- `X'` is target tick; `'` is host tick. `DOES` writes a compile
  behavior into the last target word.
- If a whole target definition is truncated at a word that is not in
  the target vocabulary yet, check the definition order first.

A compile-mode behavior is a constructor or a terminator. A
constructor (`{`, `"`, `[`, `'`, `ASCII`) leaves a value or xt for the
compiler. A terminator (`}`, `}~`, `}~FAIL`, `}~|`, `}~SELF`,
`'ID}~|`) emits its code and then fails, which ends the compile loop.
The z80 registers the same behaviors in `XCOMPS`: `COMMA`, `ENDCOMP`,
`ENDTAIL`, `SELFREF`, `~SELFREF`, `>LIT`, `QUOTATE`, and `EXEC`, each
a target pointer used as the lookup key.

Known traps from this port:

- `}~SELF` used `*` before `*` was defined in the target vocabulary.
  The failure looked arithmetic but was a lookup failure.
- `X32,` combined the halves in the wrong order, so instructions were
  emitted byte-swapped.
- `shl`/`shr` put `immr` in bits 16..21, where a 16-bit `X32,` silently
  dropped it.

## Quotations

`{` starts a quotation at `HERE`: it saves the body address and calls
the compiler. The compiled layout is:

    opener        push the body address and branch over the body
    body          the computation
    continuation  pop the return address into TOS

The opener is emitted by `{{` (target) or `X{{` (host). `X{{` returns
the body address so `X}}` can patch the branch; the target `{{` does
not push the body address, so the xt supplied by `QUOTATE` remains TOS
for `EXECUTE`. `}}` patches the opener's branch to the continuation
and emits `TOS_STORE` plus the pop. `XQUOTE_OPEN_SIZE` is the opener
size and `XREL_SIZE` is the branch-field width; on x86 the opener may
have the same size as `XCALL_SIZE`, in which case say so in the
geometry comment.

`}~SELF` emits a branch back to the body start and then fails. `}~`
emits a tail call to the next word, `}~FAIL` raises failure, and
`}~|` ends with a disjunction. These endings are compile-mode
terminators: they emit code and then fail so the enclosing compiler
stops. Constructors (`{`, `"`, `[`, `'`, `ASCII`) instead leave a
value or xt for the compiler to consume.

## Failure and effect frames

`&` installs a failure handler for the computation that follows. `|`
executes one computation with another as its failure handler.
`HANDLE` installs a handler for an effect, `CUT` removes the current
handler, and `}~FAIL` unwinds to the nearest handler. `FAIL` holds the
current handler address and `ERR_SP` points at the innermost frame on
the return stack.

For the conventional ports the frame is, from `ERR_SP` up, one cell
each:

    +0  handler slot pointer
    +1  previous handler address
    +2  previous ERR_SP
    +3  saved data stack pointer

`HANDLE` and `&` build such a frame. On those ports `}~FAIL` walks
the chain, restores each handler cell and `ERR_SP`, and jumps to the
handler it finds. `CUT` discards the top frame and restores the
previous one. The startup installs a circular outermost frame at label
6: the handler-pointer slot holds the address of `FAIL`, so the walk
matches it instead of continuing past the frame.

The z80 uses 2-byte cells. `CUT` reads a handler pointer, the previous
handler, and the previous `ERR_SP` from the frame, then moves the live
stack below it; read `HANDLE` and `CUT` for the exact slot count and
register sequence.

Do not assume a frame layout from another port. The slot order and the
saved-pointer convention are part of the port's ABI.

## Postponed definitions

`POSTPONE` creates the entry and reserves a forward jump. `{::` finds
the entry, patches that jump to the body it is about to compile, and
leaves the token on the patched jump. Emit the placeholder with the
target's jump width and patch only the branch field; do not write a
whole host cell over it. `LINK` aligns the next entry, so `POSTPONE`
needs no extra padding. Mark the patched instruction for an icache
sync where the target requires it.

## ELF output

Sprouts keep section headers. The current valid layout is:

- `.text` `PROGBITS`, `WRITE` cleared, `ALLOC|EXECINSTR`;
- `.bss` `NOBITS`, `WRITE|ALLOC`;
- an empty `.data` `PROGBITS` at the `.bss` address so the writable
  `PT_LOAD` contains a writable non-`NOBITS` section;
- `e_shnum` counts every section including `.data`;
- `.shstrtab` is last and `e_shstrndx` points at it.

Seeds may omit section headers entirely; `eu-elflint` still validates
the ELF and program headers.

Section virtual addresses use `XIMAGE_BASE_HI`, like the rest of the
emitter. Validate with `eu-elflint -q`; `readelf` is too permissive to
be the test.

The z80 port emits a raw binary, not an ELF. Skip the ELF checks there.

## Bootstrap

`seed/bin/seed-linux-amd64` is the trusted bootstrap. It must
correspond to the current `seed-linux-amd64.seed` source:

```sh
./seed/bin/seed-linux-amd64 <seed/src/seed-linux-amd64.seed \
    >tools-for-build/build/seed.amd64
chmod +x tools-for-build/build/seed.amd64
./tools-for-build/build/seed.amd64 <seed/src/seed-linux-amd64.seed \
    >tools-for-build/build/seed.amd64.2
cmp tools-for-build/build/seed.amd64 tools-for-build/build/seed.amd64.2
```

Rebuild the committed binary whenever the amd64 source changes, and
verify it still behaves identically on every source. The test suite
fails when a committed `seed/bin/seed-*` differs from a fresh build.

A port also needs a two-generation self-host check and the full cross
matrix: every capable Seed and Sprout compiles the port, and all
outputs agree byte for byte.

## Testing

The suite lives in `tools-for-build/`:

- `ci-linux.sh [--native|--cross|--all]` drives the CI matrix and can
  be run locally;
- `test.sh` runs the native host suite and the z80 suite;
- `test-<arch>.sh` is a host-architecture suite;
- `test-common.sh` holds the shared cross-compilation matrix, the
  runtime probes, and the checks;
- `probes/` holds the Seed programs used by the runtime suite;
- `install-ubuntu-deps.sh` is the one package list;
- `README.md` describes prerequisites and target availability.

Add a new port to `test-common.sh`; add a runtime probe to `probes/`
and its expected whitespace-stripped stdout to `probe_expected` in
`test-common.sh`. A test that exposes a bug is a separate `test:`
commit before the fix.

`qemu-user` is optional. Without a runner for a foreign target, the
suite skips that target with a `SKIP:` note; the full cross matrix runs
only when amd64, i386, and aarch64 are all executable.

Run the full suite with:

```sh
rm -rf tools-for-build/build && bash tools-for-build/ci-linux.sh --all
```

## Pitfalls

- A host literal wider than 16 bits used for arithmetic, a comparison,
  or control flow instead of being truncated first.
- A wide source literal listed by the yellow literal check: review it,
  but do not split it merely to silence the check.
- A 32-bit intermediate that overflows before it is split.
- `X32,` argument order: high half on top.
- An `immr`/`imm12`/`imm26` field that extends past bit 15.
- A target word used before it is defined in the target vocabulary.
- A stale `seed/bin/seed-linux-amd64`.
- Host heap addresses leaking into target addresses, or `$`/`HERE`
  mixed up.
- Repeating the instruction alignment size instead of using
  `XCODE_ALIGN_BYTES`/`XCODE_ALIGN`.
- `RSHIFT` on a negative host value when the intent was a target-side
  sign-preserving shift.
- Forgetting to update the cross matrix in `test-common.sh`.
- Using the ISA's native return instead of `RET,`; on AArch64 `RET`
  branches to `X30`, which the port leaves unused.
- Copying a branch displacement formula between ports; x86 measures
  from the end of the instruction, AArch64 from the instruction.
- A helper that clobbers TOS, the data stack pointer, the call stack,
  or `CF` without saying so.
- Assuming a failure-frame slot order from another port.
- Forgetting that host `X{{` returns the body address while target
  `{{` does not push it.

## Checklist

- [ ] source builds with the amd64 Seed and with the 16-bit z80 Seed;
- [ ] wide source literals are truncated before they affect emitted
      bytes;
- [ ] two-generation self-host fixpoint;
- [ ] cross-compiles identically from every capable Seed/Sprout;
- [ ] z80 -> new port matches the amd64-built image;
- [ ] every emitted ELF passes `eu-elflint -q`;
- [ ] geometry block describes the target, not the host;
- [ ] `XCODE_ALIGN_BYTES` is the only place the instruction alignment
      is written down;
- [ ] word entry layout and token/target-address conventions are
      documented in the source;
- [ ] `tools-for-build/test-common.sh` covers the new port;
- [ ] `seed/bin/seed-linux-amd64` is current;
- [ ] the source header states the register roles, call convention,
      clobber rules, and memory map;
- [ ] `RET,`, `CALLCOMP`, and `TAILCOMP` emit the Seed call and return
      sequences; the ISA's native return is not used;
- [ ] the quotation opener, closer, and branch field sizes match the
      geometry constants;
- [ ] the failure-frame slot order matches `HANDLE`, `CUT`, and
      `}~FAIL`;
- [ ] host and target definitions of the same name are understood;
- [ ] a runtime probe covers the changed behavior;
- [ ] the z80 image stays below `STK_BOT` and the stacks do not meet;
- [ ] comments explain invariants and portability constraints.

## Reviewing a change

- Which pass does the changed word belong to, host or target?
- Does the change alter any emitted byte? If yes, rebuild the
  committed bootstrap in the same series and run the cross matrix.
- Does it use a named geometry constant instead of a repeated size?
- Does it preserve the ABI and clobber contract?
- Does it touch a failure frame, a quotation, or a branch? Re-read the
  corresponding section above.
- Is there a probe that would fail if the change regresses?
