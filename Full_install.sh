#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'; NC='\033[0m'
say(){ echo -e "${YLW}[*]${NC} $*"; }
ok(){  echo -e "${GRN}[✓]${NC} $*"; }
err(){ echo -e "${RED}[!]${NC} $*"; }

# --- Préambule & dossiers ---
say "Initialisation…"
mkdir -p "$HOME/can-tp" "$HOME/.venvs" "$HOME/.local/bin"

if ! command -v sudo >/dev/null 2>&1; then err "sudo requis."; exit 1; fi
if ! command -v apt  >/dev/null 2>&1; then err "Ce script vise Debian/Ubuntu/Kali (APT)."; exit 1; fi

# --- Paquets système ---
say "Installation des paquets système (build, SDL2, CAN, Meson/Ninja)…"
sudo apt update
sudo apt install -y --no-install-recommends \
  build-essential git python3 python3-venv python3-pip \
  libsdl2-dev libsdl2-image-dev can-utils meson ninja-build

ok "Paquets système OK."

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
ok "ICSim compilé : $ICSIM_DIR/builddir/icsim & controls"

# --- Script helper vcan0 ---
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

# --- can-explorer dans un VENV dédié ---
say "Installation de can-explorer dans un venv…"
VENV="$HOME/.venvs/canexp"
[ -d "$VENV" ] || python3 -m venv "$VENV"
# shellcheck disable=SC1090
source "$VENV/bin/activate"
python -m pip install -U pip setuptools wheel
python -m pip install can-explorer
deactivate

# Wrapper pour lancer facilement can-explorer depuis le venv
cat > "$HOME/.local/bin/can-explorer-venv" <<'EOF'
#!/usr/bin/env bash
# Lance can-explorer depuis le venv ~/.venvs/canexp
source "$HOME/.venvs/canexp/bin/activate"
exec can-explorer "$@"
EOF
chmod +x "$HOME/.local/bin/can-explorer-venv"

# S'assurer que ~/.local/bin est dans le PATH futurs shells
if ! grep -qs '\.local/bin' "$HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi
if [ -f "$HOME/.zshrc" ] && ! grep -qs '\.local/bin' "$HOME/.zshrc"; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
fi
export PATH="$HOME/.local/bin:$PATH"
ok "can-explorer installé et wrapper disponible."

# --- Lanceur de labo ---
say "Création du lanceur de TP…"
cat > "$HOME/can-tp/start_can_lab.sh" <<'EOF'
#!/usr/bin/env bash
set -e
IFACE=${1:-vcan0}
ICSIM_DIR="$HOME/can-tp/ICSim/builddir"

# 1) Interface CAN virtuelle
"$HOME/can-tp/vcan_up.sh" "$IFACE"

# 2) ICSim + controls
( cd "$ICSIM_DIR" && ./icsim "$IFACE" ) &
sleep 0.5
( cd "$ICSIM_DIR" && ./controls "$IFACE" ) &

# 3) CAN Explorer (venv)
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

# --- Démo d’accélération fluide optionnelle ---
say "Ajout de la démo d’accélération fluide…"
cat > "$HOME/can-tp/accelerate_loop.sh" <<'EOF'
#!/usr/bin/env bash
# Boucle montée/descente réaliste sur ID 0x244 (ICSim)
set -e
IFACE=${1:-vcan0}
STEP_SLEEP=${2:-0.1}   # 100 ms = 10 Hz
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
echo "➡️  Démarrer le TP :"
echo "    ~/can-tp/start_can_lab.sh"
echo "➡️  Sniffer :"
echo "    candump -tz vcan0"
echo "➡️  Démo d'accélération (optionnel) :"
echo "    ~/can-tp/accelerate_loop.sh vcan0 0.1   # Ctrl+C pour arrêter"
