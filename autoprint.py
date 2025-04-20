
import os
import time
import json
import subprocess
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from datetime import datetime
import threading
import itertools
import sys
from PIL import Image
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4


FAILED_DIR = os.path.expanduser("~/autoprint_failed")
os.makedirs(FAILED_DIR, exist_ok=True)

CONFIG_FILE = os.path.expanduser("~/.autoprint_config.json")

A4_WIDTH_PX = 2480  # 210mm * 300 DPI / 25.4
A4_HEIGHT_PX = 3508  # 297mm * 300 DPI / 25.4

def loading_animation(message, stop_event):
    spinner = itertools.cycle(['|', '/', '-', '\\'])
    while not stop_event.is_set():
        c = next(spinner)
        sys.stdout.write(f'\r{message} {c}')
        sys.stdout.flush()
        time.sleep(0.1)
    sys.stdout.write('\r' + ' ' * (len(message) + 5) + '\r')  # Clear the line
    sys.stdout.flush()
  
def notify_process(title, message):
    try:
        subprocess.run([
            "termux-notification",
            "--title", f"{title}",
            "--content", f"{message}",
            "--priority", "high"
        ])
    except Exception as e:
        print(f"[Notification Error] {e}")
def load_config():
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, "r") as f:
            return json.load(f)
    else:
        return {}

def save_config(config):
    with open(CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=4)

def wait_for_ready_file(original_path, timeout=15):
    """Wait until the image file becomes available and the .pending file is gone."""
    base_dir = os.path.dirname(original_path)
    base_name = os.path.basename(original_path)

    for _ in range(timeout):
        # Look for the file without `.pending-` prefix
        for f in os.listdir(base_dir):
            if f.endswith(base_name) and not f.startswith(".pending"):
                full_path = os.path.join(base_dir, f)
                if os.path.exists(full_path):
                    return full_path
        time.sleep(1)

    print(f"[SKIPPED] File not finalized in time: {original_path}")
    return None

def ask_config():
    config = load_config()

    print("\n[Configuring for first time use...]")

    pc_ip = config.get("pc_ip") or input("Enter PC IP address: ").strip()
    pc_user = config.get("pc_user") or input("Enter PC username: ").strip()
    remote_folder = config.get("remote_folder") or input("Enter remote PC folder path (e.g. /home/you/printjobs): ").strip()
    image_width = config.get("image_width") or input("Set default image width in mm (e.g. 120): ").strip()
    always_ask_pos = config.get("always_ask_pos", True)

    config.update({
        "pc_ip": pc_ip,
        "pc_user": pc_user,
        "remote_folder": remote_folder,
        "image_width": image_width,
        "always_ask_pos": always_ask_pos
    })

    save_config(config)
    return config

def ask_position():
    print("\nChoose image position on paper:")
    print("1. Top-Left")
    print("2. Center")
    print("3. Bottom-Right")
    choice = input("Enter choice (1/2/3): ").strip()
    positions = {
        "1": "+50+50",
        "2": "-gravity center",
        "3": "-gravity southeast"
    }
    return positions.get(choice, "-gravity center")

def convert_to_pdf(image_path, output_pdf, width_mm, position_args, default_aspect=False):
    stop_event = threading.Event()
    loader_thread = threading.Thread(target=loading_animation, args=("Converting image...", stop_event))
   
    loader_thread.start()

    try:
        width_mm = int(width_mm) if str(width_mm).strip().isdigit() else 160  # fallback default
        print(f"[INFO] Using width: {width_mm} mm")
        width_points = width_mm * 2.83465  # Convert mm to points
        a4_width, a4_height = A4

        img = Image.open(image_path)

        if default_aspect:
            # Force 4:3 aspect ratio
            aspect_ratio = 3 / 4
        else:
            aspect_ratio = img.height / img.width

        height_points = width_points * aspect_ratio

        # Decide image position
        if "center" in position_args:
            x = (a4_width - width_points) / 2
            y = (a4_height - height_points) / 2
        elif "southeast" in position_args:
            x = a4_width - width_points - 50
            y = 50
        else:  # Top-left default
            x = 50
            y = a4_height - height_points - 50

        date_str = datetime.now().strftime("%A, %d %B %Y")

        c = canvas.Canvas(output_pdf, pagesize=A4)
        c.drawImage(image_path, x, y, width=width_points, height=height_points)
        c.setFont("Helvetica", 12)
        c.drawString(50, a4_height - 30, date_str)  # Add date at top-left
        c.save()

    except Exception as e:
        print("\nImage conversion failed:", e)
    finally:
        stop_event.set()
        loader_thread.join()

def send_to_pc(pdf_path, config):
    stop_event = threading.Event()
    loader_thread = threading.Thread(target=loading_animation, args=("Sending to PC...", stop_event))
   
    loader_thread.start()

    remote_path = f"{config['pc_user']}@{config['pc_ip']}:{config['remote_folder']}/"
    try:
        subprocess.run(["scp", pdf_path, remote_path], check=True)
        print(f"\n[SENT] {pdf_path} -> {remote_path}")
       
    except subprocess.CalledProcessError:
        print("\n[ERROR] Failed to send PDF.")
        if os.path.exists(pdf_path):
            try:
                os.makedirs(FAILED_DIR, exist_ok=True)
                fallback_path = os.path.join(FAILED_DIR, os.path.basename(pdf_path))
                os.rename(pdf_path, fallback_path)
                print(f"[SAVED LOCALLY] to {fallback_path}")
            except Exception as e:
                print(f"[CRITICAL] Failed to move file to fallback folder: {e}")
         
        else:
            print("[SKIPPED] File not created or already removed, nothing to save.")
    finally:
        stop_event.set()
        loader_thread.join()

class PhotoHandler(FileSystemEventHandler):
    def __init__(self, config):
        self.config = config

    def on_created(self, event):
        if event.is_directory:
            return

        file_path = event.src_path
 
        if ".pending-" in os.path.basename(file_path):
        # Extract the real image name from pending file name
            real_name = os.path.basename(file_path).split('-')[-1]
            dir_path = os.path.dirname(file_path)
            final_image_path = os.path.join(dir_path, real_name)

            print(f"[PENDING DETECTED] Waiting for final file: {real_name}")

            for _ in range(20):  # Check up to ~20 seconds
                if os.path.exists(final_image_path):
                    print(f"[READY] File is finalized: {final_image_path}")
                   
                    file_path = final_image_path
                    break
                time.sleep(1)
            else:
                print(f"[TIMEOUT] File not finalized: {real_name}")
                return

        if not file_path.lower().endswith((".jpg", ".jpeg", ".png")):
            return

        print(f"[NEW FILE] {file_path}")
      
        filename = f"photo_{datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
        output_pdf = os.path.join("/data/data/com.termux/files/home", filename)

        pos_map = {
            "top-left": "+50+50",
            "center": "-gravity center",
            "bottom-right": "-gravity southeast"
        }
        position_args = pos_map.get(self.config.get("image_position", "center"), "-gravity center")
        convert_to_pdf(file_path, output_pdf, self.config["image_width"], position_args)
        send_to_pc(output_pdf, self.config)
def start_watcher(paths, config):
    observer = Observer()
    event_handler = PhotoHandler(config)
    for path in paths:
        if os.path.exists(path):
            observer.schedule(event_handler, path, recursive=False)
            print(f"[Watching] {path}")
        else:
            print(f"[WARNING] Path does not exist: {path}")
    observer.start()
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()

if __name__ == "__main__":
    if not os.path.exists(CONFIG_FILE):
        config = ask_config()
    else:
        config = load_config()

    folders = [
        "/storage/emulated/0/DCIM/Camera",
        "/storage/emulated/0/Download",
        "/storage/emulated/0/Bluetooth"
    ]
    start_watcher(folders, config)
                  
