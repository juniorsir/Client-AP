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

    trap 'echo -e "\n${RED}Scan cancelled by user.${NC}"; exit 1' INT

    echo -e "\n${CYAN}[Scanning local network for SSH-enabled devices...]${NC}"

    # Detect subnet
    subnet=$(ip route | awk '/src/ {print $1}')
    if [ -z "$subnet" ]; then
        if ! command -v ifconfig >/dev/null 2>&1; then
            echo -e "${YELLOW}Installing net-tools for ifconfig...${NC}"
            pkg install net-tools -y >/dev/null
        fi
        ip_addr=$(ifconfig | grep -w inet | grep -v 127.0.0.1 | awk '{print $2}' | head -n1)
        subnet=$(echo "$ip_addr" | cut -d'.' -f1-3).0/24
    fi

    if [ -z "$subnet" ]; then
        echo -e "${RED}Unable to determine subnet.${NC}"
        return 1
    fi

    base_ip=$(echo "$subnet" | cut -d'/' -f1 | cut -d'.' -f1-3)

    echo -e "${YELLOW}Scanning subnet ${CYAN}$subnet${NC}..."

    # Spinner animation
    spinner='|/-\'
    spin() {
        i=0
        while kill -0 "$1" 2>/dev/null; do
            i=$(( (i+1) %4 ))
            printf "\r${CYAN}Scanning ${spinner:$i:1}${NC}"
            sleep 0.1
        done
    }

    for i in $(seq 1 254); do
        ip="$base_ip.$i"
        echo -ne "${NC}\r${YELLOW}Checking $ip...${NC} "

        # Capture output and error
        output=$(timeout 1 bash -c "cat < /dev/null > /dev/tcp/$ip/22" 2>&1)
        status=$?

        if [ $status -eq 0 ]; then
            printf "\r${GREEN}[FOUND] SSH available on: $ip${NC}\n"
            read -p "  ${YELLOW}Use $ip as your PC IP? (y/n): ${NC}" choice
            if [ "$choice" = "y" ]; then
                echo "$ip" > /tmp/autoprint_ip.tmp
                echo -e "${GREEN}Saved $ip for use.${NC}"
                return 0
            fi
        else
            echo -e "${RED}No SSH or error: ${output}${NC}"
        fi
    done

    echo -e "\n${RED}No SSH-enabled devices found.${NC}"
    return 1
}

function set_config() {
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}A saved configuration was found:${NC}"
        cat "$CONFIG_FILE" | jq
        echo
        read -p $'\033[1;33mDo you want to use this saved config? (y/n): \033[0m' use_saved

        if [[ "$use_saved" =~ ^[yY]$ ]]; then
            echo -e "${GREEN}Using existing config.${NC}"
            return
        else
            echo -e "${CYAN}Proceeding to create new configuration...${NC}"
        fi
    fi

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
clear
function view_live_log() {
    echo -e "${CYAN}Press Ctrl+C to stop viewing and return to the menu.${NC}"
    
    trap "echo -e '\n${YELLOW}Returning to menu...${NC}'; trap - INT; return" INT
    tail -f autoprint.log
    trap - INT  # Reset the trap afterward
}
clear
function ask_position_pref() {
    echo -e "\n${CYAN}[Choose image position]${NC}"
    echo -e "${YELLOW}1.${NC} Top-Left"
    echo -e "${YELLOW}2.${NC} Center"
    echo -e "${YELLOW}3.${NC} Bottom-Right"
    read -p $'\033[1;33mEnter choice (1/2/3): \033[0m' choice

    pos_code="center"
    case "$choice" in
        1) pos_code="top-left" ;;
        2) pos_code="center" ;;
        3) pos_code="bottom-right" ;;
        *) echo -e "${RED}Invalid choice. Defaulting to Center.${NC}" ;;
    esac

    # Inject selected position into config
    tmp_config=$(mktemp)
    jq ".image_position = \"$pos_code\"" "$CONFIG_FILE" > "$tmp_config" && mv "$tmp_config" "$CONFIG_FILE"
    echo -e "${GREEN}Image position set to: $pos_code${NC}"
}
clear
function check_update_notice() {
    REMOTE_VERSION=$(curl -s https://raw.githubusercontent.com/juniorsir/Client-AP/main/version.txt)
    VERSION_FILE="$HOME/.autoprint_version"
    [ ! -f "$VERSION_FILE" ] && echo "v0.0.0" > "$VERSION_FILE"
    LOCAL_VERSION=$(cat "$VERSION_FILE")

    if [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
        #
        echo -e ""
        echo -e "${YELLOW}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║${NC}        ${GREEN}★ New Update Available! ★${NC}             ${YELLOW}║${NC}"
        echo -e "${YELLOW}╠══════════════════════════════════════════════╣${NC}"
        echo -e "${YELLOW}║${NC}  Current Version  : ${CYAN}$LOCAL_VERSION${NC}                   ${YELLOW}║${NC}"
        echo -e "${YELLOW}║${NC}  Available Version: ${CYAN}$REMOTE_VERSION${NC}                   ${YELLOW}║${NC}"
        echo -e "${YELLOW}╚══════════════════════════════════════════════╝${NC}"
        echo -e ""

        read -p $'\033[1;33mDo you want to update now? (y/n): \033[0m' update_choice
        if [[ "$update_choice" =~ ^[yY]$ ]]; then
            echo -e "\033[1;34mRunning updater...\033[0m"
            autoprint-update
        else
            echo -e "\033[0;33mUpdate skipped.\033[0m"
        fi
    else
        echo -e "\033[1;32mYou're using the latest version ($LOCAL_VERSION).\033[0m"
    fi
}
clear
function show_menu() {
    while true; do
        echo -e "\n${BLUE}======= AutoPrint Menu =======${NC}"
        echo -e "${YELLOW}1.${NC} Start AutoPrint"
        echo -e "${YELLOW}2.${NC} Stop AutoPrint"
        echo -e "${YELLOW}3.${NC} Edit Configuration"
        echo -e "${YELLOW}4.${NC} Reset Settings"
        echo -e "${YELLOW}5.${NC} Exit"
        echo -e "${YELLOW}6.${NC} Check for Updates"
        echo -e "${YELLOW}7.${NC} View Live Log"
        echo -e "${YELLOW}8.${NC} Developer Info"
        echo -e "${BLUE}===============================${NC}"

        read -p $'\033[0;36mChoose an option: \033[0m' opt

        case $opt in
            1) 
                > $HOME/autoprint.log
                termux-wake-lock
                echo -e "${CYAN}Starting AutoPrint...${NC}"
                ask_position_pref    
                nohup python $PREFIX/bin/autoprint.py > autoprint.log 2>&1 &
                sleep 2  # give it a moment to fail if it will

                if pgrep -f autoprint.py > /dev/null; then
                echo -e "${GREEN}AutoPrint started successfully and is running in the background.${NC}"
            else
                echo -e "${RED}Failed to start AutoPrint. Check autoprint.log for details.${NC}"
                echo 
                echo -e "${YELLOW}May be the config file is missing. Restart with autoprint ${NC}"
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
            7) view_live_log ;;
            8)
                echo -e "\n${CYAN}=== Developer Info ===${NC}"
                echo -e "Name: ${GREEN}JuniorSir${NC}"
                echo -e "GitHub: ${BLUE}https://github.com/juniorsir${NC}"
                echo -e "Telegram: ${BLUE}https://t.me/Junior_sir${NC}"
                echo ""
                echo -e "${YELLOW}1.${NC} Open GitHub"
                echo -e "${YELLOW}2.${NC} Open Telegram"
                echo -e "${YELLOW}3.${NC} Back"
                read -p $'\033[0;36mChoose an option: \033[0m' devopt

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
