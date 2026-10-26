# Build tools

The test entry points live here. `test.sh` runs the suite for the
current host architecture and then the z80 suite.

The suffix in a `test-<arch>.sh` name is the **host** architecture,
not the target. Every suite cross-compiles to all the Seed and Sprout
ports.

## Scripts

* `test.sh` — dispatches on `uname -m` and runs `test-z80.sh`.
* `test-amd64.sh`, `test-i386.sh`, `test-aarch64.sh` — the host suite.
* `test-z80.sh` — the z80 Seed through `z80sim`.
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

* `bash`, `git`, `make`, `gcc`, `python3`
* `qemu-user-static` and `binfmt-support` for executing binaries of a
  foreign architecture
* `eu-elflint` (package `elfutils`)
* `libz80ex-dev` for building `z80sim`

On Debian/Ubuntu:

```sh
sudo apt-get install -y \
    qemu-user-static binfmt-support elfutils libz80ex-dev \
    build-essential git python3
```

## Running another host's suite by hand

`test.sh` only runs the native host suite plus `test-z80.sh`. To run a
different `test-<arch>.sh` on the current machine, configure
`binfmt_misc` for every architecture the script executes but the
machine cannot run natively.

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

The scripts execute the generated binaries directly; `binfmt_misc`
selects qemu. There are no `qemu-*` prefixes in the scripts.

## z80sim

`test-z80.sh` checks out `https://github.com/nagydani/z80sim.git` at
`4bb8be2` under `tools-for-build/z80sim` if it is not already present,
then builds it. Delete that directory to force a clean checkout.
