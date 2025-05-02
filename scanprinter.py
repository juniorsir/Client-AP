import socket
import json
import os
from concurrent.futures import ThreadPoolExecutor
# ANSI color codes
RED     = '\033[91m'
GREEN   = '\033[92m'
YELLOW  = '\033[93m'
BLUE    = '\033[94m'
MAGENTA = '\033[95m'
CYAN    = '\033[96m'
WHITE   = '\033[97m'
BOLD    = '\033[1m'
UNDERLINE = '\033[4m'
NC      = '\033[0m'  # No Color / Reset

CONFIG_FILE = os.path.expanduser("~/.autoprint_config.json")
ALERT_MESSAGE = ">>> AutoPrint configuration attempt <<<\n"

def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
        return local_ip
    except Exception as e:
        print(f"{RED}[ERROR] Could not detect local IP: {e}{NC}")
        return None

def is_printer(ip, port=9100, timeout=1):
    try:
        with socket.create_connection((ip, port), timeout=timeout) as sock:
            return ip
    except:
        return None

def scan_printers(base_ip):
    print(f"\n{CYAN}[Scanning subnet {YELLOW}{base_ip}.0/24{CYAN} for printers on port {YELLOW}9100{CYAN}...]{NC}")
    ips = [f"{base_ip}.{i}" for i in range(1, 255)]
    found = []

    with ThreadPoolExecutor(max_workers=100) as executor:
        results = executor.map(is_printer, ips)
        for ip in results:
            if ip:
                print(f"{GREEN}[FOUND]{NC} Printer detected on: {YELLOW}{ip}{NC}")
                found.append(ip)
    return found

def save_printer_ip(ip):
    config = {}
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, "r") as f:
            try:
                config = json.load(f)
            except json.JSONDecodeError:
                pass
    config["printer_ip"] = ip
    with open(CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=4)
    print(f"{BLUE}[SAVED]{NC} Printer IP saved to config: {CYAN}{ip}{NC}")

def choose_printer(printers):
    print("\n[Available Printers]")
    for i, ip in enumerate(printers, 1):
        print(f"{YELLOW}{i}{NC}. {CYAN}{ip}{NC}")

    while True:
        choice = input("Select a printer to save (1/2/...): ").strip()
        if choice.isdigit() and 1 <= int(choice) <= len(printers):
            return printers[int(choice) - 1]
        print(f"{RED}Invalid selection. Try again.{NC}")


def get_printer_model(ip):
    try:
        pjl_cmd = b"\x1B%-12345X@PJL INFO ID\r\n\x1B%-12345X"
        with socket.create_connection((ip, 9100), timeout=2) as sock:
            sock.sendall(pjl_cmd)
            response = sock.recv(1024).decode(errors="ignore").strip()
            return response if response else "[Unknown model]"
    except:
        return "[Unknown model]"

def send_alert_to_printer(ip, message=ALERT_MESSAGE):
    try:
        with socket.create_connection((ip, 9100), timeout=2) as sock:
            sock.sendall(message.encode())
            print(f"{MAGENTA}[ALERT SENT]{NC} Sent alert to: {YELLOW}{ip}{NC}")
    except Exception as e:
        print(f"{RED}[WARNING]{NC} Failed to send alert to {YELLOW}{ip}{NC}: {RED}{e}{NC}")

    # Show model after alert
    model = get_printer_model(ip)
    print(f"{BLUE}[MODEL INFO]{NC} {YELLOW}{ip}{NC} → {CYAN}{model}{NC}")

def main():
    local_ip = get_local_ip()
    if not local_ip or local_ip.startswith("127."):
        print(f"{RED}[ERROR]{NC} Could not detect proper local IP. {YELLOW}Are you connected to a network?{NC}")
        return

    base_ip = ".".join(local_ip.split(".")[:3])
    printers = scan_printers(base_ip)

    if not printers:
        print(f"{YELLOW}No printers found on the network.{NC}")
        return

    print(f"\n{CYAN}[INFO]{NC} Sending alert message to detected printers...")
    for ip in printers:
        send_alert_to_printer(ip)

    selected = choose_printer(printers)
    save_printer_ip(selected)

if __name__ == "__main__":
    main()
