#!/data/data/com.termux/files/usr/bin/bash

clear

CONFIG_FILE="$HOME/.autoprint_config.json"
BACKUP_FILE="$HOME/.autoprint_config_backup.json"
GIT_REPO="https://github.com/juniorsir/Client-AP.git"
LOCAL_FOLDER="$HOME/Client-AP"

function scan_network_for_ssh() {
    echo ""
    echo "[Scanning local network for SSH-enabled devices...]"
    subnet=$(ip route | grep -oP '(\d+\.\d+\.\d+)\.\d+/24' | head -n 1)
    [ -z "$subnet" ] && { echo "Unable to detect subnet."; return 1; }

    base_ip=$(echo "$subnet" | cut -d'/' -f1 | cut -d'.' -f1-3)
    for i in $(seq 1 254); do
        ip="$base_ip.$i"
        timeout 1 bash -c "echo > /dev/tcp/$ip/22" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "[FOUND] Possible PC with SSH: $ip"
            read -p "Use $ip as your PC IP? (y/n): " choice
            [ "$choice" = "y" ] && { echo "$ip"; return 0; }
        fi
    done
    echo "No active SSH devices found."
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

    echo "Configuration saved."
}

function update_from_github() {
    echo ""
    echo "[Checking for updates from GitHub...]"

    if [ -d "$LOCAL_FOLDER" ]; then
        cd "$LOCAL_FOLDER"
        git fetch origin main >/dev/null 2>&1
        local_hash=$(git rev-parse HEAD)
        remote_hash=$(git rev-parse origin/main)

        if [ "$local_hash" != "$remote_hash" ]; then
            echo ""
            echo "--------------------------------------------------"
            echo "  [!] A new update is available for AutoPrint!"
            echo "  Your version:   $local_hash"
            echo "  Latest version: $remote_hash"
            echo "  To update now, choose option 6 in the menu."
            echo "--------------------------------------------------"
        else
            echo "You already have the latest version."
        fi
    else
        echo "[First-time install...]"
        git clone "$GIT_REPO" "$LOCAL_FOLDER"
        cp "$LOCAL_FOLDER"/*.sh "$HOME"
        echo "Installed scripts from GitHub."
    fi
}

function show_menu() {
    while true; do
        echo ""
        echo "========== AutoPrint Menu =========="
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
