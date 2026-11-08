#!/usr/bin/env bash

# Run the suite for the current host (and the i386 suite on amd64,
# which executes i386 ELF directly), then the z80 suite.
# The suffix of a test-<arch>.sh script is the assumed *host*
# architecture, not the target architecture.

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    echo "error: run this script, do not source it" >&2
    return 1
fi

set -euo pipefail
if [ "${TEST_DEBUG:-0}" = 1 ]; then
    set -x
fi

TOOLS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$TOOLS/.." && pwd)
BUILD="$TOOLS/build"
LOG="$BUILD/test.log"
mkdir -p "$BUILD"
: >"$LOG"

# Per-step limit for the external suites. The in-process checks are
# bounded by the source tree and are not timed. qemu, the z80sim
# checkout and its build are the steps that can hang.
STEP_TIMEOUT="${STEP_TIMEOUT:-20m}"

# GitHub folds a step between ::group:: and ::endgroup::; outside CI
# they are ordinary log lines. The summary table is written only when
# GitHub provides a file for it.
summary="${GITHUB_STEP_SUMMARY:-/dev/null}"

_run() {
    local status

    set +e
    # A shell function cannot be handed to timeout; run it directly.
    if declare -F "$1" >/dev/null; then
        "$@" 2>&1 | tee -a "$LOG"
    else
        timeout "$STEP_TIMEOUT" "$@" 2>&1 | tee -a "$LOG"
    fi
    status=$?
    set -e
    return "$status"
}

run() {
    local label=$1
    local start=$SECONDS
    local status result=ok

    shift
    echo "::group::$label"
    if _run "$@"; then status=0; else status=$?; fi
    echo "::endgroup::"

    if [ "$status" -ne 0 ]; then
        result="failed ($status)"
    fi
    printf '| %s | %s | %ss |\n' "$label" "$result" "$((SECONDS - start))" \
        >>"$summary"

    return "$status"
}

source "$TOOLS/test-common.sh"

echo "==> log: ${LOG#"$ROOT"/}"

printf '### test suite\n\n| Step | Result | Time |\n|:-----|:-------|-----:|\n' \
    >>"$summary"

case "$(uname -m)" in
    x86_64|amd64)
        host=amd64
        ;;
    i386|i486|i586|i686)
        host=i386
        ;;
    aarch64|arm64)
        host=aarch64
        ;;
    *)
        echo "error: unsupported host architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

echo "==> host architecture: $host"

BOOTSTRAP=$(bootstrap_for_host)

run "source line check" source_line_check
run "source literal check" source_literal_check
run "committed binaries" committed_binary_check
run "undefined word" undefined_word_check
export TEST_CHECKS_DONE=1

run "host suite ($host)" bash "$TOOLS/test-$host.sh"

# An amd64 host can run i386 ELF binaries natively, so exercise the
# i386 host suite there too.
if [ "$host" = amd64 ]; then
    run "i386 host suite" bash "$TOOLS/test-i386.sh"
fi

run "z80 suite" bash "$TOOLS/test-z80.sh"
