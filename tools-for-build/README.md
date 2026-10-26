# Build tools

The test entry points live here. `test.sh` runs the suite for the
current host architecture and the z80 suite. Runtime probes run as
each Seed and Sprout binary is built.

The suffix in a `test-<arch>.sh` name is the **host** architecture,
not the target. Every suite cross-compiles to all the Seed and Sprout
ports.

## Scripts

* `test.sh` — dispatches on `uname -m` and runs the suites below.
* `test-amd64.sh`, `test-i386.sh`, `test-aarch64.sh` — the host suite.
* `test-z80.sh` — the z80 Seed through `z80sim`.
* `test-runtime.sh` — manual wrapper for the runtime probes.
* `probes/` — the Seed programs used by the runtime suite.
* `test-common.sh` — shared checks and the cross-compilation matrix.

`build/` and `z80sim/` are generated and ignored by git.

Run the scripts; do not source them. `test.sh` writes the complete
output to `tools-for-build/build/test.log`, so a failure or a closed
terminal does not lose the log. Set `TEST_DEBUG=1` to trace commands:

```sh
TEST_DEBUG=1 bash tools-for-build/test.sh
```

`test-common.sh` is a library; running it directly reports that and
exits.

## Prerequisites

* `bash`, `git`, `make`, `gcc`
* `qemu-user-static` and `binfmt-support`, optional, for executing
  binaries of a foreign architecture
* `eu-elflint` (package `elfutils`)
* `libz80ex-dev` for building `z80sim`

On Debian/Ubuntu:

```sh
sudo apt-get install -y \
    qemu-user-static binfmt-support elfutils libz80ex-dev \
    build-essential git
```

## Running another host's suite by hand

`test.sh` runs the native host suite and the z80 suite. To run a
different `test-<arch>.sh` on the current machine, install `qemu-user`
or otherwise provide the matching `qemu-<arch>` in `PATH`.  Without a
runner, the suite skips the affected target with a `SKIP:` note and
exits successfully.

For example, to run the aarch64 suite on an amd64 host:

```sh
sudo apt-get install -y qemu-user-static binfmt-support
sudo update-binfmts --enable qemu-aarch64
# enable qemu-i386 too if the kernel cannot execute 32-bit x86 natively
sudo update-binfmts --enable qemu-i386

bash tools-for-build/test-aarch64.sh
```

To run the amd64 suite on an aarch64 host, enable `qemu-x86_64` (and
`qemu-i386` for the i386 cross-checks):

```sh
sudo update-binfmts --enable qemu-x86_64
sudo update-binfmts --enable qemu-i386

bash tools-for-build/test-amd64.sh
```

The suites execute native targets directly and foreign targets through
a matching `qemu-<arch>` when it is installed.  Without a runner they
skip the target.  The scripts do not print `qemu-*` prefixes.

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
