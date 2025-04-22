import socket
import json
import os
from concurrent.futures import ThreadPoolExecutor

CONFIG_FILE = os.path.expanduser("~/.autoprint_config.json")

def get_local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
    except Exception:
        local_ip = "127.0.0.1"
    finally:
        s.close()
    return local_ip

def save_printer_ip(ip):
    config = {}
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, "r") as f:
            config = json.load(f)
    config["printer_ip"] = ip
    with open(CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=4)
    print(f"[SAVED] Printer IP saved to config: {ip}")

def is_printer(ip, port=9100, timeout=1):
    try:
        with socket.create_connection((ip, port), timeout=timeout):
            return True
    except:
        return False

def scan_network(base_ip):
    print(f"[Scanning subnet {base_ip}.0/24 for printers on port 9100...]")
    ips = [f"{base_ip}.{i}" for i in range(1, 255)]
    printers = []

    with ThreadPoolExecutor(max_workers=100) as executor:
        results = executor.map(is_printer, ips)
        for ip, is_open in zip(ips, results):
            if is_open:
                printers.append(ip)

    return printers

def choose_printer(printers):
    print("\n[Available Printers]")
    for idx, ip in enumerate(printers, 1):
        print(f"{idx}. {ip}")
    choice = input("Select a printer to save (1/2/...): ").strip()
    if choice.isdigit() and 1 <= int(choice) <= len(printers):
        return printers[int(choice)-1]
    else:
        print("Invalid choice.")
        return None

def send_test_print(message="It's working\n\n"):
    if not os.path.exists(CONFIG_FILE):
        print("[ERROR] No printer configured. Please run the setup first.")
        return
    try:
        with open(CONFIG_FILE, "r") as f:
            config = json.load(f)
            ip = config.get("printer_ip")
            if not ip:
                raise ValueError("Printer IP not found in config.")
            print(f"[INFO] Sending test print to {ip}...")
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.connect((ip, 9100))
                s.sendall(message.encode('utf-8'))
            print("[SUCCESS] Print sent successfully.")
    except Exception as e:
        print(f"[ERROR] {e}")

def main():
    local_ip = get_local_ip()
    if local_ip.startswith("127."):
        print("[ERROR] Could not detect proper local IP. Are you connected to a network?")
        return

    base_ip = ".".join(local_ip.split('.')[:3])
    printers = scan_network(base_ip)

    if not printers:
        print("No printers found on the local network.")
        return

    selected_ip = choose_printer(printers)
    if selected_ip:
        save_printer_ip(selected_ip)
        send_test_print()

if __name__ == "__main__":
    main()
