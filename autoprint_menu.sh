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
    echo -e "${CYAN}[Checking for updates from GitHub...]${NC}"

    REMOTE_VERSION=$(curl -s https://raw.githubusercontent.com/juniorsir/Client-AP/main/version.txt)
    LOCAL_VERSION_FILE="$HOME/.autoprint_version"

    if [ ! -f "$LOCAL_VERSION_FILE" ]; then
        echo "v0.0.0" > "$LOCAL_VERSION_FILE"
    fi

    LOCAL_VERSION=$(cat "$LOCAL_VERSION_FILE")

    if [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
        echo ""
        echo -e "${YELLOW}--------------------------------------------------${NC}"
        echo -e "${YELLOW}  [!] Update available: $REMOTE_VERSION${NC}"
        echo -e "${CYAN}  Current version: $LOCAL_VERSION${NC}"
        echo -e "${YELLOW}--------------------------------------------------${NC}"

        read -p "Do you want to update now? (y/n): " confirm
        if [ "$confirm" = "y" ]; then
            echo -e "${CYAN}[*] Backing up config...${NC}"
            [ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "$BACKUP_FILE"

            echo -e "${CYAN}[*] Updating scripts...${NC}"
            cd "$HOME" || { echo -e "${RED}Failed to change directory.${NC}"; return; }

            if [ -d "$LOCAL_FOLDER" ]; then
                cd "$LOCAL_FOLDER" || { echo -e "${RED}Failed to enter repo directory.${NC}"; return; }
                git pull origin main || { echo -e "${RED}Git pull failed.${NC}"; return; }
            else
                git clone "$GIT_REPO" "$LOCAL_FOLDER" || { echo -e "${RED}Git clone failed.${NC}"; return; }
            fi

            if ls "$LOCAL_FOLDER"/*.sh 1> /dev/null 2>&1; then
                cp "$LOCAL_FOLDER"/*.sh "$HOME" || { echo -e "${RED}Failed to copy scripts.${NC}"; return; }

                # Rename the main script to 'autoprint' and make executable
                if [ -f "$HOME/autoprint_menu.sh" ]; then
                    mv "$HOME/autoprint_menu.sh" "$HOME/autoprint"
                    chmod +x "$HOME/autoprint"
                    echo -e "${GREEN}[*] 'autoprint' command is now ready.${NC}"
                fi

                # Ensure $HOME is in PATH
                SHELL_RC="$HOME/.bashrc"
                if [ -n "$ZSH_VERSION" ]; then SHELL_RC="$HOME/.zshrc"; fi
                grep -q 'export PATH="$HOME:$PATH"' "$SHELL_RC" 2>/dev/null || echo 'export PATH="$HOME:$PATH"' >> "$SHELL_RC"
                export PATH="$HOME:$PATH"

                echo "$REMOTE_VERSION" > "$LOCAL_VERSION_FILE"
                echo -e "${GREEN}[✓] Update completed to version $REMOTE_VERSION.${NC}"
            else
                echo -e "${RED}[!] No .sh files found to copy. Update aborted.${NC}"
            fi
        else
            echo -e "${YELLOW}[!] Update skipped.${NC}"
        fi
    else
        echo -e "${GREEN}You already have the latest version ($LOCAL_VERSION).${NC}"
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
            1) ./start_autoprint.sh ;;
            2) ./stop_autoprint.sh ;;
            3) set_config ;;
            4) rm -f "$CONFIG_FILE"; echo "Settings cleared." ;;
            5) echo "Exiting."; break ;;
            6) update_from_github ;;
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
