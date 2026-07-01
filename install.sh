#!/bin/sh
# tracefield bootstrap installer.
#
# Clones-and-runs friendly: from a checkout, just run
#
#     ./install.sh
#
# It installs the tracefield CLI onto your PATH (cargo install) and runs a
# model-free smoke check. No Ollama instance or external API key is required
# for the default run.
#
# Flags:
#   --no-smoke   skip the mock flow smoke run
#   --test       also run the Rust test suite
#   -h, --help   show this help

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$SCRIPT_DIR"

RUN_SMOKE=1
RUN_TEST=0

usage() {
  awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

for arg in "$@"; do
  case "$arg" in
    --no-smoke) RUN_SMOKE=0 ;;
    --test) RUN_TEST=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'install.sh: unknown option: %s\n\n' "$arg" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -t 1 ]; then
  BOLD=$(printf '\033[1m'); DIM=$(printf '\033[2m'); RESET=$(printf '\033[0m')
  GREEN=$(printf '\033[32m'); RED=$(printf '\033[31m')
else
  BOLD=''; DIM=''; RESET=''; GREEN=''; RED=''
fi
step() { printf '%s==>%s %s%s%s\n' "$GREEN" "$RESET" "$BOLD" "$1" "$RESET"; }
info() { printf '    %s%s%s\n' "$DIM" "$1" "$RESET"; }
die()  { printf '%serror:%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }

if ! command -v cargo >/dev/null 2>&1; then
  die "Cargo not found.
    Install Rust/Cargo:
        https://www.rust-lang.org/tools/install
    then re-run ./install.sh"
fi

step "Installing tracefield CLI"
cargo install --path crates/tracefield-cli --locked --force
if ! command -v tracefield >/dev/null 2>&1; then
  die "tracefield installed but not found on PATH.
    Add cargo's bin directory (usually ~/.cargo/bin) to PATH, then re-run."
fi
info "installed $(command -v tracefield)"

step "Checking Rust workspace"
cargo check -p tracefield

if [ "$RUN_TEST" -eq 1 ]; then
  step "Running Rust test suite"
  cargo test
fi

if [ "$RUN_SMOKE" -eq 1 ]; then
  step "Smoke check: mock flow run"
  SMOKE_TMP=$(mktemp -d)
  trap 'rm -rf "$SMOKE_TMP"' EXIT
  tracefield new smoke --dir "$SMOKE_TMP/smoke" >/dev/null
  tracefield run --scenario-dir "$SMOKE_TMP/smoke" >/dev/null
  rm -rf "$SMOKE_TMP"
  trap - EXIT
  info "mock flow run OK"
fi

printf '\n%s✓ tracefield is ready.%s\n\n' "$GREEN$BOLD" "$RESET"
cat <<EOF
Next steps:

  tracefield doctor
  tracefield new smoke
  tracefield run --scenario-dir scenarios/smoke
  tracefield new my-review

For live runs with a local model, start Ollama and pull a model first
(see README.md / RUNNING.md). The default flow above needs no model at all.
EOF
