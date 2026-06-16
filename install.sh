#!/bin/sh
# tracefield bootstrap installer.
#
# Clones-and-runs friendly: from a checkout, just run
#
#     ./install.sh
#
# It installs the pinned toolchain (via mise, if present), fetches deps,
# compiles, and runs a model-free smoke check so you know it works.
#
# Flags:
#   --no-smoke   skip the mock smoke run (just deps + compile)
#   --test       also run the full ExUnit suite (mix test)
#   -h, --help   show this help
#
# No network model is required for the default run: tracefield ships a mock
# adapter, so the smoke check runs with no Ollama / API key at all.

set -eu

# --- locate the repo root (this script's directory) so CWD doesn't matter ----
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$SCRIPT_DIR"

RUN_SMOKE=1
RUN_TEST=0

usage() {
  # print the leading comment block (skip the shebang, stop at first code line)
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

# --- pretty output -----------------------------------------------------------
if [ -t 1 ]; then
  BOLD=$(printf '\033[1m'); DIM=$(printf '\033[2m'); RESET=$(printf '\033[0m')
  GREEN=$(printf '\033[32m'); YELLOW=$(printf '\033[33m'); RED=$(printf '\033[31m')
else
  BOLD=''; DIM=''; RESET=''; GREEN=''; YELLOW=''; RED=''
fi
step() { printf '%s==>%s %s%s%s\n' "$GREEN" "$RESET" "$BOLD" "$1" "$RESET"; }
info() { printf '    %s%s%s\n' "$DIM" "$1" "$RESET"; }
warn() { printf '%swarning:%s %s\n' "$YELLOW" "$RESET" "$1" >&2; }
die()  { printf '%serror:%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }

# --- pick a toolchain runner: prefer mise, fall back to a bare PATH mix -------
# MIX is the argv prefix used to invoke mix; e.g. "mise exec -- mix" or "mix".
if command -v mise >/dev/null 2>&1; then
  step "Toolchain: using mise ($(mise --version 2>/dev/null | head -1))"
  # mise refuses to read an untrusted config; trust this repo's mise.toml.
  mise trust --quiet 2>/dev/null || mise trust 2>/dev/null || true
  info "installing pinned Elixir/Erlang from mise.toml ..."
  mise install
  MIX="mise exec -- mix"
elif command -v mix >/dev/null 2>&1; then
  warn "mise not found; falling back to the mix on your PATH."
  warn "the toolchain version is not pinned in this mode (mise.toml is ignored)."
  ELIXIR_V=$(elixir --version 2>/dev/null | sed -n 's/^Elixir \([0-9][0-9.]*\).*/\1/p' | head -1)
  info "found Elixir ${ELIXIR_V:-unknown}"
  MIX="mix"
else
  die "no toolchain found.
    Install mise (recommended) so the pinned Elixir/Erlang are used:
        https://mise.jdx.io/getting-started.html
    then re-run ./install.sh
    — or install Elixir ~> 1.18 yourself and ensure 'mix' is on your PATH."
fi

# helper that runs mix with the chosen prefix
run_mix() {
  # shellcheck disable=SC2086
  $MIX "$@"
}

# --- fetch deps + compile ----------------------------------------------------
step "Fetching Hex dependencies"
run_mix deps.get

step "Compiling"
run_mix compile

# --- smoke check (mock adapter, no model needed) -----------------------------
if [ "$RUN_SMOKE" -eq 1 ]; then
  step "Smoke check: mock phase1 (no model required)"
  if run_mix tracefield.phase1 --adapter mock --n 4 >/dev/null 2>&1; then
    info "mock run OK"
  else
    warn "smoke run failed — compile succeeded, but 'mix tracefield.phase1 --adapter mock' errored."
    warn "re-run it directly to see the output:  $MIX tracefield.phase1 --adapter mock --n 4"
  fi
fi

# --- optional full test suite ------------------------------------------------
if [ "$RUN_TEST" -eq 1 ]; then
  step "Running test suite"
  run_mix test
fi

# --- done --------------------------------------------------------------------
printf '\n%s✓ tracefield is ready.%s\n\n' "$GREEN$BOLD" "$RESET"
cat <<EOF
Next steps:

  # see every task, grouped by purpose
  $MIX tracefield

  # check your environment (toolchain, Ollama, API keys, CLI adapters)
  $MIX tracefield.doctor

  # consult the team on a scenario (mock adapter, no model)
  $MIX tracefield.consult --scenario-dir scenarios/enterprise-hi --adapter mock

  # scaffold your own scenario
  $MIX tracefield.new my-review

For live runs with a local model, start Ollama and pull a model first
(see README.md / RUNNING.md). The default flow above needs no model at all.
EOF
