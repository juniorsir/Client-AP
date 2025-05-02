import os
import sys
import json
import time
import signal
import subprocess
import threading
import requests
import socket
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

# ANSI Colors
RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
BLUE = "\033[0;34m"
CYAN = "\033[0;36m"
NC = "\033[0m"

HOME = str(Path.home())
CONFIG_FILE = os.path.join(HOME, ".autoprint_config.json")
BACKUP_FILE = os.path.join(HOME, ".autoprint_config_backup.json")
VERSION_FILE = os.path.join(HOME, ".autoprint_version")
LOG_FILE = os.path.join(HOME, "autoprint.log")
REPO_URL = "https://github.com/juniorsir/Client-AP"
REMOTE_VERSION_URL = f"{REPO_URL}/raw/main/version.txt"

# Spinner
def spinner(target_pid):
    symbols = ['|', '/', '-', '\\']
    i = 0
    while True:
        if not is_process_running(target_pid):
            break
        print(f"\r{CYAN}Scanning {symbols[i % 4]}{NC}", end="", flush=True)
        time.sleep(0.1)
        i += 1

def is_process_running(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False

# Config Setup
def set_config():
    if os.path.exists(CONFIG_FILE):
        print(f"{YELLOW}A saved configuration was found:{NC}")
        with open(CONFIG_FILE, "r") as f:
            print(json.dumps(json.load(f), indent=2))
        use_saved = input(f"{YELLOW}Do you want to use this saved config? (y/n): {NC}")
        if use_saved.lower() == 'y':
            print(f"{GREEN}Using existing config.{NC}")
            return

    print(f"\n{CYAN}-- AutoPrint Configuration Setup --{NC}\n")
   
    config = {
        
        "pc_user": input(f"{YELLOW}Enter PC username: {NC}"),
        "remote_folder": input(f"{YELLOW}Enter PC folder: {NC}"),
        "image_width": input(f"{YELLOW}Default image width in mm: {NC}"),
        "always_ask_pos": input(f"{YELLOW}Always ask for image position? (y/n): {NC}").lower() != 'n'
    }

    with open(CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=2)
    print(f"{GREEN}Configuration saved successfully.{NC}")

# Live log viewer
def view_live_log():
    print(f"{CYAN}Press Ctrl+C to stop viewing and return to the menu.{NC}")
    try:
        with open(LOG_FILE, "r") as f:
            f.seek(0, os.SEEK_END)
            while True:
                line = f.readline()
                if not line:
                    time.sleep(0.5)
                    continue
                line = line.replace("INFO", f"{GREEN}[INFO]{NC}") \
                           .replace("ERROR", f"{RED}[ERROR]{NC}") \
                           .replace("OK", f"{GREEN}[OK]{NC}") \
                           .replace("WARN", f"{YELLOW}[WARN]{NC}") \
                           .replace("DEBUG", f"{BLUE}[DEBUG]{NC}")
                print(line, end="")
    except KeyboardInterrupt:
        print(f"\n{YELLOW}Returning to menu...{NC}")

# Position Selector
def ask_position_pref():
    print(f"\n{CYAN}[Choose image position]{NC}")
    print(f"{YELLOW}1.{NC} Top-Left\n{YELLOW}2.{NC} Center\n{YELLOW}3.{NC} Bottom-Right")
    choice = input(f"{YELLOW}Enter choice (1/2/3): {NC}")
    pos_map = {'1': 'top-left', '2': 'center', '3': 'bottom-right'}
    pos_code = pos_map.get(choice, 'center')

    with open(CONFIG_FILE, "r") as f:
        config = json.load(f)
    config["image_position"] = pos_code
    with open(CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=2)
    print(f"{GREEN}Image position set to: {pos_code}{NC}")

# Update Check
def check_update_notice():
    try:
        remote_ver = requests.get(REMOTE_VERSION_URL).text.strip()
    except:
        print(f"{RED}Failed to check for updates.{NC}")
        return
    if not os.path.exists(VERSION_FILE):
        with open(VERSION_FILE, "w") as f:
            f.write("v0.0.0")
    with open(VERSION_FILE, "r") as f:
        local_ver = f.read().strip()

    if remote_ver != local_ver:
        print(f"{YELLOW}╔══════════════════════════════════════╗{NC}")
        print(f"{YELLOW}║{NC}   {GREEN}★ New Update Available! ★{NC}         {YELLOW}║{NC}")
        print(f"{YELLOW}╠══════════════════════════════════════╣{NC}")
        print(f"{YELLOW}║{NC} Current: {CYAN}{local_ver}{NC}  Remote: {CYAN}{remote_ver}{NC}     {YELLOW}║{NC}")
        print(f"{YELLOW}╚══════════════════════════════════════╝{NC}")
        update = input(f"{YELLOW}Do you want to update now? (y/n): {NC}")
        if update.lower() == 'y':
            os.system("autoprint-update")
        else:
            print(f"{YELLOW}Update skipped.{NC}")
    else:
        print(f"{GREEN}You're using the latest version ({local_ver}).{NC}")

# Menu
def show_menu():
    while True:
        print(f"\n{BLUE}======= AutoPrint Menu ======={NC}")
        print(f"{YELLOW}1.{NC} Start AutoPrint")
        print(f"{YELLOW}2.{NC} Stop AutoPrint")
        print(f"{YELLOW}3.{NC} Edit Configuration")
        print(f"{YELLOW}4.{NC} Configure Printer")
        print(f"{YELLOW}5.{NC} Exit")
        print(f"{YELLOW}6.{NC} Check for Updates")
        print(f"{YELLOW}7.{NC} View Live Log")
        print(f"{YELLOW}8.{NC} Developer Info")
        print(f"{BLUE}==============================={NC}")

        choice = input(f"{CYAN}Choose an option: {NC}")
        if choice == '1':
            open(LOG_FILE, 'w').close()
            os.system("termux-wake-lock")
            ask_position_pref()
            subprocess.Popen(["nohup", "python", os.path.join(os.environ['PREFIX'], "bin", "autoprint.py")],
                             stdout=open(LOG_FILE, "a"), stderr=subprocess.STDOUT)
            time.sleep(2)
            if subprocess.getoutput("pgrep -f autoprint.py"):
                print(f"{GREEN}AutoPrint started in background.{NC}")
            else:
                print(f"{RED}Failed to start. Check log file.{NC}")
                os.system("termux-wake-unlock")
        elif choice == '2':
            os.system("pkill -f autoprint.py")
            os.system("termux-wake-unlock")
            print(f"{RED}AutoPrint stopped.{NC}")
        elif choice == '3':
            set_config()
        elif choice == '4':
            subprocess.run(["python", os.path.join(os.environ['PREFIX'], "bin", "scanprinter.py")])
        elif choice == '5':
            print(f"{CYAN}Exiting.{NC}")
            break
        elif choice == '6':
            check_update_notice()
        elif choice == '7':
            view_live_log()
        elif choice == '8':
            print(f"{CYAN}Name: {GREEN}JuniorSir{NC}")
            print(f"GitHub: {BLUE}https://github.com/juniorsir{NC}")
            print(f"Telegram: {BLUE}https://t.me/Junior_sir{NC}")
            sub = input(f"{YELLOW}1.{NC} Open GitHub  2.{NC} Open Telegram  3.{NC} Back\n{CYAN}Choose: {NC}")
            if sub == '1':
                os.system("termux-open-url https://github.com/juniorsir")
            elif sub == '2':
                os.system("termux-open-url https://t.me/Junior_sir")
        else:
            print(f"{RED}Invalid option.{NC}")

# Run
if __name__ == "__main__":
    os.system("clear")
    check_update_notice()
    set_config()
    show_menu()
    
