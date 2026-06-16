#!/bin/sh
# tracefield bootstrap installer.
#
# Clones-and-runs friendly: from a checkout, just run
#
#     ./install.sh
#
# It builds the Rust CLI and runs a model-free smoke check. No Ollama instance
# or external API key is required for the default run.
#
# Flags:
#   --no-smoke   skip the mock consult smoke run
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

step "Building Rust CLI"
cargo build --release -p tracefield
info "built ./target/release/tracefield"

step "Checking Rust workspace"
cargo check -p tracefield

if [ "$RUN_TEST" -eq 1 ]; then
  step "Running Rust test suite"
  cargo test
fi

if [ "$RUN_SMOKE" -eq 1 ]; then
  step "Smoke check: mock consult"
  ./target/release/tracefield consult --scenario-dir scenarios/generic-smoke --adapter mock >/dev/null
  info "mock consult OK"
fi

printf '\n%s✓ tracefield is ready.%s\n\n' "$GREEN$BOLD" "$RESET"
cat <<EOF
Next steps:

  ./target/release/tracefield doctor
  ./target/release/tracefield consult --scenario-dir scenarios/generic-smoke --adapter mock
  ./target/release/tracefield new my-review

For live runs with a local model, start Ollama and pull a model first
(see README.md / RUNNING.md). The default flow above needs no model at all.
EOF
