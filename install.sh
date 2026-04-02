#!/usr/bin/env bash
#
# OpenMatrix — One-Command Install
#
# Checks prerequisites, installs dependencies, pulls models,
# and launches Trinity's setup wizard.
#

set -euo pipefail

GREEN='\033[32m'
BRIGHT_GREEN='\033[92m'
WHITE='\033[97m'
RED='\033[31m'
YELLOW='\033[33m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRED_PYTHON="3.10"
REQUIRED_NODE="22"

# ── Helpers ────────────────────────────────────────────────────────────

info()  { echo -e "  ${GREEN}[OK]${RESET} $1"; }
warn()  { echo -e "  ${YELLOW}[!!]${RESET} $1"; }
fail()  { echo -e "  ${RED}[FAIL]${RESET} $1"; exit 1; }
step()  { echo -e "\n  ${BOLD}$1${RESET}"; }

version_gte() {
    # Returns 0 if $1 >= $2 (dot-separated version comparison)
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

# ── Banner ─────────────────────────────────────────────────────────────

echo ""
echo -e "  ${BRIGHT_GREEN}${BOLD}┌─────────────────────────────────────┐${RESET}"
echo -e "  ${BRIGHT_GREEN}${BOLD}│         OpenMatrix Installer        │${RESET}"
echo -e "  ${BRIGHT_GREEN}${BOLD}│         v3.0.0                      │${RESET}"
echo -e "  ${BRIGHT_GREEN}${BOLD}└─────────────────────────────────────┘${RESET}"
echo ""

# ── Step 1: Check Python ──────────────────────────────────────────────

step "Checking Python..."

PYTHON_CMD=""
for cmd in python3 python; do
    if command -v "$cmd" &>/dev/null; then
        PY_VER=$("$cmd" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null || echo "0.0")
        if version_gte "$PY_VER" "$REQUIRED_PYTHON"; then
            PYTHON_CMD="$cmd"
            break
        fi
    fi
done

if [ -z "$PYTHON_CMD" ]; then
    fail "Python ${REQUIRED_PYTHON}+ is required but not found. Install it first."
fi
info "Python $PY_VER ($PYTHON_CMD)"

# ── Step 2: Check Node.js ─────────────────────────────────────────────

step "Checking Node.js..."

if command -v node &>/dev/null; then
    NODE_VER=$(node -v 2>/dev/null | sed 's/^v//' | cut -d. -f1)
    if [ "$NODE_VER" -ge "$REQUIRED_NODE" ] 2>/dev/null; then
        info "Node.js v$(node -v | sed 's/^v//')"
    else
        warn "Node.js ${REQUIRED_NODE}+ recommended. Found v$(node -v | sed 's/^v//')"
        warn "Some features may not work. Install from https://nodejs.org"
    fi
else
    warn "Node.js not found. Optional but recommended."
    warn "Install from https://nodejs.org"
fi

# ── Step 3: Install Python dependencies ───────────────────────────────

step "Installing Python dependencies..."

REQ_FILE="${SCRIPT_DIR}/requirements.txt"

if [ ! -f "$REQ_FILE" ]; then
    # Generate requirements.txt if it doesn't exist
    cat > "$REQ_FILE" << 'REQEOF'
# OpenMatrix Runtime Dependencies
fastapi>=0.100.0
uvicorn>=0.20.0
httpx>=0.24.0
web3>=6.0.0
eth-account>=0.10.0
eth-abi>=4.0.0
requests>=2.28.0
pydantic>=2.0.0
REQEOF
    info "Generated requirements.txt"
fi

if $PYTHON_CMD -m pip install -r "$REQ_FILE" --quiet 2>/dev/null; then
    info "Python dependencies installed"
elif $PYTHON_CMD -m pip install -r "$REQ_FILE" --quiet --break-system-packages 2>/dev/null; then
    info "Python dependencies installed (system packages)"
else
    warn "Could not install some dependencies. Try manually: pip install -r requirements.txt"
fi

# ── Step 4: Check/Install Ollama ──────────────────────────────────────

step "Checking Ollama..."

if command -v ollama &>/dev/null; then
    OLLAMA_VER=$(ollama --version 2>/dev/null | head -1 || echo "installed")
    info "Ollama found: $OLLAMA_VER"
else
    echo -e "  ${DIM}Ollama is not installed. It provides free local AI models.${RESET}"
    echo -e "  ${DIM}Install it? This is optional but recommended. [Y/n]${RESET}"
    read -r INSTALL_OLLAMA
    INSTALL_OLLAMA="${INSTALL_OLLAMA:-Y}"

    if [[ "$INSTALL_OLLAMA" =~ ^[Yy] ]]; then
        echo -e "  ${DIM}Installing Ollama...${RESET}"
        if curl -fsSL https://ollama.com/install.sh | sh 2>/dev/null; then
            info "Ollama installed"
        else
            warn "Ollama install failed. Install manually: https://ollama.com"
        fi
    else
        info "Skipping Ollama (you can install it later)"
    fi
fi

# ── Step 5: Pull Ollama model ─────────────────────────────────────────

if command -v ollama &>/dev/null; then
    step "Pulling mistral:7b-instruct model..."

    # Check if model already exists
    if ollama list 2>/dev/null | grep -q "mistral:7b-instruct"; then
        info "mistral:7b-instruct already pulled"
    else
        echo -e "  ${DIM}Downloading mistral:7b-instruct (~4.1GB). This may take a few minutes.${RESET}"
        if ollama pull mistral:7b-instruct 2>/dev/null; then
            info "mistral:7b-instruct ready"
        else
            warn "Could not pull model. Is Ollama running? Try: ollama serve"
        fi
    fi
fi

# ── Step 6: Generate config from example ──────────────────────────────

step "Setting up configuration..."

EXAMPLE_CONFIG="${SCRIPT_DIR}/openmatrix.config.example.json"
CONFIG_FILE="${SCRIPT_DIR}/openmatrix.config.json"

if [ ! -f "$EXAMPLE_CONFIG" ]; then
    cat > "$EXAMPLE_CONFIG" << 'CFGEOF'
{
  "version": "3.0.0",
  "provider": {
    "primary": "ollama",
    "model": "mistral:7b-instruct",
    "fallback": "ollama",
    "fallback_model": "mistral:7b-instruct"
  },
  "channels": {},
  "agents": {
    "neo": {"enabled": true},
    "trinity": {"enabled": true},
    "morpheus": {"enabled": true}
  }
}
CFGEOF
    info "Generated openmatrix.config.example.json"
fi

if [ -f "$CONFIG_FILE" ]; then
    info "openmatrix.config.json already exists (keeping current config)"
else
    cp "$EXAMPLE_CONFIG" "$CONFIG_FILE"
    info "Created openmatrix.config.json from example"
fi

# ── Step 7: Create .env if needed ─────────────────────────────────────

ENV_FILE="${SCRIPT_DIR}/.env"
if [ ! -f "$ENV_FILE" ]; then
    cat > "$ENV_FILE" << 'ENVEOF'
# OpenMatrix Environment Variables
# Add your API keys and bot tokens here

# Model provider keys (uncomment the ones you use)
# NVIDIA_API_KEY=your-nvidia-key
# OPENAI_API_KEY=your-openai-key
# ANTHROPIC_API_KEY=your-anthropic-key
# GOOGLE_API_KEY=your-google-key

# Telegram bot tokens (create via @BotFather)
# TELEGRAM_BOT_TOKEN_NEO=your-neo-token
# TELEGRAM_BOT_TOKEN_TRINITY=your-trinity-token
# TELEGRAM_BOT_TOKEN_MORPHEUS=your-morpheus-token
ENVEOF
    info "Created .env template"
fi

# ── Step 8: Create data directories ──────────────────────────────────

step "Creating data directories..."

for dir in data/memory data/goals data/documents data/triggers data/execution \
           data/tasks data/mcp data/models data/streams data/proactive \
           data/attestations data/approvals; do
    mkdir -p "${SCRIPT_DIR}/${dir}"
done
info "Data directories ready"

# ── Done ──────────────────────────────────────────────────────────────

echo ""
echo -e "  ${BRIGHT_GREEN}${BOLD}Installation complete.${RESET}"
echo ""
echo -e "  ${DIM}Next steps:${RESET}"
echo -e "    1. Run the setup wizard:  ${WHITE}$PYTHON_CMD -m matrix.cli.setup_wizard${RESET}"
echo -e "    2. Or start directly:     ${WHITE}$PYTHON_CMD -m matrix.cli.boot${RESET}"
echo ""

# ── Launch wizard if interactive ──────────────────────────────────────

if [ -t 0 ]; then
    echo -e "  ${DIM}Run Trinity's setup wizard now? [Y/n]${RESET}"
    read -r RUN_WIZARD
    RUN_WIZARD="${RUN_WIZARD:-Y}"

    if [[ "$RUN_WIZARD" =~ ^[Yy] ]]; then
        cd "$SCRIPT_DIR"
        $PYTHON_CMD -m matrix.cli.setup_wizard
    fi
fi
