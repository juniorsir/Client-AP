#!/data/data/com.termux/files/usr/bin/bash

GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

check_and_install_pkg() {
    pkg_name="$1"
    echo -e "${BLUE}[*] Checking $pkg_name...${RESET}"

    if pkg list-installed | grep -q "^$pkg_name"; then
        latest_version=$(pkg list-all | grep "^$pkg_name " | awk '{print $2}')
        installed_version=$(pkg list-installed | grep "^$pkg_name " | awk '{print $2}')

        if [ "$latest_version" != "$installed_version" ]; then
            echo -e "${YELLOW}[+] New version of $pkg_name available: $installed_version → $latest_version${RESET}"
            pkg install -y "$pkg_name"
        else
            echo -e "${GREEN}[✓] $pkg_name is up to date ($installed_version)${RESET}"
        fi
    else
        echo -e "${YELLOW}[+] Installing $pkg_name...${RESET}"
        pkg install -y "$pkg_name"
    fi
}

check_and_install_pip() {
    module="$1"
    echo -e "${BLUE}[*] Installing/upgrading Python module: $module...${RESET}"
    pip install --upgrade "$module"
}

echo -e "${BLUE}[*] Updating pkg sources...${RESET}"
apt update && apt upgrade -y

echo -e "${BLUE}[*] Installing core packages...${RESET}"
check_and_install_pkg python
check_and_install_pkg make
check_and_install_pkg wget
check_and_install_pkg clang
check_and_install_pkg libjpeg-turbo
check_and_install_pkg freetype
check_and_install_pkg git
check_and_install_pkg curl
check_and_install_pkg termux-api
check_and_install_pkg iproute2
check_and_install_pkg openssh
check_and_install_pkg termux-exec
check_and_install_pkg jq

echo -e "${BLUE}[*] Setting up Termux storage access...${RESET}"
termux-setup-storage

echo -e "${BLUE}[*] Installing/upgrading Python tools...${RESET}"
pip install --upgrade pip setuptools wheel

echo -e "${BLUE}[*] Installing Pillow with build flags...${RESET}"
env INCLUDE="$PREFIX/include" LDFLAGS=" -lm" pip install Pillow

echo -e "${BLUE}[*] Installing remaining Python modules...${RESET}"
check_and_install_pip watchdog
check_and_install_pip reportlab

echo -e "${BLUE}[*] Downloading latest AutoPrint setup script...${RESET}"
curl -L -o autoprint-update.sh https://raw.githubusercontent.com/juniorsir/Client-AP/main/autoprint-update.sh
chmod +x autoprint-update.sh
mv autoprint-update.sh $PREFIX/bin/autoprint-update
sleep 1.5
clear
echo -e "${GREEN}[✓] Setup complete!${RESET}"
echo
echo -e "${YELLOW}You can now run the bot with:${RESET}"
echo -e "${GREEN}Run autoprint-update to update Tool${RESET}"
sleep 0.5

autoprint
