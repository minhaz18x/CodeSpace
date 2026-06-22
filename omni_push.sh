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
    echo "${C_BLUE}"
    cat << 'EOF'
 ╭──────────────────────────────────────────╮
 │  ██████╗ ██╗   ██╗███████╗██╗  ██╗       │
 │  ██╔══██╗██║   ██║██╔════╝██║  ██║       │
 │  ██████╔╝██║   ██║███████╗███████║       │
 │  ██╔═══╝ ██║   ██║╚════██║██╔══██║       │
 │  ██║     ╚██████╔╝███████║██║  ██║       │
 │  ╚═╝      ╚═════╝ ╚══════╝╚═╝  ╚═╝       │
 │       [ KERNEL CHUNK PUSHER • PRO ]      │
 ╰──────────────────────────────────────────╯
EOF
    echo "${C_RST}"
}

ui_header() { echo -e "\n${C_BLUE}╭─── ${C_CYAN}$1${C_RST}"; }
ui_step()   { echo -e "${C_BLUE}│ ${C_MAGENTA}:: ${C_RST}$1"; }
ui_ok()     { echo -e "${C_BLUE}│ ${C_GREEN}✔  ${C_RST}$1"; }
ui_warn()   { echo -e "${C_BLUE}│ ${C_YELLOW}⚠  $1${C_RST}"; }
ui_end()    { echo -e "${C_BLUE}╰────────────────────────────────────────${C_RST}"; }
ui_err()    { echo -e "\n${C_RED} [✖] FATAL: $1${C_RST}" >&2; exit 1; }

# ==============================================================================
# WORKFLOW MODULES
# ==============================================================================

probe_push_config() {
    ui_header "TRANSMISSION CONFIGURATION"
    
    local def_ssh="git@github.com:pa-xe/android_kernel_xiaomi_miatoll.git"
    local def_branch="lineage-22.2"
    local def_base="upstream/lineage-20"

    echo -e "${C_BLUE}│${C_RST} ${C_DIM}Press [ENTER] to use defaults.${C_RST}"
    
    read -r -p "${C_BLUE}│${C_RST} 🔑 Target SSH Repo [${C_GREEN}$def_ssh${C_RST}]: " TARGET_REPO_SSH
    TARGET_REPO_SSH="${TARGET_REPO_SSH:-$def_ssh}"
    
    read -r -p "${C_BLUE}│${C_RST} 🌿 Remote Branch   [${C_GREEN}$def_branch${C_RST}]: " TARGET_REMOTE_BRANCH
    TARGET_REMOTE_BRANCH="${TARGET_REMOTE_BRANCH:-$def_branch}"
    
    read -r -p "${C_BLUE}│${C_RST} 🔱 Upstream Base   [${C_GREEN}$def_base${C_RST}]: " UPSTREAM_BASE
    UPSTREAM_BASE="${UPSTREAM_BASE:-$def_base}"

    REPO_NAME=$(basename "${TARGET_REPO_SSH}" .git)
    REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/kernel-workspace/${REPO_NAME}"
    PUSH_REMOTE="origin"
    ui_end
}

mount_tunnel() {
    ui_header "CRYPTOGRAPHIC TUNNEL"
    
    # Source the agent file created by the Sync script
    # shellcheck source=/dev/null
    [ -f "$AGENT_ENV" ] && source "$AGENT_ENV" >/dev/null 2>&1 || true

    # Spin it up if it does not exist
    if [ -z "${SSH_AUTH_SOCK:-}" ] || ! kill -0 "${SSH_AGENT_PID:-}" 2>/dev/null; then
        ui_step "Initializing background SSH daemon..."
        eval "$(ssh-agent -s)" > /dev/null
        echo "export SSH_AUTH_SOCK=\"${SSH_AUTH_SOCK}\"" > "$AGENT_ENV"
        echo "export SSH_AGENT_PID=\"${SSH_AGENT_PID}\"" >> "$AGENT_ENV"
        chmod 600 "$AGENT_ENV"
        
        if [ -f "$SSH_KEY_PATH" ]; then
            ssh-add "$SSH_KEY_PATH" 2>/dev/null || true
        fi
    fi

    # GitHub limits and timeouts configuration
    mkdir -p ~/.ssh/sockets
    export GIT_SSH_COMMAND="ssh -i ${SSH_KEY_PATH} -o IdentitiesOnly=yes -o ServerAliveInterval=60 -o ServerAliveCountMax=120 -o ControlMaster=auto -o ControlPath=~/.ssh/sockets/%%r@%%h-%%p -o ControlPersist=60m"
    
    ui_step "Executing Handshake with GitHub..."
    if ssh -i "$SSH_KEY_PATH" -T -o ConnectTimeout=5 git@github.com 2>&1 | grep -q "successfully authenticated"; then
        ui_ok "Connection secured."
    else
        ui_warn "Handshake anomalous, but proceeding."
    fi
    ui_end
}

apply_workspace_optimizations() {
    ui_header "WORKSPACE TUNING"
    
    if [ ! -d "$REPO_DIR/.git" ]; then
        ui_err "Workspace missing. Please run sync_engine.sh first."
    fi
    cd "$REPO_DIR" || exit 1
    
    # Clean stale locks from previous broken processes
    if [ -f ".git/index.lock" ]; then
        rm -f .git/index.lock
        ui_warn "Cleared stale index.lock file."
    fi
    
    local system_threads
    system_threads=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)

    # Aggressive memory tuning for massive kernel pushes
    git config --local core.compression 1
    git config --local pack.windowMemory 1g 
    git config --local pack.packSizeLimit 1g
    git config --local pack.threads "$system_threads"
    
    git remote set-url "$PUSH_REMOTE" "$TARGET_REPO_SSH" 2>/dev/null || git remote add "$PUSH_REMOTE" "$TARGET_REPO_SSH"
    ui_ok "Git memory management and remotes configured."
    ui_end
}

execute_push() {
    ui_header "DATA TRANSMISSION"
    local local_branch
    local_branch=$(git branch --show-current)
    
    echo -e "${C_BLUE}│${C_RST} ${C_DIM}Strategy for current branch [${local_branch}]:${C_RST}"
    echo -e "${C_BLUE}│${C_RST}  ${C_CYAN}[1]${C_RST} MASS UPLOAD ${C_DIM}(3000 commits/chunk)${C_RST}"
    echo -e "${C_BLUE}│${C_RST}  ${C_CYAN}[2]${C_RST} DELTA SYNC  ${C_DIM}(50 commits/chunk)${C_RST}"
    
    read -r -p "${C_BLUE}│${C_RST} Select [1/2]: " strategy

    local commits=()
    local chunk_size=50

    # Build the array. Used a while-read loop for 100% shell universality.
    if [ "$strategy" == "1" ]; then
        chunk_size=3000
        while IFS= read -r line; do commits+=("$line"); done < <(git rev-list --reverse HEAD)
    elif [ "$strategy" == "2" ]; then
        chunk_size=50
        if ! git rev-parse --verify "${UPSTREAM_BASE}" >/dev/null 2>&1; then
            ui_err "Upstream base '${UPSTREAM_BASE}' not found. Did you sync first?"
        fi
        while IFS= read -r line; do commits+=("$line"); done < <(git rev-list --reverse "${UPSTREAM_BASE}"..HEAD)
    else
        ui_err "Invalid selection."
    fi

    local total=${#commits[@]}
    if [ "$total" -eq 0 ]; then
        ui_ok "No commits to push. Remote is perfectly synced."
        ui_end
        exit 0
    fi

    local total_chunks=$(( (total + chunk_size - 1) / chunk_size ))
    ui_step "Queue: $total elements. Processing in $total_chunks chunks..."

    local count=1
    for (( i=chunk_size-1; i < total; i+=chunk_size )); do
        local target="${commits[$i]}"
        ui_step "[Batch $count/$total_chunks] Pushing to commit -> ${C_YELLOW}${target:0:8}${C_RST}"
        
        if git push -f "$PUSH_REMOTE" "$target:refs/heads/$TARGET_REMOTE_BRANCH" --quiet; then
            ui_ok "Batch $count secured."
        else
            ui_err "Transmission failed on batch $count."
        fi
        count=$((count + 1))
        # Brief pause to avoid rate limiting
        sleep 2
    done

    ui_step "Locking final tip pointer..."
    if git push -f "$PUSH_REMOTE" HEAD:refs/heads/"$TARGET_REMOTE_BRANCH" --quiet; then
        ui_ok "TRANSMISSION COMPLETE! Tree successfully synced to GitHub."
    else
        ui_err "Final anchor transmission failed."
    fi
    ui_end
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================
print_ascii
probe_push_config
mount_tunnel
apply_workspace_optimizations
execute_push
