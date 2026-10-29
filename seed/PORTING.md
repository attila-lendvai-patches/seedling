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
5. the z80 roots still match: z80 self-host, z80 -> amd64,
   z80 -> i386, and z80 -> aarch64.

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

## Source shape

A Seed source starts with `output` on the first line. The usual order is:

1. requirements, assembler scope, TOS/register roles;
2. `[port]` image base and target geometry;
3. Part I: host-side assembler macros (`w,`, `d,`, `a,`, opcode
   emitters, labels, calls, literals);
4. the cross-compiler (`xcompile`, `xcomps`, `xcreate`, `x'`, `does`);
5. `create ELF`, the ELF header, and the initial machine code;
6. Part II: target-side words (`literal`, `{{`, `}}`, `ret,`,
   `create`, the seed loop);
7. the final `output` path.

Part I runs while the source is being compiled. Part II is the target
program that will compile the next generation. Do not use a target word
at compile time unless it is also defined as a host word.

## Target geometry

Put a geometry block in `[port]` and make every value true for the
target, not for the host:

```forth
xcell_bits  xcelllog  xcell  xcell1-  xcell_mask
xcells  xalign  xcell+
xcode_align_bytes     \ only where instructions need alignment
xcall_size  xquote_open_size  xrel_size
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
xcell 2 * constant xword_comp
xcell 2 * constant xname_from_token
10 constant xcall_size
10 constant xquote_open_size
4 constant xrel_size
```

`xcell` is the target cell size in bytes. `xalign` aligns an address
to a target cell. `xcode_align_bytes` is the *instruction* boundary,
which may be different from the cell size.

### Code alignment

Where instructions need alignment, do not repeat the size in the
target words. Emit `xcode_align_bytes` as a target constant and derive
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

`xcode_align_addr` aligns an address. `xcode_align` aligns the code
pointer (`here`). Both are target-side words. The host constant and the
target word share the name `xcode_align_bytes`; `native` emits a target
word that pushes the same value. The host itself uses
`xcode_align_bytes align`.

The z80 has threaded code and byte-aligned code, so it has no
instruction alignment and no `xcode_align_bytes`. Do not force x86-style
link/token/comp cells onto it.

### Word entry layout

For a conventional port, `current` points at the link cell:

```
+0              link
+xcell          token / xt (code address)
+2 cells        compile-mode behavior
+3 cells        zero-terminated name
code ...        aligned to xcode_align_bytes
```

`xword_comp` is the offset of the compile-mode field.
`xname_from_token` is the offset of the name from the token field.
The z80 uses a different, threaded layout; keep its `xword_name` and
`xrel_size` local.

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

`x32,` expects `( low16 high16 -- )`, with the high half on top of the
data stack. Getting this order wrong byte-swaps every instruction.

For addresses, keep only the low 16 bits in the host and let
`ximage_base_hi` supply the rest:

```forth
1 constant ximage_base_hi
{: a,   w, ximage_base_hi w, 0 d, }      \ 64-bit target address
```

On i386, `a,` is 4 bytes (`w, ximage_base_hi w,`). On a raw-binary
target such as the z80, there is no `a,`.

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
separately, as the AArch64 `shl_rr,s`/`shr_rr,s` do, rather than
shifting a value that already overflowed the host cell.

### Target computation is not host computation

Code emitted by a literal or an assembler macro runs on the target at
runtime, where cells may be 64-bit. A logical `rshift` of a negative
target value still leaves ones in the high bits, which is what the
branch decoder needs. The host only has to emit the literals; it does
not evaluate that computation. The exception is anything the host
executes while compiling (address arithmetic, label offsets, word
layout) — keep those 16-bit-safe.

## Addressing and tokens

`here` is the host emission pointer. `$` is the target offset:

```forth
0 variable offset
{: $     here offset @ - }
{: org   here swap - offset ! }
```

`0 org` records the host address that corresponds to target address 0.
After that, `$` is the target offset and `here - offset` recovers the
host address.

A target token is usually the target code address. In the AArch64 port
the entry stores only the low 16 bits of the token; the high half is
always `ximage_base_hi`. This is why:

- `w@`/`w!` are 16-bit;
- `x'` returns the low half;
- `does` overwrites only the low half of the compile field;
- `a,` writes the full address when a full address is needed.

Do not mix host heap addresses and target image addresses. The image is
built in the host heap and dumped as target bytes; the two are related
only through `offset`.

## Cross-compilation

The compile-mode behavior of a target word cannot be executed on the
host. The AArch64 port keeps a small association list (`xcomps`) of
host-side compile behaviors and uses `xcompile` for the default case:

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
- The default compile behavior emits a call (`callcomp`). Words whose
  compile behavior differs (for example `}`, `}~`, `}~fail`, `}~self`,
  `}~|`, `[`, `{`, `"`, `\`, `(`) are listed in `xcomps`.
- `literal` emits a target literal; `{{`/`}}` emit a quotation and
  patch its branch; `ret,` emits a return.
- `x'` is target tick; `'` is host tick. `does` writes a compile
  behavior into the last target word.
- If a whole target definition is truncated at a word that is not in
  the target vocabulary yet, check the definition order first.

Known traps from this port:

- `}~self` used `*` before `*` was defined in the target vocabulary.
  The failure looked arithmetic but was a lookup failure.
- `x32,` combined the halves in the wrong order, so instructions were
  emitted byte-swapped.
- `shl`/`shr` put `immr` in bits 16..21, where a 16-bit `x32,` silently
  dropped it.

## Postponed definitions

`postpone` creates the entry and reserves a forward jump. `{::` finds
the entry, patches that jump to the body it is about to compile, and
leaves the token on the patched jump. Emit the placeholder with the
target's jump width and patch only the branch field; do not write a
whole host cell over it. `link` aligns the next entry, so `postpone`
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

Section virtual addresses use `ximage_base_hi`, like the rest of the
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
warns when a committed `seed/bin/seed-*` differs from a fresh build.

A port also needs a two-generation self-host check and the full cross
matrix: every capable Seed and Sprout compiles the port, and all
outputs agree byte for byte.

## Testing

The suite lives in `tools-for-build/`:

- `tools-for-build/test.sh` dispatches on the host architecture and
  runs the z80 suite;
- `tools-for-build/test-<arch>.sh` is the host architecture suite;
- `tools-for-build/test-common.sh` holds the shared cross-compilation
  matrix and the checks;
- `tools-for-build/README.md` lists prerequisites and binfmt setup.

Add a new port to `test-common.sh` (not to CI). CI installs the
dependencies and runs `bash tools-for-build/test.sh`. The same applies
to the z80 roots: add the new direction to the z80 suite.

Run the full suite with:

```sh
rm -rf tools-for-build/build && bash tools-for-build/test.sh
```

## Pitfalls

- A host literal wider than 16 bits used for arithmetic, a comparison,
  or control flow instead of being truncated first.
- A wide source literal listed by the yellow literal check: review it,
  but do not split it merely to silence the check.
- A 32-bit intermediate that overflows before it is split.
- `x32,` argument order: high half on top.
- An `immr`/`imm12`/`imm26` field that extends past bit 15.
- A target word used before it is defined in the target vocabulary.
- A stale `seed/bin/seed-linux-amd64`.
- Host heap addresses leaking into target addresses, or `$`/`here`
  mixed up.
- Repeating the instruction alignment size instead of using
  `xcode_align_bytes`/`xcode_align`.
- `rshift` on a negative host value when the intent was a target-side
  sign-preserving shift.
- Forgetting to update the cross matrix in `test-common.sh`.

## Checklist

- [ ] source builds with the amd64 Seed and with the 16-bit z80 Seed;
- [ ] wide source literals are truncated before they affect emitted
      bytes;
- [ ] two-generation self-host fixpoint;
- [ ] cross-compiles identically from every capable Seed/Sprout;
- [ ] z80 -> new port matches the amd64-built image;
- [ ] every emitted ELF passes `eu-elflint -q`;
- [ ] geometry block describes the target, not the host;
- [ ] `xcode_align_bytes` is the only place the instruction alignment
      is written down;
- [ ] word entry layout and token/target-address conventions are
      documented in the source;
- [ ] `tools-for-build/test-common.sh` covers the new port;
- [ ] `seed/bin/seed-linux-amd64` is current;
- [ ] comments explain invariants and portability constraints.
