#!/data/data/com.termux/files/usr/bin/bash
clear

BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

GIT_REPO="https://github.com/juniorsir/Client-AP.git"
TEMP_FOLDER="$HOME/Client-AP"
VERSION_URL="https://raw.githubusercontent.com/juniorsir/Client-AP/main/version.txt"
VERSION_FILE="$HOME/.autoprint_version"
CONFIG_FILE="$HOME/.autoprint_config.json"
BACKUP_FILE="$HOME/.autoprint_config_backup.json"

echo -e "${BLUE}[Checking for updates from GitHub...]${NC}"

REMOTE_VERSION=$(curl -s "$VERSION_URL")
[ -z "$REMOTE_VERSION" ] && { echo -e "${RED}Failed to fetch remote version.${NC}"; exit 1; }

[ ! -f "$VERSION_FILE" ] && echo "v0.0.0" > "$VERSION_FILE"
LOCAL_VERSION=$(cat "$VERSION_FILE")

if [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
        echo ""
        echo ""
        echo -e "${YELLOW}--------------------------------------------------${NC}"
        echo -e "${YELLOW}      [!] Update available: $REMOTE_VERSION${NC}"
        echo -e "${CYAN}           Current version: $LOCAL_VERSION${NC}"
        echo -e "${YELLOW}--------------------------------------------------${NC}"
        echo ""
        echo ""
    read -p "Do you want to update now? (y/n): " confirm

    if [ "$confirm" = "y" ]; then
        echo "[*] Backing up config..."
        [ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "$BACKUP_FILE"

        echo "[*] Removing old scripts..."
        rm -f "$PREFIX/bin/autoprintset" "$PREFIX/bin/autoprint"

        echo "[*] Creating temporary folder..."
        [ -d "$TEMP_FOLDER" ] || mkdir -p "$TEMP_FOLDER"

        echo "[*] Cloning repository..."
        git clone "$GIT_REPO" "$TEMP_FOLDER" && {


        echo -e "${YELLOW}[*]${GREEN}Giving permission for execution${NC}"

            chmod +x "$TEMP_FOLDER/autoprint_menu.sh"
            chmod +x "$TEMP_FOLDER/autoprint.py"

        echo "[*] Moving updated files..."

            mv "$TEMP_FOLDER/autoprint.py" "$PREFIX/bin/autoprint.py"
            mv "$TEMP_FOLDER/autoprint_menu.sh" "$PREFIX/bin/autoprint"


            echo "$REMOTE_VERSION" > "$VERSION_FILE"
            echo -e "${GREEN}[✓] Updated to version $REMOTE_VERSION.${NC}"
        } || {
            echo -e "${RED}[✗] Update failed. Keeping current version.${NC}"
        }

        echo "[*] Cleaning up..."
           rm -rf "${TEMP_FOLDER}"
    else
        echo "[!] Update cancelled by user."
    fi
else
    echo -e "${GREEN}You already have the latest version ($LOCAL_VERSION).${NC}"
fi
echo -e "${YELLOW}  To start using AutoPrint, simply run: ${GREEN}autoprint${YELLOW}  (v$REMOTE_VERSION)${NC}"
