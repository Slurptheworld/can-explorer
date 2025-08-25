\
    #!/usr/bin/env bash
    set -euo pipefail

    # === CAN TP - Full installer for ICSim + CAN Explorer (Debian/Ubuntu/Kali) ===
    # - Installs system deps
    # - Builds ICSim
    # - Creates vcan0 helper
    # - Installs can-explorer in a Python venv (~/.venvs/canexp)
    # - Generates a lab launcher script
    #
    # Usage:
    #   bash install_can_tp.sh
    #
    # After install, run:
    #   ~/can-tp/start_can_lab.sh
    #
    # Optional: to launch the smooth acceleration demo after the lab starts:
    #   ~/can-tp/accelerate_loop.sh
    #
    # Tested on: Kali/Debian/Ubuntu (APT-based)

    RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'; NC='\033[0m'

    need_cmd() { command -v "$1" >/dev/null 2>&1; }

    echo -e "${YLW}[*] Checking prerequisites...${NC}"
    if ! need_cmd sudo; then
      echo -e "${RED}[!] 'sudo' is required. Please install/configure sudo and rerun.${NC}"
      exit 1
    fi

    if ! need_cmd apt; then
      echo -e "${RED}[!] This installer targets APT-based systems (Debian/Ubuntu/Kali).${NC}"
      exit 1
    fi

    # Create working folders
    mkdir -p "$HOME/can-tp" "$HOME/.venvs"

    echo -e "${YLW}[*] Installing system packages...${NC}"
    sudo apt update
    sudo apt install -y --no-install-recommends \
      build-essential git python3 python3-venv python3-pip \
      libsdl2-dev libsdl2-image-dev can-utils meson ninja-build

    echo -e "${YLW}[*] Cloning & building ICSim...${NC}"
    if [ ! -d "$HOME/can-tp/ICSim" ]; then
      git clone https://github.com/zombieCraig/ICSim.git "$HOME/can-tp/ICSim"
    else
      echo -e "${YLW}[i] ICSim repo already present, pulling latest...${NC}"
      git -C "$HOME/can-tp/ICSim" pull --ff-only || true
    fi

    # Build
    mkdir -p "$HOME/can-tp/ICSim/builddir"
    ( cd "$HOME/can-tp/ICSim" && meson setup builddir >/dev/null 2>&1 || true )
    ( cd "$HOME/can-tp/ICSim/builddir" && meson compile )

    echo -e "${YLW}[*] Creating vcan helper (requires sudo at runtime)...${NC}"
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

    echo -e "${YLW}[*] Installing can-explorer in a dedicated venv...${NC}"
    # Create venv
    if [ ! -d "$HOME/.venvs/canexp" ]; then
      python3 -m venv "$HOME/.venvs/canexp"
    fi
    # shellcheck source=/dev/null
    source "$HOME/.venvs/canexp/bin/activate"
    python -m pip install -U pip setuptools wheel
    python -m pip install can-explorer

    # Create a convenience wrapper
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/can-explorer-venv" <<'EOF'
    #!/usr/bin/env bash
    source "$HOME/.venvs/canexp/bin/activate"
    exec can-explorer "$@"
    EOF
    chmod +x "$HOME/.local/bin/can-explorer-venv"

    # Ensure ~/.local/bin on PATH for future shells
    if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
      if [ -f "$HOME/.bashrc" ]; then
        grep -q ".local/bin" "$HOME/.bashrc" || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
      fi
      if [ -f "$HOME/.zshrc" ]; then
        grep -q ".local/bin" "$HOME/.zshrc" || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
      fi
      export PATH="$HOME/.local/bin:$PATH"
    fi

    echo -e "${YLW}[*] Creating lab launcher...${NC}"
    cat > "$HOME/can-tp/start_can_lab.sh" <<'EOF'
    #!/usr/bin/env bash
    set -e
    IFACE=${1:-vcan0}
    ICSIM_DIR="$HOME/can-tp/ICSim/builddir"

    # 1) vcan up
    "$HOME/can-tp/vcan_up.sh" "$IFACE"

    # 2) start ICSim + controls in background terminals
    ( cd "$ICSIM_DIR" && ./icsim "$IFACE" ) &
    sleep 0.5
    ( cd "$ICSIM_DIR" && ./controls "$IFACE" ) &

    # 3) start can-explorer (venv)
    if command -v can-explorer-venv >/dev/null 2>&1; then
      can-explorer-venv &
    else
      echo "[i] can-explorer wrapper not in PATH; starting from venv..."
      source "$HOME/.venvs/canexp/bin/activate"
      can-explorer &
    fi

    echo "[*] Lab started. Use 'candump -tz ${IFACE}' to observe frames."
    EOF
    chmod +x "$HOME/can-tp/start_can_lab.sh"

    echo -e "${YLW}[*] Creating optional smooth acceleration demo...${NC}"
    cat > "$HOME/can-tp/accelerate_loop.sh" <<'EOF'
    #!/usr/bin/env bash
    # Smooth, human-like acceleration loop on ID 0x244 (ICSim)
    set -e
    IFACE=${1:-vcan0}
    STEP_SLEEP=${2:-0.1}   # 100 ms per step (10 Hz) -> realistic
    # Hand-picked valid values seen in logs (low -> mid -> high)
    VALUES=(0164 02A0 05A8 08B2 0D39 12F4 18F7 1DC0 234A)
    while true; do
      # up
      for v in "${VALUES[@]}"; do
        cansend "$IFACE" 244#000000"$v"
        sleep "$STEP_SLEEP"
      done
      # down
      for ((i=${#VALUES[@]}-1; i>=0; i--)); do
        cansend "$IFACE" 244#000000"${VALUES[$i]}"
        sleep "$STEP_SLEEP"
      done
    done
    EOF
    chmod +x "$HOME/can-tp/accelerate_loop.sh"

    echo -e "${GRN}[✓] Install complete.${NC}"
    echo -e "${GRN}Next steps:${NC}"
    echo "  1) Start the lab:   ~/can-tp/start_can_lab.sh"
    echo "  2) Optional demo:   ~/can-tp/accelerate_loop.sh   # press Ctrl+C to stop"
    echo "  3) Observe frames:  candump -tz vcan0"
