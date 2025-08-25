#!/usr/bin/env bash
set -euo pipefail
RED='\033[0;31m'; YLW='\033[1;33m'; GRN='\033[0;32m'; NC='\033[0m'
say(){ echo -e "${YLW}[*]${NC} $*"; } ; ok(){ echo -e "${GRN}[✓]${NC} $*"; } ; err(){ echo -e "${RED}[!]${NC} $*"; }

mkdir -p "$HOME/can-tp" "$HOME/.venvs" "$HOME/.local/bin"

command -v sudo >/dev/null || { err "sudo requis"; exit 1; }
command -v apt  >/dev/null || { err "Debian/Ubuntu/Kali requis (APT)"; exit 1; }

say "Paquets système…"
sudo apt update
sudo apt install -y --no-install-recommends \
  build-essential git python3 python3-venv python3-pip \
  libsdl2-dev libsdl2-image-dev can-utils meson ninja-build \
  python3.12 python3.12-venv

# ICSim
say "ICSim clone/build…"
ICSIM_DIR="$HOME/can-tp/ICSim"
[ -d "$ICSIM_DIR/.git" ] && git -C "$ICSIM_DIR" pull --ff-only || git clone https://github.com/zombieCraig/ICSim.git "$ICSIM_DIR"
mkdir -p "$ICSIM_DIR/builddir"
( cd "$ICSIM_DIR" && meson setup builddir >/dev/null 2>&1 || true )
( cd "$ICSIM_DIR/builddir" && meson compile )
ok "ICSim OK."

# vcan helper
say "vcan helper…"
cat > "$HOME/can-tp/vcan_up.sh" <<'EOF'
#!/usr/bin/env bash
set -e
IFACE=${1:-vcan0}
sudo modprobe can
sudo modprobe vcan
ip link show "$IFACE" >/dev/null 2>&1 && sudo ip link set up "$IFACE" || {
  sudo ip link add dev "$IFACE" type vcan
  sudo ip link set up "$IFACE"
}
ip link show "$IFACE"
EOF
chmod +x "$HOME/can-tp/vcan_up.sh"

# can-explorer dans venv Python 3.12
say "Venv Python 3.12 + can-explorer…"
VENV="$HOME/.venvs/canexp312"
python3.12 -m venv "$VENV"
source "$VENV/bin/activate"
python -m pip install -U pip setuptools wheel
python -m pip install "dearpygui==1.10.1"
python -m pip install "can-explorer==0.2.2" --use-deprecated=legacy-resolver
deactivate
ok "can-explorer installé dans $VENV."

# wrapper
cat > "$HOME/.local/bin/can-explorer-venv" <<'EOF'
#!/usr/bin/env bash
source "$HOME/.venvs/canexp312/bin/activate"
exec can-explorer "$@"
EOF
chmod +x "$HOME/.local/bin/can-explorer-venv"
grep -q ".local/bin" "$HOME/.zshrc" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
grep -q ".local/bin" "$HOME/.bashrc" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
export PATH="$HOME/.local/bin:$PATH"

# Lanceur TP
say "start_can_lab.sh…"
cat > "$HOME/can-tp/start_can_lab.sh" <<'EOF'
#!/usr/bin/env bash
set -e
IFACE=${1:-vcan0}
ICSIM_DIR="$HOME/can-tp/ICSim/builddir"
"$HOME/can-tp/vcan_up.sh" "$IFACE"
( cd "$ICSIM_DIR" && ./icsim "$IFACE" ) & sleep 0.5
( cd "$ICSIM_DIR" && ./controls "$IFACE" ) &
can-explorer-venv &>/dev/null & || { source "$HOME/.venvs/canexp312/bin/activate"; can-explorer & }
echo "[*] TP lancé : candump -tz $IFACE pour sniffer."
EOF
chmod +x "$HOME/can-tp/start_can_lab.sh"

# Démo accélération
cat > "$HOME/can-tp/accelerate_loop.sh" <<'EOF'
#!/usr/bin/env bash
set -e
IFACE=${1:-vcan0} ; STEP=${2:-0.1}
VALUES=(0164 02A0 05A8 08B2 0D39 12F4 18F7 1DC0 234A)
while true; do
  for v in "${VALUES[@]}"; do cansend "$IFACE" 244#000000"$v"; sleep "$STEP"; done
  for ((i=${#VALUES[@]}-1;i>=0;i--)); do cansend "$IFACE" 244#000000"${VALUES[$i]}"; sleep "$STEP"; done
done
EOF
chmod +x "$HOME/can-tp/accelerate_loop.sh"

ok "Install terminée 🎉"
echo "➡  Démarrer :  ~/can-tp/start_can_lab.sh"
echo "➡  Sniffer  :  candump -tz vcan0"
echo "➡  Démo     :  ~/can-tp/accelerate_loop.sh vcan0 0.1"
