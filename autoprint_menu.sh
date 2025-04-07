#!/data/data/com.termux/files/usr/bin/bash

clear
# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

CONFIG_FILE="$HOME/.autoprint_config.json"
BACKUP_FILE="$HOME/.autoprint_config_backup.json"
GIT_REPO="https://github.com/juniorsir/Client-AP.git"
LOCAL_FOLDER="$HOME/Client-AP"

function scan_network_for_ssh() {
    echo ""
    echo -e "${CYAN}[Scanning local network for SSH-enabled devices...]${NC}"
    subnet=$(ip route | grep -oP '(\d+\.\d+\.\d+)\.\d+/24' | head -n 1)
    [ -z "$subnet" ] && { echo "Unable to detect subnet."; return 1; }

    base_ip=$(echo "$subnet" | cut -d'/' -f1 | cut -d'.' -f1-3)
    for i in $(seq 1 254); do
        ip="$base_ip.$i"
        timeout 1 bash -c "echo > /dev/tcp/$ip/22" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}[FOUND] Possible PC with SSH: $ip${NC}"
            read -p "Use $ip as your PC IP? (y/n): " choice
            [ "$choice" = "y" ] && { echo "$ip"; return 0; }
        fi
    done
    echo -e "${RED}No active SSH devices found.${NC}"
    return 1
}

function set_config() {
    echo ""
    echo "Updating configuration..."
    auto_ip=$(scan_network_for_ssh)
    if [ -n "$auto_ip" ]; then
        pc_ip=$auto_ip
    else
        read -p "Enter PC IP address: " pc_ip
    fi

    read -p "Enter PC username: " pc_user
    read -p "Enter PC folder (e.g. /home/user/printjobs): " folder
    read -p "Default image width in mm (e.g. 120): " width
    read -p "Always ask for image position? (y/n): " ask_pos
    ask_flag=true
    [ "$ask_pos" = "n" ] || [ "$ask_pos" = "N" ] && ask_flag=false

    cat <<EOF > "$CONFIG_FILE"
{
  "pc_ip": "$pc_ip",
  "pc_user": "$pc_user",
  "remote_folder": "$folder",
  "image_width": "$width",
  "always_ask_pos": $ask_flag
}
EOF

    echo -e "${GREEN}Configuration saved.${NC}"
}

function update_from_github() {
    echo ""
    echo -e "${BLUE}[Checking for updates from GitHub...]${NC}"

    REMOTE_VERSION=$(curl -s https://raw.githubusercontent.com/juniorsir/Client-AP/main/version.txt)
    LOCAL_VERSION_FILE="$HOME/.autoprint_version"
    LOCAL_FOLDER="$HOME/Client-AP"
    CONFIG_FILE="$HOME/.autoprint_config.json"
    BACKUP_FILE="$HOME/.autoprint_config_backup.json"

    [ ! -f "$LOCAL_VERSION_FILE" ] && echo "v0.0.0" > "$LOCAL_VERSION_FILE"
    LOCAL_VERSION=$(cat "$LOCAL_VERSION_FILE")

    if [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
        echo ""
        echo -e "${YELLOW}--------------------------------------------------${NC}"
        echo -e "${YELLOW}  [!] Update available: $REMOTE_VERSION${NC}"
        echo -e "${YELLOW}  Current version: $LOCAL_VERSION${NC}"
        echo -e "${YELLOW}--------------------------------------------------${NC}"

        read -p "Do you want to update now? (y/n): " confirm
        if [ "$confirm" = "y" ]; then
            echo "[*] Backing up config..."
            [ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "$BACKUP_FILE"

            echo "[*] Removing old scripts..."
            rm -f "$HOME/autoprint.py" "$HOME/autoprint_menu.sh" "$HOME/printer_watch.sh"

            echo "[*] Preparing local folder..."
            [ -d "$LOCAL_FOLDER" ] || mkdir -p "$LOCAL_FOLDER"

            echo "[*] Cloning repository..."
            git clone "$GIT_REPO" "$LOCAL_FOLDER" && {
                echo "[*] Moving files..."
                cp "$LOCAL_FOLDER/autoprint.py" "$HOME/"
                cp "$LOCAL_FOLDER/autoprint_menu.sh" "$HOME/"
                cp "$LOCAL_FOLDER/printer_watch.sh" "$HOME/"

                echo "$REMOTE_VERSION" > "$LOCAL_VERSION_FILE"
                echo -e "${GREEN}[✓] Update completed to version $REMOTE_VERSION.${NC}"
            } || {
                echo -e "${RED}[✗] Update failed. Version file not changed.${NC}"
            }

            echo "[*] Cleaning up..."
            rm -rf "$LOCAL_FOLDER"
        else
            echo "[!] Update skipped."
        fi
    else
        echo "You already have the latest version ($LOCAL_VERSION)."
    fi
}

function show_menu() {
    while true; do
        echo ""
        echo -e "${BLUE}======= AutoPrint Menu =======${NC}"
        echo "1. Start AutoPrint"
        echo "2. Stop AutoPrint"
        echo "3. Edit Configuration"
        echo "4. Reset Settings"
        echo "5. Exit"
        echo "6. Check for Updates"
        echo "7. Developer Info"
    
        echo "===================================="
        read -p "Choose an option: " opt

        case $opt in
            1) termux-wake-lock
               nohup python autoprint.py > autoprint.log 2>&1 &
               echo "AutoPrint started. Running in background..." ;;
            2) pkill -f autoprint.py
               termux-wake-unlock
               echo "AutoPrint stopped." ;;
            3) set_config ;;
            4) rm -f "$CONFIG_FILE"; echo "Settings cleared." ;;
            5) echo "Exiting."; break ;;
            6) termux-open-url https://github.com/juniorsir/Client-AP.git ;;
            7) 
               echo ""
               echo "=== Developer Info ==="
               echo "Name: JuniorSir"
               echo "GitHub: https://github.com/juniorsir"
               echo "Telegram: https://t.me/Junior_sir"
               echo ""
               echo "1. Open GitHub"
               echo "2. Open Telegram"
               echo "3. Back"
               read -p "Choose an option: " devopt

               case $devopt in 
                   1)
                       termux-open-url "https://github.com/juniorsir"
                       ;;
                   2)
                       termux-open-url "https://t.me/Junior_sir"
                       ;;
                   3)
                       echo "Returning..."
                       ;;
                   *)
                       echo "Invalid option."
                       ;;
               esac
               ;;
        
            *) echo "Invalid option." ;;
        esac
    done
}

update_from_github
show_menu
