#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'; NC='\033[0m'
say(){ echo -e "${YLW}[*]${NC} $*"; }
ok(){  echo -e "${GRN}[✓]${NC} $*"; }
err(){ echo -e "${RED}[!]${NC} $*"; }

say "Initialisation…"
mkdir -p "$HOME/can-tp" "$HOME/.venvs" "$HOME/.local/bin"

command -v sudo >/dev/null 2>&1 || { err "sudo requis."; exit 1; }
command -v apt  >/dev/null 2>&1 || { err "Ce script vise Debian/Ubuntu/Kali (APT)."; exit 1; }

# --- Paquets système ---
say "Installation des paquets système (build, SDL2, CAN, Meson/Ninja)…"
sudo apt update
sudo apt install -y --no-install-recommends \
  build-essential git python3 python3-venv python3-pip \
  libsdl2-dev libsdl2-image-dev can-utils meson ninja-build

# --- ICSim : clone & build ---
ICSIM_REPO="https://github.com/zombieCraig/ICSim.git"
ICSIM_DIR="$HOME/can-tp/ICSim"
say "Clonage/MAJ ICSim…"
if [ -d "$ICSIM_DIR/.git" ]; then
  git -C "$ICSIM_DIR" pull --ff-only || true
else
  git clone "$ICSIM_REPO" "$ICSIM_DIR"
fi

say "Compilation ICSim…"
mkdir -p "$ICSIM_DIR/builddir"
( cd "$ICSIM_DIR" && meson setup builddir >/dev/null 2>&1 || true )
( cd "$ICSIM_DIR/builddir" && meson compile )
ok "ICSim compilé."

# --- Helper vcan0 ---
say "Création du helper vcan0…"
cat > "$HOME/can-tp/vcan_up.sh" <<'EOF'
#!/usr/bin/env bash
set -e
IFACE=${1:-vcan0}
sudo modprobe can
sudo modprobe vcan
if ip link show "$IFACE" >/dev/null 2>&1; then
  sudo ip link set up "$IFACE"
else
  sudo ip link add dev "$IFACE" type vcan
  sudo ip link set up "$IFACE"
fi
ip link show "$IFACE"
EOF
chmod +x "$HOME/can-tp/vcan_up.sh"
ok "vcan_up.sh prêt."

# --- can-explorer dans un VENV dédié (avec correctif dearpygui) ---
say "Installation de can-explorer dans un venv (avec fix dearpygui)…"
VENV="$HOME/.venvs/canexp"
[ -d "$VENV" ] || python3 -m venv "$VENV"
# shellcheck disable=SC1090
source "$VENV/bin/activate"

python -m pip install -U pip setuptools wheel
# ★ Correctif de conflit : dearpygui compatible
python -m pip install "dearpygui==1.10.1"
# ★ Version connue OK + résolveur legacy pour éviter ResolutionImpossible
python -m pip install "can-explorer==0.2.2" --use-deprecated=legacy-resolver

deactivate

# Wrapper pratique
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/can-explorer-venv" <<'EOF'
#!/usr/bin/env bash
source "$HOME/.venvs/canexp/bin/activate"
exec can-explorer "$@"
EOF
chmod +x "$HOME/.local/bin/can-explorer-venv"
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [ -f "$rc" ] && grep -q ".local/bin" "$rc" || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
done
export PATH="$HOME/.local/bin:$PATH"
ok "can-explorer installé (venv)."

# --- Lanceur de TP ---
say "Création du lanceur de TP…"
cat > "$HOME/can-tp/start_can_lab.sh" <<'EOF'
#!/usr/bin/env bash
set -e
IFACE=${1:-vcan0}
ICSIM_DIR="$HOME/can-tp/ICSim/builddir"

"$HOME/can-tp/vcan_up.sh" "$IFACE"

( cd "$ICSIM_DIR" && ./icsim "$IFACE" ) &
sleep 0.5
( cd "$ICSIM_DIR" && ./controls "$IFACE" ) &

if command -v can-explorer-venv >/dev/null 2>&1; then
  can-explorer-venv &
else
  source "$HOME/.venvs/canexp/bin/activate"
  can-explorer &
fi
echo "[*] TP lancé : candump -tz $IFACE pour sniffer."
EOF
chmod +x "$HOME/can-tp/start_can_lab.sh"
ok "start_can_lab.sh prêt."

# --- Démo d’accélération fluide ---
say "Ajout de la démo d’accélération fluide…"
cat > "$HOME/can-tp/accelerate_loop.sh" <<'EOF'
#!/usr/bin/env bash
set -e
IFACE=${1:-vcan0}
STEP_SLEEP=${2:-0.1}
VALUES=(0164 02A0 05A8 08B2 0D39 12F4 18F7 1DC0 234A)
while true; do
  for v in "${VALUES[@]}"; do
    cansend "$IFACE" 244#000000"$v"
    sleep "$STEP_SLEEP"
  done
  for ((i=${#VALUES[@]}-1; i>=0; i--)); do
    cansend "$IFACE" 244#000000"${VALUES[$i]}"
    sleep "$STEP_SLEEP"
  done
done
EOF
chmod +x "$HOME/can-tp/accelerate_loop.sh"
ok "accelerate_loop.sh prêt."

ok "Installation terminée 🎉"
echo
echo "➡️  Démarrer le TP : ~/can-tp/start_can_lab.sh"
echo "➡️  Sniffer       : candump -tz vcan0"
echo "➡️  Démo option   : ~/can-tp/accelerate_loop.sh vcan0 0.1"
