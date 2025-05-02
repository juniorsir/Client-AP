#!/data/data/com.termux/files/usr/bin/bash
clear

# Colors
BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
CYAN='\033[1;36m'
NC='\033[0m'

AUTO_CONFIRM=0
[[ "$1" == "--yes" ]] && AUTO_CONFIRM=1

# Paths and URLs
GIT_REPO="https://github.com/juniorsir/Client-AP.git"
TEMP_FOLDER="$HOME/Client-AP"
VERSION_URL="https://raw.githubusercontent.com/juniorsir/Client-AP/main/version.txt"
VERSION_FILE="$HOME/.autoprint_version"
CONFIG_FILE="$HOME/.autoprint_config.json"
BACKUP_FILE="$HOME/.autoprint_config_backup.json"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Checking for updates from GitHub...${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

REMOTE_VERSION=$(curl -s "$VERSION_URL")
if [ -z "$REMOTE_VERSION" ]; then
    echo -e "${RED}[✗] Failed to fetch remote version.${NC}"
    exit 1
fi

[ ! -f "$VERSION_FILE" ] && echo "v0.0.0" > "$VERSION_FILE"
LOCAL_VERSION=$(cat "$VERSION_FILE")

if [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
    echo
    echo -e "${YELLOW}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${NC}        ${GREEN}★ New Update Available! ★${NC}            ${YELLOW}║${NC}"
    echo -e "${YELLOW}╠══════════════════════════════════════════════╣${NC}"
    echo -e "${YELLOW}║${NC}  Current Version  : ${CYAN}$LOCAL_VERSION${NC}                   ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}  Available Version: ${CYAN}$REMOTE_VERSION${NC}                   ${YELLOW}║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════╝${NC}"
    echo

    if [ "$AUTO_CONFIRM" -eq 0 ]; then
        read -p $'\033[1;33mDo you want to update now? (y/n): \033[0m' confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "${RED}[!] Update cancelled by user.${NC}"
            exit 0
        fi
    else
        echo -e "${BLUE}[*] Auto-confirm enabled. Proceeding with update...${NC}"
    fi

    echo -e "\n${BLUE}[*] Backing up config...${NC}"
    [ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "$BACKUP_FILE"

    echo -e "${BLUE}[*] Removing old scripts...${NC}"
    rm -f "$PREFIX/bin/autoprint.py" "$PREFIX/bin/autoprint-menu.py" "$PREFIX/bin/scanprinter.py"

    echo -e "${BLUE}[*] Creating temporary folder...${NC}"
    mkdir -p "$TEMP_FOLDER"

    echo -e "${BLUE}[*] Cloning latest repo files...${NC}"
    if git clone "$GIT_REPO" "$TEMP_FOLDER"; then
        echo -e "${YELLOW}[•]${GREEN} Setting execution permissions...${NC}"
        chmod +x "$TEMP_FOLDER/autoprint-menu.py"
        chmod +x "$TEMP_FOLDER/autoprint.py"
        chmod +x "$TEMP_FOLDER/scanprinter.py"

        echo -e "${BLUE}[*] Moving updated files...${NC}"
        mv "$TEMP_FOLDER/autoprint.py" "$PREFIX/bin/autoprint.py"
        mv "$TEMP_FOLDER/autoprint-menu.py" "$PREFIX/bin/autoprint-menu.py"
        mv "$TEMP_FOLDER/scanprinter.py" "$PREFIX/bin/scanprinter.py"

        echo -e "${BLUE}[*] Adding alias to .bashrc...${NC}"
        grep -q "alias autoprint=" "$HOME/.bashrc" || echo "alias autoprint='python \$PREFIX/bin/autoprint-menu.py'" >> "$HOME/.bashrc"

        echo "$REMOTE_VERSION" > "$VERSION_FILE"
        echo -e "${GREEN}[✓] Updated to version $REMOTE_VERSION.${NC}"
    else
        echo -e "${RED}[✗] Update failed. Keeping current version.${NC}"
    fi

    echo -e "${BLUE}[*] Cleaning up temporary files...${NC}"
    rm -rf "$TEMP_FOLDER"
else
    echo -e "${GREEN}[✓] You already have the latest version ($LOCAL_VERSION).${NC}"
    source "$HOME/.bashrc"
fi

echo
echo -e "${YELLOW}To start using AutoPrint, run: ${GREEN}autoprint${YELLOW}  ($REMOTE_VERSION)${NC}"
