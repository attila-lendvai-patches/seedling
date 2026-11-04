# Build tools

The test entry points live here. `ci-linux.sh` runs the matrix, both
in CI and locally; `test.sh` runs the suite for the current host
architecture and the z80 suite. Runtime probes run as each Seed and
Sprout binary is built.

The suffix in a `test-<arch>.sh` name is the **host** architecture,
not the target. Every suite cross-compiles to all the Seed and Sprout
ports.

## Scripts

* `ci-linux.sh` — runs the matrix: `--native`, `--cross` or `--all`.
* `test.sh` — dispatches on `uname -m` and runs the suites below.
* `test-amd64.sh`, `test-i386.sh`, `test-aarch64.sh` — the host suite.
* `test-z80.sh` — the z80 Seed through `z80sim`.
* `test-runtime.sh` — manual wrapper for the runtime probes.
* `probes/` — the Seed programs used by the runtime suite.
* `test-common.sh` — shared checks and the cross-compilation matrix.
* `install-ubuntu-deps.sh` — the Ubuntu packages the suite needs.

`build/` and `z80sim/` are generated and ignored by git.

Run the scripts; do not source them. `test.sh` writes the complete
output to `tools-for-build/build/test.log`, so a failure or a closed
terminal does not lose the log. Set `TEST_DEBUG=1` to trace commands:

```sh
TEST_DEBUG=1 bash tools-for-build/test.sh
```

Every step is wrapped in a `::group::` for GitHub's job log and runs
under `timeout` (`STEP_TIMEOUT`, default 20 minutes; the in-process
source checks are not timed). When GitHub sets `GITHUB_STEP_SUMMARY`,
`test.sh` also appends a table of steps, results and durations to it.

`test-common.sh` is a library; running it directly reports that and
exits.

## Prerequisites

* `bash`, `git`, `make`, `gcc`
* `qemu-user-static`, optional, for executing binaries of a foreign
  architecture
* `eu-elflint` (package `elfutils`)
* `libz80ex-dev` for building `z80sim`

On Debian/Ubuntu, install the same list CI uses:

```sh
sudo tools-for-build/install-ubuntu-deps.sh
```

## Running another host's suite by hand

`ci-linux.sh --native` runs the host suite and the z80 suite for the
current machine. `ci-linux.sh --cross` runs the aarch64 host suite on
an x86_64 machine, where the committed aarch64 Seed compiles every
port:

```sh
tools-for-build/ci-linux.sh --cross
```

`--all`, the default, runs both.

A foreign binary is run by prefixing it with `qemu-<arch>`, so no
binfmt registration is needed; `qemu-user-static` from the
prerequisites is enough, and the scripts do not print the prefix.
binfmt matters only for the one case the kernel handles itself: 32-bit
x86 binaries on an amd64 machine without 32-bit support.

To run the amd64 host suite on an aarch64 machine, provide
`qemu-x86_64` and call that suite directly:

```sh
bash tools-for-build/test-amd64.sh
```

Without a runner a suite skips the affected target with a `SKIP:` note
and exits successfully, so check the log when a run looks too quick.

## Target availability

Native targets run directly, and i386 on an amd64 host counts as
native.  Foreign targets use a matching `qemu-<arch>` when it is
installed; otherwise their tests are skipped with a `SKIP:` note.  The
full cross-compilation matrix runs only when amd64, i386 and aarch64
are all executable.  Otherwise the suite runs a per-target suite for
each available target and keeps the committed-binary, z80 and ELF
checks.

Set `TEST_NO_QEMU=1` to force the no-qemu path even when qemu is
installed.

## Runtime suite

The host suites call `runtime_suite <binary> <label>` from
`test-common.sh` immediately after each build. It runs the Seed
programs under `probes/` against that one binary and checks stdout, not
emitted bytes, so it covers compiler behaviour that the
cross-compilation matrix cannot see.  A binary whose target cannot be
executed is skipped with a note.  The `postpone.seed` probe is the
regression for the AArch64 `postpone`/`{::` placeholder bug.

The z80 suite builds the worktree Seed first and probes it before the
z80 cross-compilation tests. A runtime failure therefore stops the
suite as soon as the affected binary is built.

`test-runtime.sh <binary> [label]` runs the probes against one binary
by hand. Without arguments it runs the standard `$BUILD` set. The
probes use `TEST_TIMEOUT` (default 120 seconds) as a per-run limit; set
`TEST_VERBOSE=1` to list every passing probe.

## z80sim

`test-z80.sh` checks out `https://github.com/nagydani/z80sim.git` at
`4bb8be2` under `tools-for-build/z80sim` if it is not already present,
then builds it. Delete that directory to force a clean checkout.
