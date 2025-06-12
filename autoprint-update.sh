#!/data/data/com.termux/files/usr/bin/bash

# ==============================================================================
#           AutoPrint Updater - v2.2 (Corrected Parallel Wait)
#
#  - Fixes "wait: not a pid or valid job spec" error.
#  - Uses a robust `trap` and `for` loop to correctly handle parallel jobs.
#  - Automatically installs dependencies and provides a clean, modern UI.
# ==============================================================================

# --- Configuration ---
REPO_OWNER="juniorsir"
REPO_NAME="Client-AP"
BRANCH="main"
FILES_TO_INSTALL=("autoprint-menu.py" "autoprint.py" "scanprinter.py")

# --- Paths ---
VERSION_URL="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/$BRANCH/version.txt"
BASE_RAW_URL="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/$BRANCH"
VERSION_FILE="$HOME/.autoprint_version"
CONFIG_FILE="$HOME/.autoprint_config.json"
BACKUP_FILE="$HOME/.autoprint_config_backup.json"
INSTALL_DIR="$PREFIX/bin"

# --- UI & Colors (Using ANSI-C Quoting for compatibility) ---
GREEN=$'\033[1;32m'
BLUE=$'\033[1;34m'
YELLOW=$'\033[1;33m'
RED=$'\033[1;31m'
CYAN=$'\033[1;36m'
NC=$'\033[0m' # No Color

# --- Helper Functions ---

print_banner() {
    local text="$1"
    local color="$2"
    local width=$(tput cols 2>/dev/null)
    [[ -z "$width" || "$width" -lt 40 ]] && width=80
    local padding=$(( (width - ${#text} - 2) / 2 ))
    [[ "$padding" -lt 0 ]] && padding=0

    printf "\n"
    printf "%s╔%s╗%s\n" "$color" "$(printf '═%.0s' $(seq 1 $((width - 2))))" "$NC"
    printf "%s║%*s%s%*s║%s\n" "$color" $padding "" "$text" $padding "" "$NC"
    printf "%s╚%s╝%s\n" "$color" "$(printf '═%.0s' $(seq 1 $((width - 2))))" "$NC"
    printf "\n"
}

print_status() {
    local status_symbol=$1
    local message=$2
    printf "\r${GREEN}[%s]${NC} %s\n" "$status_symbol" "$message"
}

spinner_animation() {
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while true; do
        printf "\r${CYAN}[*]${NC} ${spin:i++%${#spin}:1} %s " "$1"
        sleep 0.1
    done
}

# --- Main Logic Functions ---

check_dependencies() {
    local missing_pkgs=""
    for pkg in ncurses-utils curl; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            missing_pkgs+=" $pkg"
        fi
    done
    if [[ -n "$missing_pkgs" ]]; then
        print_banner "Installing Dependencies" "$YELLOW"
        echo -e "${YELLOW}[!] Required tools are missing:${CYAN}${missing_pkgs}${NC}"
        pkg update -y >/dev/null 2>&1
        pkg install -y $missing_pkgs
        if [ $? -ne 0 ]; then
            echo -e "${RED}[✗] Auto-install failed. Please run 'pkg install${missing_pkgs}' manually.${NC}"
            exit 1
        fi
        echo -e "${GREEN}[✓] Dependencies installed successfully.${NC}"
    fi
}

check_for_updates() {
    print_banner "Checking for AutoPrint Updates" "$BLUE"
    printf "${CYAN}[*]${NC} Fetching latest version info..."
    REMOTE_VERSION=$(curl -sL "$VERSION_URL")
    if [[ -z "$REMOTE_VERSION" ]]; then
        printf "\r${RED}[✗] Failed to fetch remote version. Check internet connection.${NC}\n"
        exit 1
    fi
    printf "\r${GREEN}[✓]${NC} Latest version is: ${CYAN}%s${NC}\n" "$REMOTE_VERSION"
    [[ ! -f "$VERSION_FILE" ]] && echo "v0.0.0" > "$VERSION_FILE"
    LOCAL_VERSION=$(cat "$VERSION_FILE")
    if [[ "$REMOTE_VERSION" == "$LOCAL_VERSION" ]]; then
        echo -e "\n${GREEN}You already have the latest version ($LOCAL_VERSION). Nothing to do.${NC}"
        echo -e "${YELLOW}To start, run: ${GREEN}autoprint${NC}"
        exit 0
    fi
    echo
    echo -e "${YELLOW}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${NC}        ${GREEN}★ New Update Available! ★${NC}            ${YELLOW}║${NC}"
    echo -e "${YELLOW}╠══════════════════════════════════════════════╣${NC}"
    echo -e "${YELLOW}║${NC}  Current Version  : ${CYAN}$LOCAL_VERSION${NC}                   ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}  Available Version: ${CYAN}$REMOTE_VERSION${NC}                   ${YELLOW}║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════╝${NC}"
    echo
    if [[ "$1" != "--yes" ]]; then
        read -p $'\033[1;33mDo you want to update now? (y/n): \033[0m' confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "${RED}[!] Update cancelled by user.${NC}"
            exit 0
        fi
    else
        echo -e "${BLUE}[*] Auto-confirm enabled. Proceeding with update...${NC}"
    fi
}

perform_update() {
    print_banner "Updating AutoPrint to $REMOTE_VERSION" "$BLUE"
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "$BACKUP_FILE"
        print_status "✓" "Configuration backed up."
    fi

    # Start spinner in the background
    spinner_animation "Downloading new files..." &
    SPINNER_PID=$!
    # Ensure spinner is killed on exit
    trap 'kill $SPINNER_PID &> /dev/null' EXIT

    # Download files in parallel
    pids=()
    for file in "${FILES_TO_INSTALL[@]}"; do
        (curl -sL -o "$file" "$BASE_RAW_URL/$file") & pids+=($!)
    done

    # Wait for each download and check for failures
    SUCCESS=true
    for pid in "${pids[@]}"; do
        wait "$pid" || SUCCESS=false
    done
    
    # Stop spinner
    kill $SPINNER_PID &> /dev/null
    trap - EXIT # Disable the trap
    printf "\r%*s\r" "$(tput cols)" # Clear the spinner line

    if ! $SUCCESS; then
        echo -e "${RED}[✗] A download failed. Aborting update.${NC}"
        rm -f "${FILES_TO_INSTALL[@]}" # Cleanup partial downloads
        exit 1
    fi
    print_status "✓" "All new files downloaded successfully."

    echo -e "\n${CYAN}[*] Installing updated files...${NC}"
    for file in "${FILES_TO_INSTALL[@]}"; do
        chmod +x "$file"
        mv "$file" "$INSTALL_DIR/$file"
        print_status "✓" "Installed: ${CYAN}$file${NC}"
    done

    if ! grep -q "alias autoprint=" "$HOME/.bashrc"; then
        echo -e "\nalias autoprint='python $INSTALL_DIR/autoprint-menu.py'" >> "$HOME/.bashrc"
        print_status "✓" "Alias 'autoprint' added to .bashrc."
        echo -e "${YELLOW}[!] Restart Termux or run 'source ~/.bashrc' to use the new alias.${NC}"
    else
        print_status "✓" "Alias 'autoprint' already exists."
    fi

    echo "$REMOTE_VERSION" > "$VERSION_FILE"
    print_status "✓" "Version updated to $REMOTE_VERSION."
}

# --- Script Execution ---

clear
check_dependencies
check_for_updates "$1"
perform_update

print_banner "Update Complete!" "$GREEN"
echo -e "You can now run AutoPrint with the command:"
echo -e "  ${GREEN}autoprint${NC}"
echo
