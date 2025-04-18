#!/data/data/com.termux/files/usr/bin/bash
clear

BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
CYAN='\033[1;36m'
NC='\033[0m'

AUTO_CONFIRM=0
[[ "$1" == "--yes" ]] && AUTO_CONFIRM=1

GIT_REPO="https://github.com/juniorsir/Client-AP.git"
TEMP_FOLDER="$HOME/Client-AP"
VERSION_URL="https://raw.githubusercontent.com/juniorsir/Client-AP/main/version.txt"
VERSION_FILE="$HOME/.autoprint_version"
CONFIG_FILE="$HOME/.autoprint_config.json"
BACKUP_FILE="$HOME/.autoprint_config_backup.json"

echo -e "${BLUE}[Checking for updates from GitHub...]${NC}"

REMOTE_VERSION=$(curl -s "$VERSION_URL")
[ -z "$REMOTE_VERSION" ] && { echo -e "${RED}[✗] Failed to fetch remote version.${NC}"; exit 1; }

[ ! -f "$VERSION_FILE" ] && echo "v0.0.0" > "$VERSION_FILE"
LOCAL_VERSION=$(cat "$VERSION_FILE")

if [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
    echo ""
    echo -e "${YELLOW}--------------------------------------------------${NC}"
    echo -e "${YELLOW}[!] Update available: ${REMOTE_VERSION}${NC}"
    echo -e "${CYAN}    Current version: ${LOCAL_VERSION}${NC}"
    echo -e "${YELLOW}--------------------------------------------------${NC}"
    echo ""

    if [ "$AUTO_CONFIRM" -eq 0 ]; then
        read -p "Do you want to update now? (y/n): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "${RED}[!] Update cancelled by user.${NC}"
            exit 0
        fi
    else
        echo -e "${BLUE}[*] Auto-confirm enabled. Proceeding with update...${NC}"
    fi

    echo -e "${BLUE}[*] Backing up config...${NC}"
    [ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "$BACKUP_FILE"

    echo -e "${BLUE}[*] Removing old scripts...${NC}"
    rm -f "$PREFIX/bin/autoprintset" "$PREFIX/bin/autoprint"

    echo -e "${BLUE}[*] Creating temporary folder...${NC}"
    mkdir -p "$TEMP_FOLDER"

    echo -e "${BLUE}[*] Cloning repository...${NC}"
    if git clone "$GIT_REPO" "$TEMP_FOLDER"; then
        echo -e "${YELLOW}[*]${GREEN} Giving permission for execution${NC}"
        chmod +x "$TEMP_FOLDER/autoprint_menu.sh"
        chmod +x "$TEMP_FOLDER/autoprint.py"

        echo -e "${BLUE}[*] Moving updated files...${NC}"
        mv "$TEMP_FOLDER/autoprint.py" "$PREFIX/bin/autoprint.py"
        mv "$TEMP_FOLDER/autoprint_menu.sh" "$PREFIX/bin/autoprint"

        echo "$REMOTE_VERSION" > "$VERSION_FILE"
        echo -e "${GREEN}[✓] Updated to version $REMOTE_VERSION.${NC}"
    else
        echo -e "${RED}[✗] Update failed. Keeping current version.${NC}"
    fi

    echo -e "${BLUE}[*] Cleaning up...${NC}"
    rm -rf "$TEMP_FOLDER"
else
    echo -e "${GREEN}[✓] You already have the latest version ($LOCAL_VERSION).${NC}"
fi

echo
echo -e "${YELLOW}To start using AutoPrint, simply run: ${GREEN}autoprint${YELLOW}  ($REMOTE_VERSION)${NC}"
