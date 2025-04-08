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
    echo -e "${CYAN}[SSH Device Setup]${NC}"
    read -p "$(echo -e "${YELLOW}Do you want to auto-scan for SSH devices? (y/n): ${NC}")" auto_choice

    if [ "$auto_choice" != "y" ]; then
        read -p "$(echo -e "${CYAN}Enter your PC IP manually (e.g., 192.168.1.100): ${NC}")" manual_ip
        if [[ $manual_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo -e "${GREEN}Using IP: $manual_ip${NC}"
            echo "$manual_ip"
            return 0
        else
            echo -e "${RED}Invalid IP format. Aborting.${NC}"
            return 1
        fi
    fi

    echo -ne "${CYAN}Fetching local IP info "

    # Spinner animation
    spin() {
        local sp='/-\|'
        while true; do
            for c in $sp; do
                echo -ne "\b$c"
                sleep 0.1
            done
        done
    }
    spin &
    SPIN_PID=$!

    # Try to detect subnet
    subnet=$(ip route 2>/dev/null | grep -oP '(\d+\.\d+\.\d+)\.\d+/24' | head -n 1)

    # Fallback using ifconfig
    if [ -z "$subnet" ]; then
        if ! ifconfig_output=$(ifconfig 2>&1); then
            kill $SPIN_PID &>/dev/null
            wait $SPIN_PID 2>/dev/null
            echo -e "\b${RED} Failed.${NC}"
            echo -e "${YELLOW}Warning: ${RED}Cannot access network interfaces (Permission denied)${NC}"
            echo -e "${YELLOW}Skipping auto-detection. Please enter IP manually or send file manually.${NC}"
            return 1
        fi

        fallback_ip=$(echo "$ifconfig_output" | grep -oP 'inet\s+\K10(\.\d+){3}' | head -n 1)
        if [ -n "$fallback_ip" ]; then
            base_ip=$(echo "$fallback_ip" | cut -d'.' -f1-3)
        else
            kill $SPIN_PID &>/dev/null
            wait $SPIN_PID 2>/dev/null
            echo -e "\b${RED} Not found.${NC}"
            echo -e "${YELLOW}Network not detected. Please send the file manually.${NC}"
            return 1
        fi
    else
        base_ip=$(echo "$subnet" | cut -d'/' -f1 | cut -d'.' -f1-3)
    fi

    kill $SPIN_PID &>/dev/null
    wait $SPIN_PID 2>/dev/null
    echo -e "\b${GREEN} Done!${NC}\n"

    echo -e "${CYAN}[Scanning local network for SSH-enabled devices...]${NC}"

    for i in $(seq 1 254); do
        ip="$base_ip.$i"
        echo -ne "${CYAN}Checking $ip...\r${NC}"
        timeout 1 bash -c "echo > /dev/tcp/$ip/22" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}[FOUND] Possible SSH device: $ip${NC}"
            read -p "$(echo -e "${YELLOW}  Use $ip as your PC IP? (y/n): ${NC}")" choice
            [ "$choice" = "y" ] && { echo "$ip"; return 0; }
        fi
    done

    echo -e "${RED}No active SSH devices found. Please send file manually or check network.${NC}"
    return 1
}

function set_config() {
    echo -e "\n${CYAN}-- AutoPrint Configuration Setup --${NC}"
    
    auto_ip=$(scan_network_for_ssh)
    if [ -f /tmp/autoprint_ip.tmp ]; then
       pc_ip=$(cat /tmp/autoprint_ip.tmp)
       rm /tmp/autoprint_ip.tmp
    else
        read -p "Enter PC IP address: " pc_ip
    fi

    read -p "${YELLOW}Enter PC username: ${NC}" pc_user
    read -p "${YELLOW}Enter PC folder (e.g. /home/user/printjobs): ${NC}" folder
    read -p "${YELLOW}Default image width in mm (e.g. 120): ${NC}" width
    read -p "${YELLOW}Always ask for image position? (y/n): ${NC}" ask_pos
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
        echo -e "${YELLOW}[!] New version available: $REMOTE_VERSION${NC}"
        echo -e "    Current version: $LOCAL_VERSION"
        read -p "${CYAN}Do you want to update now? (y/n): ${NC}" confirm
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
