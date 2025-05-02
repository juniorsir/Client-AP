import os
import time
import json
import subprocess
import threading
import itertools
import sys
import re
import socket
from datetime import datetime
from PIL import Image
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
import http.server
import socketserver

# Constants
FAILED_DIR = os.path.expanduser("~/autoprint_failed")
CONFIG_FILE = os.path.expanduser("~/.autoprint_config.json")
A4_WIDTH_PX = 2480
A4_HEIGHT_PX = 3508
os.makedirs(FAILED_DIR, exist_ok=True)

# Logging
def log_message(message, level="INFO"):
    colors = {
        "INFO": "\033[94m", "SUCCESS": "\033[92m",
        "ERROR": "\033[91m", "RESET": "\033[0m"
    }
    color = colors.get(level, "")
    reset = colors["RESET"]
    print(f"{color}[{level}]{reset} {message}")
    with open("autoprint.log", "a") as log_file:
        log_file.write(f"[{level}] {message}\n")

# Notification (Termux)
def notify_process(title, message):
    try:
        subprocess.run([
            "termux-notification", "--title", title,
            "--content", message, "--priority", "high"
        ])
    except Exception as e:
        log_message(f"Notification error: {e}", "ERROR")

# Config
def load_config():
    return json.load(open(CONFIG_FILE)) if os.path.exists(CONFIG_FILE) else {}

def save_config(config):
    with open(CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=4)

def ask_config():
    config = load_config()
    print("\n[Configuring for first time use...]")
    config.update({
        "pc_ip": config.get("pc_ip") or input("Enter PC IP: ").strip(),
        "pc_user": config.get("pc_user") or input("Enter PC username: ").strip(),
        "remote_folder": config.get("remote_folder") or input("Enter remote folder: ").strip(),
        "image_width": config.get("image_width") or input("Image width (mm): ").strip(),
        "always_ask_pos": config.get("always_ask_pos", True)
    })
    save_config(config)
    return config

def ask_position():
    print("\nChoose image position:\n1. Top-Left\n2. Center\n3. Bottom-Right")
    choice = input("Enter choice (1/2/3): ").strip()
    return {"1": "+50+50", "2": "-gravity center", "3": "-gravity southeast"}.get(choice, "-gravity center")

# PDF Conversion
def convert_to_pdf(image_path, output_pdf, width_mm, position_args, default_aspect=False):
    threading.Thread(target=start_server, args=(output_pdf,)).start()
    try:
        width_mm = int(width_mm)
        width_pt = width_mm * 2.83465
        a4_w, a4_h = A4
        img = Image.open(image_path)
        aspect = 3 / 4 if default_aspect else img.height / img.width
        height_pt = width_pt * aspect

        x, y = {
            "-gravity center": ((a4_w - width_pt) / 2, (a4_h - height_pt) / 2),
            "-gravity southeast": (a4_w - width_pt - 50, 50)
        }.get(position_args, (50, a4_h - height_pt - 50))

        c = canvas.Canvas(output_pdf, pagesize=A4)
        c.drawImage(image_path, x, y, width=width_pt, height=height_pt)
        c.setFont("Helvetica", 12)
        c.drawString(50, a4_h - 30, datetime.now().strftime("%A, %d %B %Y"))
        c.save()
        log_message(f"Image converted to PDF: {output_pdf}", "SUCCESS")
    except Exception as e:
        log_message(f"Conversion failed: {e}", "ERROR")

# Print & Fallback
def get_saved_printer_ip():
    try:
        return json.load(open(CONFIG_FILE)).get("printer_ip")
    except Exception:
        return None

def send_to_printer(pdf_path):
    printer_ip = get_saved_printer_ip()
    if not printer_ip:
        log_message("No printer IP configured.", "ERROR")
        return
    if not os.path.exists(pdf_path):
        log_message(f"File not found: {pdf_path}", "ERROR")
        return
    try:
        with open(pdf_path, "rb") as f:
            data = f.read()
        with socket.create_connection((printer_ip, 9100), timeout=5) as sock:
            sock.sendall(data)
        log_message(f"Sent to printer: {printer_ip}", "SUCCESS")
    except Exception as e:
        log_message(f"Print failed: {e}", "ERROR")
        try:
            fallback_path = os.path.join(FAILED_DIR, os.path.basename(pdf_path))
            os.rename(pdf_path, fallback_path)
            log_message(f"Saved to: {fallback_path}", "INFO")
        except Exception as move_error:
            log_message(f"Fallback save failed: {move_error}", "ERROR")

# File Watcher
class PhotoHandler(FileSystemEventHandler):
    def __init__(self, config): self.config = config

    def on_created(self, event):
        if event.is_directory: return
        file_path = event.src_path

        if ".pending-" in os.path.basename(file_path):
            real_name = os.path.basename(file_path).split('-')[-1]
            final_path = os.path.join(os.path.dirname(file_path), real_name)
            for _ in range(20):
                if os.path.exists(final_path):
                    file_path = final_path
                    break
                time.sleep(1)
            else:
                return

        if not file_path.lower().endswith((".jpg", ".jpeg", ".png")):
            return

        log_message(f"New image detected: {file_path}", "INFO")
        pdf_name = f"photo_{datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
        output_pdf = os.path.join("/data/data/com.termux/files/home", pdf_name)
        pos_map = {"top-left": "+50+50", "center": "-gravity center", "bottom-right": "-gravity southeast"}
        position = pos_map.get(self.config.get("image_position", "center"), "-gravity center")

        convert_to_pdf(file_path, output_pdf, self.config["image_width"], position)
        send_to_printer(output_pdf)

# Watcher Start
def start_watcher(paths, config):
    observer = Observer()
    handler = PhotoHandler(config)
    for path in paths:
        if os.path.exists(path):
            observer.schedule(handler, path, recursive=False)
            log_message(f"Watching: {path}", "INFO")
        else:
            log_message(f"Path not found: {path}", "ERROR")
    observer.start()
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()

# Preview Server
def start_server(file_path, port=8080):
    os.chdir(os.path.dirname(file_path))
    handler = http.server.SimpleHTTPRequestHandler
    try:
        log_message(f"Preview at: http://localhost:{port}/{os.path.basename(file_path)}", "INFO")
        print("Press Ctrl+C to stop server.")
        with socketserver.TCPServer(("", port), handler) as httpd:
            httpd.serve_forever()
    except KeyboardInterrupt:
        log_message("Server stopped", "INFO")

# Main
if __name__ == "__main__":
    config = ask_config() if not os.path.exists(CONFIG_FILE) else load_config()
    watch_paths = ["/storage/emulated/0/DCIM/Camera", "/storage/emulated/0/Bluetooth"]
    start_watcher(watch_paths, config)
            
