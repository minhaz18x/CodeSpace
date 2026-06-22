#!/usr/bin/env bash

# Enforce strict error handling
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# CORE CONFIGURATION & UNIVERSAL UI
# ==============================================================================
readonly SSH_KEY_PATH="${HOME}/.ssh/id_ed25519"
readonly AGENT_ENV="${HOME}/.ssh/persistent_git_agent.env"

# ANSI-C Quoted Colors
readonly C_RED=$'\033[1;31m'
readonly C_GREEN=$'\033[1;32m'
readonly C_YELLOW=$'\033[1;33m'
readonly C_BLUE=$'\033[1;34m'
readonly C_CYAN=$'\033[1;36m'
readonly C_MAGENTA=$'\033[1;35m'
readonly C_RST=$'\033[0m'
readonly C_DIM=$'\033[2m'

# UI Components
print_ascii() {
    clear
    echo "${C_CYAN}"
    cat << 'EOF'
 ╭──────────────────────────────────────────╮
 │  ███████╗███████╗██╗  ██╗    ███╗   ███╗ │
 │  ██╔════╝██╔════╝██║  ██║    ████╗ ████║ │
 │  ███████╗███████╗███████║    ██╔████╔██║ │
 │  ╚════██║╚════██║██╔══██║    ██║╚██╔╝██║ │
 │  ███████║███████║██║  ██║    ██║ ╚═╝ ██║ │
 │  ╚══════╝╚══════╝╚═╝  ╚═╝    ╚═╝     ╚═╝ │
 │       [ SSH CRYPTO MOUNT • PRO ]         │
 ╰──────────────────────────────────────────╯
EOF
    echo "${C_RST}"
}

ui_header() { echo -e "\n${C_MAGENTA}╭─── ${C_CYAN}$1${C_RST}"; }
ui_step()   { echo -e "${C_MAGENTA}│ ${C_BLUE}:: ${C_RST}$1"; }
ui_ok()     { echo -e "${C_MAGENTA}│ ${C_GREEN}✔  ${C_RST}$1"; }
ui_warn()   { echo -e "${C_MAGENTA}│ ${C_YELLOW}⚠  $1${C_RST}"; }
ui_end()    { echo -e "${C_MAGENTA}╰────────────────────────────────────────${C_RST}"; }
ui_err()    { echo -e "\n${C_RED} [✖] FATAL: $1${C_RST}" >&2; exit 1; }

# ==============================================================================
# MAIN EXECUTION LOGIC
# ==============================================================================
print_ascii
ui_header "SECURITY SUBSYSTEM INITIALIZATION"

mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh"

# 1. Check if the current terminal session already has a functional agent
if ssh-add -l >/dev/null 2>&1; then
    ui_ok "SSH Agent is already active and keys are fully loaded!"
    ui_end
    exit 0
fi

# 2. Try to source existing environment tracking file
if [ -f "$AGENT_ENV" ]; then
    # shellcheck source=/dev/null
    source "$AGENT_ENV" >/dev/null 2>&1 || true
fi

# 3. If the background process is dead or missing, spin up a fresh daemon
if [ -z "${SSH_AUTH_SOCK:-}" ] || ! kill -0 "${SSH_AGENT_PID:-}" 2>/dev/null; then
    ui_step "Stale session detected. Spawning fresh background SSH daemon..."
    eval "$(ssh-agent -s)" > /dev/null
    echo "export SSH_AUTH_SOCK=\"${SSH_AUTH_SOCK}\"" > "$AGENT_ENV"
    echo "export SSH_AGENT_PID=\"${SSH_AGENT_PID}\"" >> "$AGENT_ENV"
    chmod 600 "$AGENT_ENV"
else
    ui_step "Connected to existing background SSH daemon process."
fi

# 4. Bind the cryptographic key to the active daemon session
if [ -f "$SSH_KEY_PATH" ]; then
    ui_step "Mounting key to subsystem. Please provide passphrase if prompted..."
    if ssh-add "$SSH_KEY_PATH"; then
        ui_ok "Key successfully loaded into the cryptographic agent."
    else
        ui_err "Failed to bind SSH key to daemon."
    fi
else
    ui_err "Target key missing at location: $SSH_KEY_PATH"
fi

ui_ok "ENVIRONMENT HEALED SUCCESSFULLY!"
echo -e "${C_MAGENTA}│${C_RST}"
echo -e "${C_MAGENTA}│${C_RST} ${C_YELLOW}👉 IMPORTANT:${C_RST} To apply these credentials to your current terminal context,"
echo -e "${C_MAGENTA}│${C_RST}    you must execute the following command manually:"
echo -e "${C_MAGENTA}│${C_RST}    ${C_CYAN}source $AGENT_ENV${C_RST}"
ui_end
