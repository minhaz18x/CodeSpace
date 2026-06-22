#!/usr/bin/env bash

# Enforce strict error handling
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# CORE CONFIGURATION & UNIVERSAL UI
# ==============================================================================
readonly SSH_KEY_PATH="${HOME}/.ssh/id_ed25519"
readonly AGENT_ENV="${HOME}/.ssh/persistent_git_agent.env"

# ANSI-C Quoted Colors (Ensures universal rendering)
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
 │  ███████╗██╗   ██╗███╗   ██╗██████╗      │
 │  ██╔════╝╚██╗ ██╔╝████╗  ██║██╔════╝     │
 │  ███████╗ ╚████╔╝ ██╔██╗ ██║██║          │
 │  ╚════██║  ╚██╔╝  ██║╚██╗██║██║          │
 │  ███████║   ██║   ██║ ╚████║╚██████╗     │
 │  ╚══════╝   ╚═╝   ╚═╝  ╚═══╝ ╚═════╝     │
 │       [ KERNEL SYNC ENGINE • PRO ]       │
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

# Safe interrupt handling
trap 'echo -e "\n${C_RED}[✖] INTERRUPT DETECTED. Exiting safely.${C_RST}"; exit 130' INT TERM

# Network operation retry wrapper
run_with_retry() {
    local cmd="$1"
    local max_attempts=3
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if eval "$cmd"; then return 0; fi
        ui_warn "Network unstable. Retrying ($attempt/$max_attempts)..."
        sleep 3; attempt=$((attempt + 1))
    done
    ui_err "Command failed after $max_attempts attempts: $cmd"
}

build_repo_url() {
    local repo_short=$1
    local proto=$2
    if [ "$proto" == "2" ]; then
        echo "git@github.com:${repo_short}.git"
    else
        echo "https://github.com/${repo_short}.git"
    fi
}

# ==============================================================================
# WORKFLOW MODULES
# ==============================================================================

mount_crypto_agent() {
    ui_header "SECURITY SUBSYSTEM"
    mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh"

    # Check if agent is already running and key is loaded
    if ssh-add -l >/dev/null 2>&1; then
        ui_ok "Agent is active and keys are loaded."
        ui_end
        return 0
    fi

    # Source existing environment if available
    if [ -f "$AGENT_ENV" ]; then
        # shellcheck source=/dev/null
        source "$AGENT_ENV" >/dev/null 2>&1 || true
    fi

    # If socket is dead or missing, start a new agent
    if [ -z "${SSH_AUTH_SOCK:-}" ] || ! kill -0 "${SSH_AGENT_PID:-}" 2>/dev/null; then
        ui_step "Initializing new background SSH daemon..."
        eval "$(ssh-agent -s)" > /dev/null
        echo "export SSH_AUTH_SOCK=\"${SSH_AUTH_SOCK}\"" > "$AGENT_ENV"
        echo "export SSH_AGENT_PID=\"${SSH_AGENT_PID}\"" >> "$AGENT_ENV"
        chmod 600 "$AGENT_ENV"
    else
        ui_step "Reconnected to existing SSH daemon."
    fi
    
    # Add the key (prompts for password ONLY once per boot)
    if [ -f "$SSH_KEY_PATH" ]; then
        ui_step "Mounting SSH key (Enter passphrase if prompted)..."
        ssh-add "$SSH_KEY_PATH" || ui_warn "Skipped key addition or failed."
    fi
    
    ui_ok "Agent initialized and securely mounted."
    ui_end
}

probe_config_matrix() {
    ui_header "TARGET CONFIGURATION"
    
    local def_t_repo="LineageOS/android_kernel_xiaomi_sm6250"
    local def_t_branch="lineage-22.2"
    local def_u_repo="LineageOS/android_kernel_qcom_sm8150"
    local def_u_branch="lineage-20"

    echo -e "${C_MAGENTA}│${C_RST} ${C_DIM}Select Protocol:${C_RST}"
    echo -e "${C_MAGENTA}│${C_RST}  ${C_CYAN}[1]${C_RST} HTTPS"
    echo -e "${C_MAGENTA}│${C_RST}  ${C_CYAN}[2]${C_RST} SSH"
    read -r -p "${C_MAGENTA}│${C_RST} Choice [1/2]: " PROTO_CHOICE
    PROTO_CHOICE="${PROTO_CHOICE:-1}"

    echo -e "${C_MAGENTA}│${C_RST} ${C_DIM}Press [ENTER] to use defaults. Use 'User/Repo' format.${C_RST}"
    
    read -r -p "${C_MAGENTA}│${C_RST} 📦 Target Repo   [${C_GREEN}$def_t_repo${C_RST}]: " TARGET_SHORT
    TARGET_SHORT="${TARGET_SHORT:-$def_t_repo}"
    TARGET_REPO=$(build_repo_url "$TARGET_SHORT" "$PROTO_CHOICE")
    
    read -r -p "${C_MAGENTA}│${C_RST} 🌿 Target Branch [${C_GREEN}$def_t_branch${C_RST}]: " TARGET_BRANCH
    TARGET_BRANCH="${TARGET_BRANCH:-$def_t_branch}"
    
    read -r -p "${C_MAGENTA}│${C_RST} 🌐 Upstream Repo [${C_GREEN}$def_u_repo${C_RST}]: " UPSTREAM_SHORT
    UPSTREAM_SHORT="${UPSTREAM_SHORT:-$def_u_repo}"
    UPSTREAM_REPO=$(build_repo_url "$UPSTREAM_SHORT" "$PROTO_CHOICE")
    
    read -r -p "${C_MAGENTA}│${C_RST} 🔱 Upstream Base [${C_GREEN}$def_u_branch${C_RST}]: " UPSTREAM_BRANCH
    UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-$def_u_branch}"

    REPO_NAME=$(basename "${TARGET_REPO}" .git)
    WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/kernel-workspace"
    REPO_DIR="${WORK_DIR}/${REPO_NAME}"
    
    # Calculate optimal threads across OS architectures
    SYSTEM_THREADS=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
    ui_end
}

provision_workspace() {
    ui_header "WORKSPACE PROVISIONING"
    mkdir -p "$WORK_DIR"
    
    if [ ! -d "$REPO_DIR/.git" ]; then
        ui_step "Cloning repository..."
        run_with_retry "git clone -b \"$TARGET_BRANCH\" \"$TARGET_REPO\" \"$REPO_DIR\" --quiet --progress"
        ui_ok "Clone completed."
    else
        ui_ok "Workspace verified."
    fi

    cd "$REPO_DIR" || ui_err "Failed to enter directory: $REPO_DIR"
    
    # Performance configurations
    git config core.compression 9
    git config pack.threads "$SYSTEM_THREADS"
    git config rerere.enabled true 
    git config rerere.autoupdate true
    git config merge.renameLimit 999999

    git remote set-url upstream "$UPSTREAM_REPO" 2>/dev/null || git remote add upstream "$UPSTREAM_REPO"
    
    ui_step "Fetching remote upstream..."
    run_with_retry "git fetch upstream \"$UPSTREAM_BRANCH\" --quiet --progress"
    ui_ok "Upstream synchronized."
    ui_end
}

handle_conflict() {
    local op_type=$1
    echo -e "\n${C_RED}╭────────────────────────────────────────╮${C_RST}"
    echo -e "${C_RED}│ ⚠️  CONFLICT DETECTED                   │${C_RST}"
    echo -e "${C_RED}╰────────────────────────────────────────╯${C_RST}"
    
    echo -e "${C_YELLOW}Git could not automatically complete the $op_type.${C_RST}\n"
    echo -e "  ${C_CYAN}[A]bort${C_RST} - Cancel and revert to previous state."
    echo -e "  ${C_CYAN}[E]xit ${C_RST} - Keep conflicts, exit script to fix manually."
    echo ""
    
    while true; do
        read -r -p " Choose an action [A/E]: " conflict_choice
        case "${conflict_choice^^}" in
            A)
                ui_step "Aborting $op_type..."
                git "$op_type" --abort
                ui_ok "Workspace restored to clean state."
                exit 0
                ;;
            E)
                echo -e "\n${C_GREEN}=== MANUAL RECOVERY CHEAT SHEET ===${C_RST}"
                echo -e " 1. Type ${C_CYAN}git status${C_RST} to find 'both modified' files."
                echo -e " 2. Open the files and fix conflicts."
                echo -e " 3. Type ${C_CYAN}git add <file>${C_RST} for each fixed file."
                echo -e " 4. Prevent SSH loops: ${C_MAGENTA}source $AGENT_ENV${C_RST}"
                echo -e " 5. Resume sync: ${C_CYAN}git $op_type --continue${C_RST}"
                echo -e "${C_DIM}(Once complete, you can safely run chunk_pusher.sh)${C_RST}"
                exit 1
                ;;
            *)
                echo -e "${C_RED}Invalid choice. Please type A or E.${C_RST}"
                ;;
        esac
    done
}

execute_sync() {
    ui_header "KERNEL SYNCHRONIZATION"
    
    # Check for stale operations
    if [ -d ".git/rebase-merge" ] || [ -d ".git/rebase-apply" ]; then
        ui_warn "A stale rebase is currently in progress."
        read -r -p "${C_MAGENTA}│${C_RST} Abort old rebase to continue? [Y/n]: " abort_choice
        if [[ ! "${abort_choice^^}" == "N" ]]; then
            git rebase --abort || true
            ui_ok "Cleared stale state."
        else
            ui_err "Please resolve the existing rebase before running this script."
        fi
    fi

    echo -e "${C_MAGENTA}│${C_RST} ${C_DIM}Integration Strategy:${C_RST}"
    echo -e "${C_MAGENTA}│${C_RST}  ${C_CYAN}[1]${C_RST} REBASE ${C_YELLOW}(Recommended)${C_RST}"
    echo -e "${C_MAGENTA}│${C_RST}  ${C_CYAN}[2]${C_RST} MERGE  ${C_DIM}(Preserves timeline)${C_RST}"
    
    read -r -p "${C_MAGENTA}│${C_RST} Select [1/2]: " op_choice

    git checkout "$TARGET_BRANCH" --quiet
    local active_branch="sync-${TARGET_BRANCH}-$(date '+%H%M')"
    git checkout -b "$active_branch" "$TARGET_BRANCH" --quiet
    ui_step "Switched to volatile working branch: $active_branch"

    # Temporarily disable 'exit on error' so we can catch conflicts gracefully
    set +e
    if [ "$op_choice" == "1" ]; then
        ui_step "Rebasing against upstream..."
        git rebase --strategy ort --empty=drop upstream/"$UPSTREAM_BRANCH" --quiet
        local exit_code=$?
        [ $exit_code -ne 0 ] && handle_conflict "rebase"
    else
        ui_step "Merging upstream..."
        git merge upstream/"$UPSTREAM_BRANCH" --no-edit --quiet
        local exit_code=$?
        [ $exit_code -ne 0 ] && handle_conflict "merge"
    fi
    # Re-enable 'exit on error'
    set -e

    ui_ok "SYNCHRONIZATION SUCCESSFUL!"
    echo -e "${C_MAGENTA}│${C_RST} You are now on branch: ${C_GREEN}$active_branch${C_RST}"
    ui_end
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================
print_ascii
mount_crypto_agent
probe_config_matrix
provision_workspace
execute_sync
