#!/usr/bin/env bash
# Provision the eval server (VM 390, 192.168.2.175) for the external benchmark
# suites. Idempotent: run it again after adding a suite and only the new parts
# do work.
#
# Runs ON the eval server. From the workstation:
#   scp external/provision/setup-eval-server.sh ubuntu@192.168.2.175:/tmp/
#   ssh ubuntu@192.168.2.175 'bash /tmp/setup-eval-server.sh'
set -euo pipefail

ROOT=/opt/evals
UV=/usr/local/bin/uv

log() { printf '\n== %s\n' "$*"; }

log "base directory"
sudo mkdir -p "$ROOT"
sudo chown "$USER":"$USER" "$ROOT"

log "uv"
if [[ ! -x "$UV" ]]; then
  curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/tmp/uvinst sh
  sudo install -m 0755 /tmp/uvinst/uv "$UV"
  sudo install -m 0755 /tmp/uvinst/uvx /usr/local/bin/uvx
fi
"$UV" --version

log "python toolchain"
"$UV" python install 3.12 2>/dev/null || true

# Each suite gets its own environment: they pin conflicting versions of
# openai/pydantic/datasets and will fight if they share one.
make_env() {
  local name="$1"; shift
  local dir="$ROOT/$name"
  if [[ ! -d "$dir/.venv" ]]; then
    mkdir -p "$dir"
    "$UV" venv --python 3.12 "$dir/.venv" >/dev/null
  fi
  if [[ $# -gt 0 ]]; then
    VIRTUAL_ENV="$dir/.venv" "$UV" pip install --quiet "$@"
  fi
  printf '  %-16s %s\n' "$name" "$("$dir/.venv/bin/python" -V)"
}

log "system libraries"
# bfcl-eval pulls qwen_agent, which imports soundfile unconditionally; soundfile
# needs libsndfile at the system level or `bfcl --help` dies on import.
missing=()
for pkg in libsndfile1 build-essential; do
  dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq "${missing[@]}"
fi
echo "  ok"

log "suite environments"
make_env tau2      "tau2 @ git+https://github.com/sierra-research/tau2-bench@main"
make_env bfcl      "bfcl-eval" "soundfile"
make_env swebench  "swebench"

log "docker access for the current user"
if ! docker info >/dev/null 2>&1; then
  sudo usermod -aG docker "$USER"
  echo "  added $USER to the docker group — log out and back in for it to apply"
else
  echo "  ok"
fi

log "CPU baseline"
# NumPy's wheels need x86-64-v2. A guest left on Proxmox's kvm64 default exposes
# only the x86-64 baseline, and every scientific package then dies at import
# with "NumPy was built with baseline optimizations (X86_V2) but your machine
# doesn't support (X86_V2)". Fix on the Proxmox node, not here:
#   qm set <vmid> --cpu host && qm stop <vmid> && qm start <vmid>
if grep -qw sse4_2 /proc/cpuinfo && grep -qw popcnt /proc/cpuinfo; then
  echo "  ok (x86-64-v2 present)"
else
  echo "  MISSING x86-64-v2 — the suites will fail at import."
  echo "  On the Proxmox node holding this guest:  qm set <vmid> --cpu host"
  echo "  then stop and start it (a CPU type change needs a full power cycle)."
fi

log "self-test"
for s in tau2 bfcl; do
  if "$ROOT/$s/.venv/bin/$s" --help >/dev/null 2>&1; then
    printf '  %-16s ok\n' "$s"
  else
    printf '  %-16s FAILS to start — see the CPU baseline note above\n' "$s"
  fi
done

log "disk"
df -h "$ROOT" | tail -1

cat <<'NOTE'

Note on the container-based suites. SWE-bench Verified and Terminal-Bench build
or pull one image per task; the full SWE-bench Verified image set is far larger
than this VM's disk. Run them against a fixed subset, and check free space
before and after. `df -h /opt/evals` is the number that matters.
NOTE
