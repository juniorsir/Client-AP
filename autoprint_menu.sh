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
    echo -e "\n${CYAN}[Scanning local network for SSH-enabled devices...]${NC}"

    # Try using `ip route` for subnet
    subnet=$(ip route | grep -oP '(\d+\.\d+\.\d+)\.\d+/24' | head -n 1)

    # Fallback to `ifconfig` if necessary
    if [ -z "$subnet" ]; then
        if ! command -v ifconfig >/dev/null 2>&1; then
            echo -e "${YELLOW}Installing net-tools for ifconfig...${NC}"
            pkg install net-tools -y >/dev/null
        fi
        subnet=$(ifconfig | grep inet | grep -v 127.0.0.1 | awk '{print $2}' | cut -d'.' -f1-3 | head -n1)
        [ -n "$subnet" ] && subnet="${subnet}.0/24"
    fi

    if [ -z "$subnet" ]; then
        echo -e "${RED}Unable to detect subnet.${NC}"
        return 1
    fi

    base_ip=$(echo "$subnet" | cut -d'/' -f1 | cut -d'.' -f1-3)

    spinner="/-\|"
    echo -ne "${YELLOW}Searching: ${NC}"

    for i in $(seq 1 254); do
        ip="$base_ip.$i"
        timeout 1 bash -c "echo > /dev/tcp/$ip/22" 2>/dev/null &
        pid=$!

        spin_i=0
        while kill -0 $pid 2>/dev/null; do
            spin_i=$(( (spin_i+1) %4 ))
            printf "\b${spinner:$spin_i:1}"
            sleep 0.1
        done

        wait $pid
        if [ $? -eq 0 ]; then
            echo -e "\b${GREEN}[FOUND] Possible SSH device: $ip${NC}"
            echo
            read -p "  ${YELLOW}Use $ip as your PC IP? (y/n): ${NC}" choice
            if [ "$choice" = "y" ]; then
                echo "$ip" > /tmp/autoprint_ip.tmp
                return 0
            fi
            echo -ne "${YELLOW}Searching: ${NC}"
        fi
    done

    echo -e "\b${RED}No active SSH devices found.${NC}"
    return 1
}

function set_config() {
    echo -e "\n${CYAN}-- AutoPrint Configuration Setup --${NC}"
    echo

    # Yellow colored prompt using escape codes
    read -p $'\033[1;33mAuto-detect PC IP? (y/n): \033[0m' auto_choice
    if [[ "$auto_choice" =~ ^[yY]$ ]]; then
        auto_ip=$(scan_network_for_ssh)
        if [ -f /tmp/autoprint_ip.tmp ]; then
            pc_ip=$(cat /tmp/autoprint_ip.tmp)
            rm /tmp/autoprint_ip.tmp
            echo -e "${GREEN}Detected PC IP: $pc_ip${NC}"
        else
            echo -e "${RED}No PC found automatically. Please enter manually.${NC}"
            read -p "Enter PC IP address: " pc_ip
        fi
    else
        read -p "Enter PC IP address: " pc_ip
    fi

    read -p $'\033[1;33mEnter PC username: \033[0m' pc_user
    read -p $'\033[1;33mEnter PC folder (e.g. /home/user/printjobs): \033[0m' folder
    read -p $'\033[1;33mDefault image width in mm (e.g. 120): \033[0m' width
    read -p $'\033[1;33mAlways ask for image position? (y/n): \033[0m' ask_pos
    ask_flag=true
    [[ "$ask_pos" =~ ^[nN]$ ]] && ask_flag=false

    cat <<EOF > "$CONFIG_FILE"
{
  "pc_ip": "$pc_ip",
  "pc_user": "$pc_user",
  "remote_folder": "$folder",
  "image_width": "$width",
  "always_ask_pos": $ask_flag
}
EOF

    echo -e "${GREEN}Configuration saved successfully.${NC}"
}

function check_update_notice() {
    REMOTE_VERSION=$(curl -s https://raw.githubusercontent.com/juniorsir/Client-AP/main/version.txt)
    VERSION_FILE="$HOME/.autoprint_version"
    [ ! -f "$VERSION_FILE" ] && echo "v0.0.0" > "$VERSION_FILE"
    LOCAL_VERSION=$(cat "$VERSION_FILE")

    if [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
        echo -e "${RED}[!] New version available: v0.0.2${NC}"
        
        echo -e "    Current version: v0.0.1"
        echo
        read -p $'\033[0;31mDo you want to update now? (y/n): \033[0m' update_choice
        if [ "$confirm" = "y" ]; then
            echo -e "${BLUE}Running updater...${NC}"
            autoprint-update
        else
            echo -e "${YELLOW}Update skipped.${NC}"
        fi
    else
        echo -e "${GREEN}You're using the latest version ($LOCAL_VERSION).${NC}"
    fi
}

function show_menu() {
    while true; do
        echo -e "\n${BLUE}======= AutoPrint Menu =======${NC}"
        echo -e "${YELLOW}1.${NC} Start AutoPrint"
        echo -e "${YELLOW}2.${NC} Stop AutoPrint"
        echo -e "${YELLOW}3.${NC} Edit Configuration"
        echo -e "${YELLOW}4.${NC} Reset Settings"
        echo -e "${YELLOW}5.${NC} Exit"
        echo -e "${YELLOW}6.${NC} Check for Updates"
        echo -e "${YELLOW}7.${NC} Developer Info"
        echo -e "${BLUE}===============================${NC}"

        read -p $'\033[0;36mChoose an option: \033[0m' opt

        case $opt in
            1)
                termux-wake-lock
                echo -e "${CYAN}Starting AutoPrint...${NC}"
    
                nohup python $PREFIX/bin/autoprint.py > autoprint.log 2>&1 &
                sleep 2  # give it a moment to fail if it will

                if pgrep -f autoprint.py > /dev/null; then
                echo -e "${GREEN}AutoPrint started successfully and is running in the background.${NC}"
            else
                echo -e "${RED}Failed to start AutoPrint. Check autoprint.log for details.${NC}"
                termux-wake-unlock
            fi
            ;;
            2)
                pkill -f autoprint.py
                termux-wake-unlock
                echo -e "${RED}AutoPrint stopped.${NC}" ;;
            3) set_config ;;
            4) rm -f "$CONFIG_FILE"
               echo -e "${RED}Settings cleared.${NC}" ;;
            5) echo -e "${CYAN}Exiting.${NC}"; break ;;
            6) check_update_notice ;;
            7)
                echo -e "\n${CYAN}=== Developer Info ===${NC}"
                echo -e "Name: ${GREEN}JuniorSir${NC}"
                echo -e "GitHub: ${BLUE}https://github.com/juniorsir${NC}"
                echo -e "Telegram: ${BLUE}https://t.me/Junior_sir${NC}"
                echo ""
                echo -e "${YELLOW}1.${NC} Open GitHub"
                echo -e "${YELLOW}2.${NC} Open Telegram"
                echo -e "${YELLOW}3.${NC} Back"
                read -p "${CYAN}Choose an option: ${NC}" devopt

                case $devopt in 
                    1) termux-open-url "https://github.com/juniorsir" ;;
                    2) termux-open-url "https://t.me/Junior_sir" ;;
                    3) echo -e "${CYAN}Returning...${NC}" ;;
                    *) echo -e "${RED}Invalid option.${NC}" ;;
                esac ;;
            *) echo -e "${RED}Invalid option.${NC}" ;;
        esac
    done
}

check_update_notice
set_config
show_menu
