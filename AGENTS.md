# Notes for Agents

Seedling is a self-hosting concatenative toolchain. The implementation *is*
the set of `.seed` sources: there is no C or bootstrapping language to fall
back on. Read `README.md`, `RATIONALE.md`, `seed/README.md`,
`sprout/README.md`, and `syntax/PRINCIPLES.md` before nontrivial work.

## Prime directive: a 16-bit host must suffice

**The high-level goal is that every Seed and Sprout can be compiled by a
16-bit host such as the z80.** A port is not finished because it builds on
amd64; it is finished when the smallest practical host can produce it.

Consequences for every source and change:

* Keep the z80 bootstrap paths working. The z80 Seed compiles amd64, i386,
  and itself. `z80 -> aarch64` is the known gap: the aarch64 sources still
  need values wider than 16 bits (e.g. the `10000` image base / 0x10000).
  Close that gap; do not widen it.
* Do not introduce constants, addresses, or intermediate values that need
  more than 16 bits unless the source is explicitly not z80-compilable.
  Emit wide target values from 16-bit-safe pieces. Use `ximage_base_hi` and
  the `a,` / `label_f` helpers rather than a full target address literal.
* Describe the *target* geometry per port. Never derive it from the
  compiling host.
* Cross-compilation must be exact: any Seed or Sprout compiling the same
  source must produce byte-identical output.

## Values

Simplicity and small size are the point. Every abstraction must pay for
itself in bootstrapping; prefer the obvious implementation over the clever
one. The sources are meant to be read and verified by people, so source
length is cheap but conceptual weight is not.

Comments are concise and earn their place: explain *why*, an invariant, a
portability constraint, or a non-obvious encoding. Do not restate the code.
Type/effect signatures in `( ... )` are meaningful; keep them accurate.

Names primarily serve readability. Use lowercase words. A name that is
simply two words composed is written as those words concatenated, without a
space: `xcelllog` is `xcell log`. Do not invent a new verb when a pair of
existing words already says it.

## Repository map

* `seed/src/seed-linux-{amd64,i386,aarch64}.seed` — Seed ports.
* `seed/src/seed-z80-fictional.seed` — 16-bit reference host.
* `seed/bin/seed-linux-amd64` — committed trusted bootstrap. It must
  correspond to the current amd64 Seed source, not to an older revision.
* `sprout/src/sprout-linux-*.seed`, `sprout/src/sprout-z80-fictional.seed`
  — Sprout ports.
* `seed/README.md`, `sprout/README.md` — the language specifications.
  `sprout/EXECUTION.md` explains interpret/compile mode duality.
* `test.sh` — local, full test suite. It is gitignored and stays local.
* `.github/workflows/ci.yaml` — the committed test definition.

Keep `test.sh` and CI in sync when adding a check. `build/`, `z80sim/`, and
`test.sh` are not committed.

## Invariants to re-establish after every change

1. **Self-host fixpoint**: a port compiling its own source reproduces
   itself byte for byte (run at least two generations).
2. **Cross agreement**: every capable Seed/Sprout compiling a source yields
   the same bytes as every other capable one.
3. **Bootstrap correspondence**: if the amd64 Seed source changes, rebuild
   `seed/bin/seed-linux-amd64` and verify it behaves identically on all
   sources. Never leave it stale.
4. **ELF validity**: every emitted ELF passes `eu-elflint -q` with no
   output. `readelf` is too permissive to be the validator.
5. **z80 roots**: z80 self-host, z80 -> amd64, and z80 -> i386 still match.

## Build and test

A source is compiled by feeding it to a Seed on stdin and capturing stdout:

```sh
./seed/bin/seed-linux-amd64 <seed/src/seed-linux-amd64.seed >build/seed.amd64
chmod +x build/seed.amd64
./build/seed.amd64 <seed/src/seed-linux-amd64.seed >build/seed.amd64.2
cmp build/seed.amd64 build/seed.amd64.2
```

The full local run needs `qemu-user` (`qemu-aarch64`, `qemu-i386`),
`eu-elflint` (package `elfutils`), and `./z80sim/z80sim`:

```sh
rm -rf build && bash test.sh
```

CI installs `qemu-user` and `elfutils`, clones and builds
`https://github.com/nagydani/z80sim.git`, then performs the same checks.
Do not add a check only to one of `test.sh` and CI.

## Porting conventions

Start from the closest existing port. Each source begins with `output` on
the first line, then states its requirements, the assembler's scope, the
TOS/register roles, and a `[port]` geometry block.

Keep the target description explicit and local:

```
xcell_bits  xcelllog  xcell  xcell1-  xcell_mask
xcells  xalign  xcell+
xcode_align_bytes (only where instructions need alignment)
xcall_size  xquote_open_size  xrel_size
xword_comp  xname_from_token
```

Where instructions need alignment, emit `xcode_align_bytes` as a target
constant and derive `xcode_align_addr`/`xcode_align` from it instead of
repeating the size.  These are target-side words; the host uses
`xcode_align_bytes align`.

The z80 has threaded code and no token/comp cells; do not force x86-style
fields onto it. Use the smallest geometry that is true, and keep code
alignment zero where the ISA does not require it.

When porting, update all of:

* the new Seed and/or Sprout source;
* `test.sh`;
* `.github/workflows/ci.yaml`;
* cross-compile checks in both directions with existing ports.

## ELF output

Sprouts keep their section headers. The current valid layout is:

* `.text` `PROGBITS`, `WRITE` cleared, `ALLOC|EXECINSTR`;
* `.bss` `NOBITS`, `WRITE|ALLOC`, file offset at the end of loaded data
  (`p_filesz`);
* an empty `.data` `PROGBITS` at the `.bss` address so the writable
  `PT_LOAD` contains a writable non-`NOBITS` section;
* `e_shnum` counts every section including `.data`; `.shstrtab` is last and
  `e_shstrndx` points at it.

Section virtual addresses use `ximage_base_hi`, like the rest of the
emitter. Re-run `eu-elflint` on every emitted binary after touching the
ELF code.

## Source style

* Hard line limit: every Seed and Sprout source line is at most 64
  bytes of UTF-8, including comments. New or edited code should also
  keep the width within 64 columns after expanding tabs to 8-column
  stops; existing over-wide lines are tolerated while they are not
  otherwise being changed, and the test suite warns about them. Seed
  sources are 7-bit ASCII, one file per port. Sprout sources are
  UTF-8, but non-ASCII is only allowed in comments and literals.
* Words are at most 30 printable ASCII characters, case-sensitive.
* `\` comments to end of line. `( ... )` comments are reserved for type
  and effect signatures; the convention is
  `( inputs -( effects )- outputs )`.
* Use the `x` prefix for target-side and cross-compilation words, and `_`
  for internal helpers not meant as public vocabulary.
* Preserve explicit tail calls (`}~`, `}~self`, `}~fail`, `}~|`) where they
  are part of the design; they keep the return stack bounded.
* Keep architecture-dependent code in `[port]` blocks; shared logic
  belongs in the common part of the file.

## Git

Use an area prefix and the imperative mood: `seed: ...`, `sprout: ...`,
`ci: ...`, `aarch64: ...`, `i386: ...`. Explain the why and any invariant
that was verified in the body. Rebuild generated binaries in the same
series as the source change, and say what was compared.
