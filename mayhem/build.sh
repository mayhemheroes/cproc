#!/usr/bin/env bash
# cproc/mayhem/build.sh — build the cproc C front-end + QBE backend as the fuzz target, plus a clean
# normal-flags build of the same binary for cproc's own golden-output test suite (mayhem/test.sh).
#
# cproc is a small C11 compiler: `./configure && make` builds `cproc-qbe` (the binary that PARSES C
# and emits QBE IR — the whole front end: scanner, preprocessor, parser, decl/expr/stmt/type analysis,
# plus the QBE backend). The Mayhem target is FILE-INPUT (CLI): `cproc-qbe @@` runs the compiler on the
# fuzz bytes as a C source file. No external deps, no libFuzzer harness — the natural fuzz surface is
# the compiler itself on a source file.
#
# Two builds from the same source tree (configure writes config.h/config.mk at the repo root, in-tree
# objects), done sequentially:
#   (1) NORMAL-flags build  -> build-tests/cproc-qbe   (honest oracle for test.sh; no sanitizer noise)
#   (2) SANITIZED build      -> /mayhem/cproc-qbe        (the fuzz target; project built WITH $SANITIZER_FLAGS)
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs from the ENV, overridable. SANITIZER_FLAGS uses `=` (not `:=`) so an explicit empty value
# (--build-arg SANITIZER_FLAGS=) is honored → no-sanitizer build (the compiler's natural crash). cproc
# has no external libs to link, so the empty-sanitizer build links cleanly with no extra flags.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
: "${CC:=clang}" ; : "${CXX:=clang++}"
: "${MAYHEM_JOBS:=$(nproc)}"
export SANITIZER_FLAGS CC MAYHEM_JOBS

cd "$SRC"

# cproc's configure bakes the C dialect/warnings into CFLAGS via config.mk; we override CFLAGS so the
# project itself is compiled with our flags. -Wno-* keep cproc's own clean-build warnings from being
# fatal noise; they don't affect codegen. We pass flags to BOTH compile (CFLAGS) and link (LDFLAGS) so
# the sanitizer runtime is linked into the final binary.
COMMON_CFLAGS="-Wall -Wno-parentheses -Wno-switch -Wno-unused -pipe"

# ---------------------------------------------------------------------------
# (1) TEST build — cproc's OWN flags, no sanitizer. Produces the golden-output oracle binary that
#     mayhem/test.sh feeds to ./runtests. Built first, stashed, then the tree is cleaned for the
#     sanitized build (the Makefile is in-tree, so the two builds can't coexist in one objdir).
# ---------------------------------------------------------------------------
make clean >/dev/null 2>&1 || true
rm -f config.h config.mk
./configure CC="$CC" CFLAGS="$COMMON_CFLAGS -O2 -g"
make -j"$MAYHEM_JOBS" cproc-qbe
mkdir -p "$SRC/build-tests"
cp -f cproc-qbe "$SRC/build-tests/cproc-qbe"

# ---------------------------------------------------------------------------
# (2) FUZZ build — the PROJECT itself compiled WITH $SANITIZER_FLAGS so the fuzzed code is instrumented
#     (ASan+UBSan, halting, by default). cproc-qbe is the file-input Mayhem target at /mayhem/cproc-qbe.
#
#     LeakSanitizer OFF for this target: cproc is a short-lived compiler that, by design, never frees —
#     it relies on process exit to reclaim memory (arena-by-exit). LSan (which runs at exit, as part of
#     ASan) therefore reports "leaks" on essentially EVERY non-trivial input, which would flood the
#     fuzzer with spurious, benign crashes and stop it exploring real defects. We disable ONLY leak
#     detection (keeping ASan's heap/stack/global overflow + use-after-free checks and all of UBSan,
#     still halting). Baked into the binary via a weak __asan_default_options so it holds no matter how
#     cproc-qbe is launched (fuzzer, standalone repro, smoke test) — not only when ASAN_OPTIONS is set.
#     (Cohort precedent: espeak-ng/flac/frr export ASAN_OPTIONS=detect_leaks=0; asteria/calc set it in
#     the Mayhemfile env. We also set it in mayhem/Mayhemfile_cproc-qbe for documentation.)
make clean >/dev/null 2>&1 || true
rm -f config.h config.mk
./configure CC="$CC" CFLAGS="$COMMON_CFLAGS $SANITIZER_FLAGS" LDFLAGS="$SANITIZER_FLAGS"
make -j"$MAYHEM_JOBS" cproc-qbe
# When ASan is active, relink cproc-qbe with a weak __asan_default_options override that turns LSan off
# (the override only takes effect if ASan is linked in; when SANITIZER_FLAGS is empty we skip it).
if printf '%s' "$SANITIZER_FLAGS" | grep -q address; then
  cat > /tmp/asan_opts.c <<'EOF'
/* Disable LeakSanitizer for cproc-qbe: cproc never frees by design (arena-by-exit), so LSan would
   report benign leaks on nearly every input. Keeps the rest of ASan + UBSan active and halting. */
const char *__asan_default_options(void) { return "detect_leaks=0"; }
EOF
  $CC $SANITIZER_FLAGS -c /tmp/asan_opts.c -o /tmp/asan_opts.o
  # Relink the same object set the Makefile produced, plus our override object.
  $CC $SANITIZER_FLAGS -o cproc-qbe \
      attr.o decl.o eval.o expr.o init.o main.o map.o pp.o scan.o scope.o stmt.o targ.o \
      token.o tree.o type.o utf.o util.o qbe.o /tmp/asan_opts.o
fi
# $SRC is /mayhem and the build is in-tree, so cproc-qbe already lands at /mayhem/cproc-qbe; only
# copy if a non-standard $SRC put it elsewhere (avoid cp's same-file error).
[ "$SRC/cproc-qbe" -ef /mayhem/cproc-qbe ] || cp -f "$SRC/cproc-qbe" /mayhem/cproc-qbe

echo "build.sh: built /mayhem/cproc-qbe (sanitized fuzz target) and build-tests/cproc-qbe (test oracle)"
ls -l /mayhem/cproc-qbe "$SRC/build-tests/cproc-qbe"
