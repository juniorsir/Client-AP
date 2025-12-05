import socket
import sys
import os
import re
import json
import ssl
import subprocess
import ipaddress
import platform
import webbrowser
import ctypes
from concurrent.futures import ThreadPoolExecutor

# ==========================================
# CONFIGURATION & CONSTANTS
# ==========================================
CONFIG_FILE = os.path.expanduser("~/.autoprint_config.json")

# Mapping ports to protocol names
TARGET_PORTS = {
    9100: "RAW",    # JetDirect / Raw
    631:  "IPP",    # Internet Printing Protocol
    515:  "LPD",    # Line Printer Daemon
    80:   "HTTP",   # Web Admin
    443:  "HTTPS"   # Secure Web Admin
}

# ==========================================
# CROSS-PLATFORM COLOR HANDLING
# ==========================================
class Colors:
    def __init__(self):
        self.use_colors = True
        self.os_type = platform.system()
        
        # Enable VT100 Emulation on Windows 10/11
        if self.os_type == "Windows":
            try:
                kernel32 = ctypes.windll.kernel32
                kernel32.SetConsoleMode(kernel32.GetStdHandle(-11), 7)
            except:
                self.use_colors = False # Disable if legacy cmd.exe

    def color(self, code):
        return code if self.use_colors else ""

C = Colors()
RED     = C.color('\033[91m')
GREEN   = C.color('\033[92m')
YELLOW  = C.color('\033[93m')
BLUE    = C.color('\033[94m')
MAGENTA = C.color('\033[95m')
CYAN    = C.color('\033[96m')
BOLD    = C.color('\033[1m')
NC      = C.color('\033[0m')

# ==========================================
# HELPER FUNCTIONS
# ==========================================
def is_admin():
    """Checks if script has Admin/Root privileges (Required for installation)."""
    try:
        if platform.system() == "Windows":
            return ctypes.windll.shell32.IsUserAnAdmin()
        else:
            return os.geteuid() == 0
    except:
        return False

# ==========================================
# CORE SCANNING CLASS
# ==========================================
class PrinterScanner:
    def __init__(self):
        self.found_devices = []
        self.os_type = platform.system()
        self.scan_counter = 0
        self.total_hosts = 0

    def get_local_network(self):
        """
        Robustly finds local IP. 
        Works online (via Google DNS) and offline (via Hostname).
        """
        local_ip = None
        try:
            # Method 1: Connect to external DNS (Preferred)
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                s.connect(("8.8.8.8", 80))
                local_ip = s.getsockname()[0]
        except:
            # Method 2: Offline Fallback
            try:
                local_ip = socket.gethostbyname(socket.gethostname())
                if local_ip.startswith("127."): return None
            except:
                return None

        if local_ip:
            # Strictly assume /24 for scan speed (Class C subnet)
            base = ".".join(local_ip.split(".")[:3]) + ".0/24"
            return ipaddress.IPv4Network(base, strict=False)
        return None

    def is_host_up(self, ip):
        # Termux/Linux Ping Command
        # -c 1: Count 1
        # -W 1: Timeout 1 second
        cmd = ['ping', '-c', '1', '-W', '1', str(ip)]
        try:
            return subprocess.call(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0
        except:
            return False

    def check_port(self, ip, port):
        """Standard TCP connect check."""
        try:
            with socket.create_connection((ip, port), timeout=0.4):
                return True
        except:
            return False

    # --- IDENTIFICATION PROTOCOLS ---

    def get_snmp_name(self, ip):
        """Sends raw SNMP v1 GetRequest for sysDescr (No external libs)."""
        # OID: 1.3.6.1.2.1.1.1.0
        packet = (
            b'\x30\x29\x02\x01\x00\x04\x06\x70\x75\x62\x6c\x69\x63\xa0\x1c'
            b'\x02\x04\x19\x90\x00\x00\x02\x01\x00\x02\x01\x00\x30\x0e\x30'
            b'\x0c\x06\x08\x2b\x06\x01\x02\x01\x01\x01\x00\x05\x00'
        )
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                s.settimeout(0.8)
                s.sendto(packet, (ip, 161))
                response, _ = s.recvfrom(2048)
                if b'\x2b\x06\x01\x02\x01\x01\x01\x00' in response:
                    idx = response.find(b'\x2b\x06\x01\x02\x01\x01\x01\x00')
                    # Skip OID(8) + Type(1) + Len(1) = 10 bytes
                    return response[idx+10:].decode(errors='ignore').strip()
        except:
            pass
        return None

    def get_ipp_name(self, ip):
        """Sends binary IPP POST request to get printer-make-and-model."""
        payload = b'\x01\x01\x00\x0b\x00\x00\x00\x01\x03'
        header = f"POST / HTTP/1.1\r\nHost: {ip}\r\nContent-Length: {len(payload)}\r\nContent-Type: application/ipp\r\n\r\n".encode()
        try:
            with socket.create_connection((ip, 631), timeout=1.5) as s:
                s.sendall(header + payload)
                res = s.recv(4096).decode(errors='ignore')
                # Regex scrape for common brands
                match = re.search(r'([\w\s-]{3,20}\s(LaserJet|DeskJet|Epson|Canon|Brother|Samsung|Xerox|Kyocera)[\w\s-]+)', res, re.IGNORECASE)
                if match: return match.group(1).strip()
        except:
            pass
        return None

    def get_web_title(self, ip, port):
        """Scrapes <title> tag from Web Interface."""
        try:
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE # Ignore self-signed certs
            
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(1.5)
                if port == 443:
                    with ctx.wrap_socket(s, server_hostname=ip) as ss:
                        ss.connect((ip, port))
                        ss.sendall(f"GET / HTTP/1.1\r\nHost: {ip}\r\n\r\n".encode())
                        data = ss.recv(2048).decode(errors='ignore')
                else:
                    s.connect((ip, port))
                    s.sendall(f"GET / HTTP/1.1\r\nHost: {ip}\r\n\r\n".encode())
                    data = s.recv(2048).decode(errors='ignore')
            
            match = re.search(r'<title>(.*?)</title>', data, re.IGNORECASE)
            if match: return match.group(1).strip()
        except:
            pass
        return None

    def get_pjl_id(self, ip):
        """Legacy PJL query."""
        try:
            with socket.create_connection((ip, 9100), timeout=1.0) as s:
                s.sendall(b"\x1B%-12345X@PJL INFO ID\r\n\x1B%-12345X")
                res = s.recv(512).decode(errors='ignore')
                return res.replace('ID=', '').replace('"', '').replace('@PJL INFO', '').strip()
        except:
            pass
        return None

    def get_mac_vendor(self, ip):
        """Parses ARP table to find MAC and Vendor."""
        # FIX: Android 10+ blocks ARP access. Skip if on Termux/Android.
        if "ANDROID_ROOT" in os.environ or "TERMUX_VERSION" in os.environ:
            return ""

        mac = ""; vendor = ""
        try:
            cmd = f"arp -a {ip}" if self.os_type == "Windows" else f"arp -n {ip}"
            # FIX: Added stderr=subprocess.DEVNULL to silence permission errors
            out = subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL).decode()
            match = re.search(r'([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})', out)
            if match:
                mac = match.group(0).upper().replace("-", ":")
                # Simple OUI Lookup (Examples)
                if mac.startswith("00:15:99"): vendor = " (Samsung)"
                elif mac.startswith("AC:16:2D"): vendor = " (Epson)"
                elif mac.startswith("00:80:77"): vendor = " (Brother)"
                elif mac.startswith("00:C0:EE"): vendor = " (Kyocera)"
                elif mac.startswith("00:17:C8"): vendor = " (Konica)"
                elif mac.startswith("00:00:AA"): vendor = " (Xerox)"
        except:
            pass
        return f"{mac}{vendor}"

    def scan_host(self, ip):
        """Worker function: Ping -> Scan Ports -> Identify."""
        self.scan_counter += 1
        # This prints "Scanning: 10/254 (192.168.1.10)" on the same line
        print(f"Scanning: {self.scan_counter}/{self.total_hosts} ({ip})     ", end='\r')        
        # 1. Ping Check (Optimization)
        if not self.is_host_up(ip):
            return None

        # 2. Port Scan
        open_ports = []
        for p in TARGET_PORTS:
            if self.check_port(str(ip), p):
                open_ports.append(p)
        
        if open_ports:
            # 3. Identify
            ip_str = str(ip)
            name = self.get_snmp_name(ip_str)
            if not name and 631 in open_ports: name = self.get_ipp_name(ip_str)
            if not name and 9100 in open_ports: name = self.get_pjl_id(ip_str)
            if not name and 80 in open_ports: name = self.get_web_title(ip_str, 80)
            if not name and 443 in open_ports: name = self.get_web_title(ip_str, 443)
            
            name = name or "Unknown Printer"
            mac = self.get_mac_vendor(ip_str)
            
            # The \n ensures it prints on a fresh line, not on top of the progress bar
            print(f"\n{GREEN}[FOUND]{NC} {ip_str.ljust(15)} | {CYAN}{name[:35].ljust(35)}{NC} | Ports: {len(open_ports)}")
            return {"ip": ip_str, "name": name, "ports": open_ports, "mac": mac}
        return None

    # Add this inside class PrinterScanner
    def get_detailed_status(self, ip):
        """
        Checks printer status via SNMP OID 1.3.6.1.2.1.25.3.2.1.5.1 (hrPrinterStatus).
        Returns: (Code, Description_String)
        Codes: 3=Idle(Ready), 4=Printing, 5=Warmup, 6=Error(Jam/Open)
        """
        # SNMP Packet for hrPrinterStatus (OID ending in .25.3.2.1.5.1)
        packet = (
            b'\x30\x29\x02\x01\x00\x04\x06\x70\x75\x62\x6c\x69\x63\xa0\x1c'
            b'\x02\x04\x19\x95\x00\x00\x02\x01\x00\x02\x01\x00\x30\x0e\x30'
            b'\x0c\x06\x08\x2b\x06\x01\x02\x01\x19\x03\x02\x01\x05\x01\x05\x00'
        )
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                s.settimeout(1.0)
                s.sendto(packet, (ip, 161))
                response, _ = s.recvfrom(1024)
                
                # Parse the last byte which contains the status integer
                # SNMP Integer type is 0x02, followed by length 0x01, followed by Value
                if b'\x02\x01' in response[-3:]:
                    status_code = response[-1]
                    
                    if status_code == 3: return (3, "Idle (Ready)")
                    if status_code == 4: return (4, "Printing / Processing")
                    if status_code == 5: return (5, "Warming Up")
                    if status_code == 1: return (1, "Offline / Other")
                    if status_code == 2: return (2, "Unknown")
                    if status_code > 5:  return (6, "⚠️ PRINTER ERROR (Jam/Door Open/No Paper)")
                    
        except:
            return (0, "No Status (SNMP Unreachable)")
        
        return (0, "Unknown Status")

    def run(self):
        net = self.get_local_network()
        if not net:
            print(f"{RED}[ERROR] No Wifi.{NC}")
            return

        # 1. Convert to list to get Total Count
        hosts = list(net.hosts())
        self.total_hosts = len(hosts)
        self.scan_counter = 0

        print(f"\n{BOLD}Scanning Network: {YELLOW}{net}{NC}")
        print(f"{CYAN}Total Hosts to Scan: {self.total_hosts}{NC}\n")
        
        # 2. ThreadPool with LOW workers for Termux stability
        with ThreadPoolExecutor(max_workers=15) as executor:
            results = executor.map(self.scan_host, hosts)
            for r in results:
                if r: self.found_devices.append(r)
        
        # Clean up the progress line
        print(" " * 50, end='\r')

# ==========================================
# ACTION FUNCTIONS
def print_universal_test_page(scanner_instance, ip):
    print(f"\n{BOLD}--- Starting Print Job on {ip} ---{NC}")

    # STEP 1: Pre-Flight Check
    print(f"{YELLOW}[STEP 1]{NC} Checking printer health...", end=' ')
    code, msg = scanner_instance.get_detailed_status(ip)
    
    if code == 6: 
        print(f"\n{RED}[STOP]{NC} Printer reports physical error: {BOLD}{msg}{NC}")
        if input(f"{YELLOW}Try anyway? (y/n): {NC}").lower() != 'y': return
    else:
        print(f"{GREEN}OK ({msg}){NC}")

    # --- ATTEMPT 1: Standard PCL ---
    print(f"\n{CYAN}[ATTEMPT 1]{NC} Sending Standard PCL Data...")
    
    payload_pcl = (
        b"\x1B%-12345X@PJL\r\n"
        b"@PJL ENTER LANGUAGE=PCL\r\n" # M111w often hates this line
        b"\r\n"
        b"Standard Network Test\r\n"
        b"IP: " + ip.encode() + b"\r\n"
        b"\f"
        b"\x1B%-12345X"
    )

    try:
        with socket.create_connection((ip, 9100), timeout=4) as s:
            s.sendall(payload_pcl)
        print(f"{GREEN}[SENT]{NC} Data sent to Port 9100.")
    except Exception as e:
        print(f"{RED}[FAIL]{NC} Connection Error: {e}")
        return

    # Check Result
    print(f"{YELLOW}[CHECK]{NC} Waiting 5 seconds for printer reaction...")
    import time
    time.sleep(5)
    
    # Check status again
    new_code, new_msg = scanner_instance.get_detailed_status(ip)
    if new_code == 4:
        print(f"{GREEN}[SUCCESS]{NC} Printer is now Printing!")
        return

    # --- ATTEMPT 2: Raw ASCII Fallback ---
    # If status didn't change, ask user
    print(f"\n{MAGENTA}[ISSUE]{NC} Printer status did not change (Still '{new_msg}').")
    q = input(f"{BOLD}Did the page physically print? (y/n): {NC}").lower()
    
    if q == 'n':
        print(f"\n{CYAN}[ATTEMPT 2]{NC} Trying 'Raw ASCII' Mode (For HP M111w/Host-Based)...")
        
        # This payload has NO COMMANDS. Just text and a Form Feed (\f).
        # This works on almost ALL "dumb" printers.
        payload_raw = (
            b"\r\n"
            b"RAW ASCII MODE TEST\r\n"
            b"-------------------\r\n"
            b"If you can read this,\r\n"
            b"Your printer prefers\r\n"
            b"Plain Text data.\r\n"
            b"\f" # The magic command that forces the page out
        )
        
        try:
            with socket.create_connection((ip, 9100), timeout=4) as s:
                s.sendall(payload_raw)
            print(f"{GREEN}[SENT]{NC} Raw data sent.")
            print(f"{YELLOW}[INFO]{NC} If this fails, this printer ONLY accepts driver-based (IPP) data.")
        except Exception as e:
            print(f"{RED}[FAIL]{NC} {e}")
    else:
        print(f"{GREEN}[DONE]{NC} Test Complete.")

def install_device_os(dev):
    if not is_admin():
        print(f"\n{RED}[ERROR] Administrator privileges required to install printers.{NC}")
        if platform.system() == "Windows":
            print(f"{YELLOW}Hint: Right-click terminal -> 'Run as Administrator'.{NC}")
        else:
            print(f"{YELLOW}Hint: Run with 'sudo python script.py'.{NC}")
        return

    # Clean name for OS compatibility
    clean_name = re.sub(r'[^a-zA-Z0-9]', '_', dev['name'])[:25]
    ip = dev['ip']
    
    print(f"\n{MAGENTA}[INSTALL]{NC} Attempting to install '{clean_name}'...")
    
    if platform.system() == "Windows":
        # PowerShell: Check if port exists -> Create if not -> Add Printer
        ps_cmd = (
            f'$port = "IP_{ip}"; '
            f'$check = Get-PrinterPort -Name $port -ErrorAction SilentlyContinue; '
            f'if (-not $check) {{ '
            f'  Add-PrinterPort -Name $port -PrinterHostAddress "{ip}"; '
            f'}} '
            f'Add-Printer -Name "{clean_name}" -DriverName "Microsoft IPP Class Driver" -PortName $port'
        )
        try:
            subprocess.run(["powershell", "-Command", ps_cmd], check=True)
            print(f"{GREEN}[SUCCESS]{NC} Printer added to Windows.")
        except subprocess.CalledProcessError:
            print(f"{RED}[FAIL]{NC} PowerShell Error. (Driver missing or Port conflict?)")

    elif platform.system() in ["Linux", "Darwin"]:
        # CUPS: Use IPP Everywhere or Generic socket
        uri = f"ipp://{ip}:631/ipp/print" if 631 in dev['ports'] else f"socket://{ip}:9100"
        cmd = ["lpadmin", "-p", clean_name, "-v", uri, "-E", "-m", "everywhere"]
        try:
            subprocess.run(cmd, check=True)
            print(f"{GREEN}[SUCCESS]{NC} Printer added to CUPS.")
        except:
            print(f"{YELLOW}[RETRY]{NC} 'Everywhere' driver failed. Trying Generic...")
            try:
                cmd[-1] = "raw"
                subprocess.run(cmd, check=True)
                print(f"{GREEN}[SUCCESS]{NC} Added as Generic Raw Queue.")
            except:
                 print(f"{RED}[FAIL]{NC} lpadmin failed. Is CUPS installed?")

# ==========================================
# MAIN INTERFACE
# ==========================================
def main():
    scanner = PrinterScanner()
    scanner.run()

    if not scanner.found_devices:
        print(f"\n{YELLOW}No printers found on this network.{NC}")
        return

    print(f"\n{BOLD}--- Available Devices ---{NC}")
    for i, dev in enumerate(scanner.found_devices, 1):
        print(f"{YELLOW}{i}.{NC} {dev['name']}")
        print(f"   IP: {CYAN}{dev['ip']}{NC} | MAC: {dev['mac']}")
        print(f"   Open Ports: {dev['ports']}")

    # Selection Loop
    while True:
        try:
            sel = input(f"\n{BOLD}Select Device # (or 'q' to quit): {NC}").strip()
            if sel.lower() == 'q': return
            idx = int(sel) - 1
            if 0 <= idx < len(scanner.found_devices):
                target = scanner.found_devices[idx]
                break
        except ValueError:
            pass
        print("Invalid selection.")

    # Action Loop
    while True:
        print(f"\n{BOLD}Target: {target['name']}{NC}")
        print("1. Print Test Page (Port 9100)")
        print("2. Open Web Admin (Browser)")
        print("3. Install to OS (Requires Admin)")
        print("4. Save Config JSON")
        print("5. Exit")
        
        choice = input("Choose Action: ").strip()
        
        if choice == "1":
            if 9100 in target['ports']:
                print_universal_test_page(scanner, target['ip'])
            else:
                print(f"{RED}Port 9100 is closed. Cannot send raw test page.{NC}")
        
        elif choice == "2":
            proto = "https" if 443 in target['ports'] else "http"
            url = f"{proto}://{target['ip']}"
            print(f"{BLUE}[BROWSER]{NC} Opening {url}...")
            webbrowser.open(url)
            
        elif choice == "3":
            install_device_os(target)
            
        elif choice == "4":
            with open(CONFIG_FILE, "w") as f:
                json.dump(target, f, indent=4)
            print(f"{BLUE}[SAVED]{NC} Configuration saved to {CONFIG_FILE}")
            
        elif choice == "5":
            break

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n{YELLOW}Operation Cancelled.{NC}")
