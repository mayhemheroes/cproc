#!/usr/bin/env bash
# cproc/mayhem/test.sh — RUN cproc's OWN test suite (the `./runtests` golden-output harness) against the
# normal-flags cproc-qbe that mayhem/build.sh produced → CTRF. PATCH-grade oracle: it never compiles.
#
# runtests compiles each test/*.c (and test/constraint/*.c) with `cproc-qbe -t <arch> -o out <test>` and
# DIFFS the emitted QBE IR against the checked-in golden test/*.qbe (or expected -E output *.pp, or the
# expected error text *.err). This is a KNOWN-ANSWER / golden-output suite — it asserts cproc emits the
# exact expected IR, not merely that the binary exits 0. A no-op / exit(0) "patch" produces empty/ wrong
# output and FAILS the diff, so it can't reward-hack this oracle. runtests prints "<P>/<N> tests passed"
# and exits non-zero if any failed.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

BIN="$SRC/build-tests/cproc-qbe"
[ -x "$BIN" ] || { echo "missing $BIN — run mayhem/build.sh first" >&2; exit 2; }

# runtests reads CCQBE for the compiler under test; point it at the normal-flags oracle binary.
# It exits non-zero on any failure; capture output regardless so we can parse the summary line.
out="$(CCQBE="$BIN" ./runtests 2>&1)"; rc=$?
printf '%s\n' "$out" | tail -20

# Parse the final "<passed>/<total> tests passed" line.
passed=$(printf '%s\n' "$out" | sed -n 's/^\([0-9][0-9]*\)\/[0-9][0-9]* tests passed$/\1/p' | tail -1)
total=$( printf '%s\n' "$out" | sed -n 's/^[0-9][0-9]*\/\([0-9][0-9]*\) tests passed$/\1/p' | tail -1)

if [ -z "${passed:-}" ] || [ -z "${total:-}" ]; then
  echo "could not parse runtests summary ('<P>/<N> tests passed'); using exit code $rc" >&2
  emit_ctrf "cproc-runtests" 0 1
  exit $?
fi
failed=$(( total - passed ))

emit_ctrf "cproc-runtests" "$passed" "$failed"
