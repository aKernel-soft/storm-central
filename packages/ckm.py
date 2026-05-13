#!/usr/bin/env python3

import curses
import os
import signal
import subprocess
import json
import hashlib
import stat
import base64
import shutil
import threading
import time
import uuid
import platform
import socket
import getpass
import random

def get_device_fingerprint():
    components = []
    try:
        mac = uuid.getnode()
        components.append(str(mac))
    except:
        pass
    try:
        hostname = socket.gethostname()
        components.append(hostname)
    except:
        pass
    try:
        components.append(platform.platform())
    except:
        pass
    try:
        components.append(getpass.getuser())
    except:
        pass
    if not components:
        components.append(str(random.random()))
    return "|".join(components)

def generate_device_key():
    fingerprint = get_device_fingerprint()
    key = fingerprint.encode()
    for _ in range(10000):
        key = hashlib.sha512(key).digest()
    return key * 2

CONFIG_FILE = os.path.expanduser("~/.ckm_config.enc")

def load_or_create_key():
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'rb') as f:
                encrypted_key = f.read()
            master = hashlib.sha256("CKM-MASTER-2024".encode()).digest()
            key = bytes(a ^ b for a, b in zip(encrypted_key, master * 4))
            if len(key) == 128:
                return key
        except:
            pass
    
    key = generate_device_key()
    master = hashlib.sha256("CKM-MASTER-2024".encode()).digest()
    encrypted_key = bytes(a ^ b for a, b in zip(key, master * 4))
    with open(CONFIG_FILE, 'wb') as f:
        f.write(encrypted_key)
    return key

ENCRYPTION_KEY = load_or_create_key()
FACTORY_KEY = "CKM-FC-26-SC-K"

def xor_encrypt(data, key):
    key_len = len(key)
    return bytes(data[i] ^ key[i % key_len] for i in range(len(data)))

DEV_PASSWORD = "1337"
DEBUG = False
CURRENT_PATH = os.path.expanduser("~")
current_process = None
clipboard = None
output_active = False
output_lines = []
output_status = ""

def encrypt_file(filepath):
    try:
        with open(filepath, 'rb') as f:
            data = f.read()
        encrypted = xor_encrypt(data, ENCRYPTION_KEY)
        encrypted_b64 = base64.b64encode(encrypted)
        enc_path = filepath + ".ckmenc"
        with open(enc_path, 'wb') as f:
            f.write(encrypted_b64)
        return True
    except:
        return False

def decrypt_to_memory(filepath):
    try:
        with open(filepath, 'rb') as f:
            encrypted_b64 = f.read()
        encrypted = base64.b64decode(encrypted_b64)
        decrypted = xor_encrypt(encrypted, ENCRYPTION_KEY)
        return decrypted
    except:
        return None

def run_encrypted(filepath, stdscr=None):
    global current_process, output_active, output_lines, output_status
    
    try:
        decrypted = decrypt_to_memory(filepath)
        if decrypted is None:
            return False, "Decryption failed"
        
        tmp_path = filepath + ".tmp"
        with open(tmp_path, 'wb') as f:
            f.write(decrypted)
        os.chmod(tmp_path, 0o755)
        
        dirpath = os.path.dirname(filepath)
        curses.endwin()
        
        if '.sh' in filepath:
            current_process = subprocess.Popen(['bash', tmp_path], cwd=dirpath, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.PIPE)
        elif '.py' in filepath:
            current_process = subprocess.Popen(['python3', tmp_path], cwd=dirpath, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.PIPE)
        else:
            current_process = subprocess.Popen(['./' + os.path.basename(tmp_path)], cwd=dirpath, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.PIPE)
        
        output_lines = []
        output_active = True
        output_status = "RUNNING..."
        
        def reader():
            global output_lines, output_active, output_status
            try:
                stdout_data, _ = current_process.communicate(timeout=10)
                if stdout_data:
                    text = stdout_data.decode('utf-8', errors='replace')
                    output_lines = text.split('\n')
                    if not output_lines or output_lines == ['']:
                        output_lines = ["[Program finished with no output]"]
            except subprocess.TimeoutExpired:
                current_process.kill()
                output_lines = ["[Program interrupted — timeout]"]
            except Exception as e:
                output_lines = [f"[Error: {e}]"]
            
            current_process.wait()
            output_status = f"EXITED (code {current_process.returncode})"
            time.sleep(0.5)
            try:
                os.remove(tmp_path)
            except:
                pass
            curses.doupdate()
        
        threading.Thread(target=reader, daemon=True).start()
        return True, "Launched"
    except Exception as e:
        curses.initscr()
        return False, str(e)

def sign_and_encrypt(filepath, key):
    if filepath.endswith('.ckmenc') or filepath.endswith('.sig'):
        return False
    for old_ext in ['.ckmsig', '.sig', '.ckmenc']:
        old_path = filepath + old_ext
        if os.path.exists(old_path):
            os.remove(old_path)
    if not encrypt_file(filepath):
        return False
    enc_path = filepath + ".ckmenc"
    signature = hashlib.sha256()
    with open(enc_path, 'rb') as f:
        signature.update(f.read())
    signature.update(key.encode())
    with open(enc_path + ".sig", 'w') as f:
        json.dump({
            "program": os.path.basename(filepath),
            "signature": signature.hexdigest(),
            "key_hash": hashlib.sha256(key.encode()).hexdigest()[:8],
            "device_id": hashlib.sha256(get_device_fingerprint().encode()).hexdigest()[:12]
        }, f)
    try:
        os.remove(filepath)
    except:
        pass
    return True

def verify_encrypted(enc_path, key):
    meta_file = enc_path + ".sig"
    if not os.path.exists(meta_file):
        return False, "Not signed"
    try:
        with open(meta_file, 'r') as f:
            meta = json.load(f)
        if meta.get("key_hash") != hashlib.sha256(key.encode()).hexdigest()[:8]:
            return False, "Wrong key"
        current_device_id = hashlib.sha256(get_device_fingerprint().encode()).hexdigest()[:12]
        if meta.get("device_id") != current_device_id:
            return False, "Wrong device"
        signature = hashlib.sha256()
        with open(enc_path, 'rb') as f:
            signature.update(f.read())
        signature.update(key.encode())
        return (meta.get("signature") == signature.hexdigest()), "OK" if (meta.get("signature") == signature.hexdigest()) else "File modified"
    except:
        return False, "Corrupted"

def revoke_and_decrypt(filepath, keep_decrypted=False):
    if not filepath.endswith('.ckmenc'):
        return False, "Not encrypted"
    original_name = filepath.replace('.ckmenc', '')
    decrypted = decrypt_to_memory(filepath)
    if decrypted is None:
        return False, "Decryption failed"
    if keep_decrypted:
        with open(original_name, 'wb') as f:
            f.write(decrypted)
        os.chmod(original_name, 0o755)
    for path in [filepath + ".sig", filepath]:
        if os.path.exists(path):
            os.remove(path)
    return True, "Done"

def kill_process():
    global current_process, output_active, output_status
    if current_process and current_process.poll() is None:
        try:
            os.kill(current_process.pid, signal.SIGTERM)
            current_process.wait(timeout=2)
        except:
            os.kill(current_process.pid, signal.SIGKILL)
    current_process = None
    output_active = False
    output_status = "KILLED"
    return True

def copy_file(filepath):
    global clipboard
    clipboard = filepath
    return True

def paste_file(dest_dir):
    global clipboard
    if not clipboard or not os.path.exists(clipboard):
        return False, "Nothing copied"
    filename = os.path.basename(clipboard)
    dest_path = os.path.join(dest_dir, filename)
    counter = 1
    while os.path.exists(dest_path):
        name, ext = os.path.splitext(filename)
        dest_path = os.path.join(dest_dir, f"{name}_{counter}{ext}")
        counter += 1
    try:
        if os.path.isdir(clipboard):
            shutil.copytree(clipboard, dest_path)
        else:
            shutil.copy2(clipboard, dest_path)
        clipboard = None
        return True, f"Pasted: {filename}"
    except Exception as e:
        return False, str(e)

def ask_yes_no(stdscr, question):
    height, width = stdscr.getmaxyx()
    win = curses.newwin(5, len(question) + 4, height // 2 - 2, width // 2 - len(question) // 2 - 2)
    win.box()
    win.addstr(1, 2, question)
    win.addstr(3, 2, "[Y] Yes  [N] No")
    win.refresh()
    while True:
        key = stdscr.getch()
        if key in (ord('y'), ord('Y')):
            return True
        elif key in (ord('n'), ord('N')):
            return False

def show_help(stdscr):
    height, width = stdscr.getmaxyx()
    lines = [
        " CKM LAUNCHER v1.1 — HELP ",
        "===========================",
        " GREEN  = Safe / Verified (ENC)",
        " RED    = Danger / Broken (BRK)",
        " BLUE   = Folder (DIR)",
        " WHITE  = Unsigned file (RAW)",
        " YELLOW = Developer mode / Warnings",
        " ",
        " KEYBOARD SHORTCUTS:",
        " Enter   = Run / Open folder",
        " S       = Encrypt & Sign",
        " R       = Decrypt (with save dialog)",
        " C/V     = Copy / Paste",
        " Ctrl+P  = Kill running program",
        " Ctrl+H  = Parent directory",
        " TAB     = Dev mode (password: 1337)",
        " F1      = This help",
        " Q       = Quit",
        " ",
        " Press any key to close...",
    ]
    win = curses.newwin(len(lines) + 2, 60, 2, (width - 60) // 2)
    win.box()
    for i, line in enumerate(lines):
        try:
            win.addstr(i + 1, 2, line[:56])
        except:
            pass
    win.refresh()
    stdscr.getch()

def draw_ui(stdscr, files, current_row, scroll_offset, message, height, width):
    console_height = 8 if output_active else 0
    file_height = height - 8 - console_height
    
    title = "CKM LAUNCHER v1.1"
    stdscr.addstr(0, (width - len(title)) // 2, title, curses.A_BOLD)
    
    mode_text = "[DEVELOPER]" if DEBUG else "[STANDARD]"
    mode_color = curses.color_pair(3) if DEBUG else curses.color_pair(2)
    stdscr.addstr(1, (width - len(mode_text)) // 2, mode_text, mode_color | curses.A_BOLD)
    
    stdscr.addstr(2, 0, "=" * width, curses.color_pair(4))
    
    path_display = f" {CURRENT_PATH}"
    stdscr.addstr(3, 2, path_display[:width - 2], curses.color_pair(4))
    
    if clipboard:
        clip_name = os.path.basename(clipboard)
        stdscr.addstr(3, width - len(clip_name) - 3, f"[{clip_name}]", curses.color_pair(3))
    
    max_display = file_height - 5
    current_row = max(0, min(current_row, len(files) - 1))
    if current_row < scroll_offset:
        scroll_offset = current_row
    if current_row >= scroll_offset + max_display:
        scroll_offset = current_row - max_display + 1
    
    for i, f in enumerate(files[scroll_offset:scroll_offset + max_display]):
        y = 5 + i
        name = f['name']
        
        if f['is_dir']:
            prefix = "[DIR]"
            color = curses.color_pair(4)
        elif f['encrypted'] and f['signed'] and f['valid']:
            prefix = "[OK] "
            color = curses.color_pair(2)
        elif f['encrypted'] and (not f['signed'] or not f['valid']):
            prefix = "[ERR]"
            color = curses.color_pair(1)
        elif not f['encrypted']:
            if DEBUG:
                prefix = "[RAW]"
                color = curses.color_pair(3)
            else:
                prefix = "[   ]"
                color = curses.color_pair(2)
        else:
            prefix = "[???]"
            color = curses.color_pair(1)
        
        display_name = name.replace('.ckmenc', '')
        disp = f" {prefix} {display_name}"
        disp = disp.ljust(width - 4)[:width - 4]
        
        if i + scroll_offset == current_row:
            stdscr.addstr(y, 2, disp, curses.A_REVERSE)
        else:
            stdscr.addstr(y, 2, disp, color)
    
    hint_y = height - 3 - console_height
    hints = "ENTER:Run | S:Encrypt | R:Decrypt | C:Copy | V:Paste | Ctrl+P:Kill | Ctrl+H:Up | F1:Help | TAB:Mode | Q:Quit"
    stdscr.addstr(hint_y + 1, 2, hints[:width - 4], curses.A_REVERSE)
    
    if message:
        msg_color = curses.color_pair(1) if "FAIL" in message or "BROKEN" in message else curses.color_pair(2)
        stdscr.addstr(hint_y - 1, 2, message[:width - 4], msg_color)
    
    if output_active and console_height > 0:
        cs = height - console_height
        stdscr.addstr(cs, 0, "=" * width, curses.color_pair(1))
        sc = curses.color_pair(2) if "EXITED" in output_status else curses.color_pair(3)
        stdscr.addstr(cs + 1, 2, f" PROGRAM OUTPUT [{output_status}] (Ctrl+P to kill) ", sc | curses.A_BOLD)
        for i in range(min(len(output_lines), console_height - 3)):
            line = output_lines[-(min(len(output_lines), console_height - 3)) + i]
            line = line[:width - 4] if len(line) > width - 4 else line
            try:
                stdscr.addstr(cs + 2 + i, 2, line)
            except:
                pass

def load_files(path):
    files = []
    try:
        for item in sorted(os.listdir(path)):
            if item.endswith(('.tmp', '.sig', '.ckmsig')):
                continue
            fp = os.path.join(path, item)
            d = os.path.isdir(fp)
            e = item.endswith('.ckmenc')
            s = os.path.exists(fp + ".sig") if e else False
            v = verify_encrypted(fp, FACTORY_KEY)[0] if s else False
            files.append({'name': item, 'is_dir': d, 'encrypted': e, 'signed': s, 'valid': v})
    except:
        pass
    return files

def main(stdscr):
    global DEBUG, CURRENT_PATH, clipboard, output_active
    
    curses.curs_set(0)
    curses.init_pair(1, curses.COLOR_RED, curses.COLOR_BLACK)
    curses.init_pair(2, curses.COLOR_GREEN, curses.COLOR_BLACK)
    curses.init_pair(3, curses.COLOR_YELLOW, curses.COLOR_BLACK)
    curses.init_pair(4, curses.COLOR_BLUE, curses.COLOR_BLACK)
    curses.init_pair(5, curses.COLOR_WHITE, curses.COLOR_BLACK)
    
    cur_row, scr_off = 0, 0
    msg, msg_timer = "", 0
    
    while True:
        stdscr.clear()
        h, w = stdscr.getmaxyx()
        files = load_files(CURRENT_PATH)
        draw_ui(stdscr, files, cur_row, scr_off, msg, h, w)
        stdscr.refresh()
        
        if msg_timer > 0:
            curses.napms(100)
            msg_timer -= 1
            if msg_timer == 0:
                msg = ""
        
        key = stdscr.getch()
        
        if key == ord('q'):
            break
        elif key in (ord('j'), curses.KEY_DOWN):
            cur_row = min(cur_row + 1, len(files) - 1) if files else 0
        elif key in (ord('k'), curses.KEY_UP):
            cur_row = max(cur_row - 1, 0)
        elif key in (curses.KEY_BACKSPACE, 127, 8, 263):
            parent = os.path.dirname(CURRENT_PATH)
            if parent != CURRENT_PATH:
                CURRENT_PATH, cur_row, scr_off = parent, 0, 0
        elif key in (curses.KEY_F1, 265):
            show_help(stdscr)
        elif key in (ord('\n'), 10) and files:
            fi = files[cur_row]
            fp = os.path.join(CURRENT_PATH, fi['name'])
            if fi['is_dir']:
                CURRENT_PATH, cur_row, scr_off = fp, 0, 0
            elif fi['encrypted']:
                if DEBUG or (fi['signed'] and fi['valid']):
                    ok, txt = run_encrypted(fp, stdscr)
                    msg, msg_timer = (f"OK: {fi['name']}" if ok else f"ERR: {txt}"), 30
                else:
                    msg, msg_timer = "SECURITY ALERT: Signature broken!", 30
            else:
                msg, msg_timer = ("NOT ENCRYPTED! Press S to secure" if DEBUG else "LOCKED: Enable Dev Mode (TAB)"), 30
        elif key == 9:
            if not DEBUG:
                curses.echo()
                stdscr.addstr(h - 1, 2, "DEV PASSWORD: ")
                pw = stdscr.getstr(h - 1, 17, 20).decode('utf-8')
                curses.noecho()
                if pw == DEV_PASSWORD:
                    DEBUG, msg, msg_timer = True, "DEVELOPER MODE ENABLED", 20
                else:
                    msg, msg_timer = "ACCESS DENIED: Wrong password!", 20
            else:
                DEBUG, msg, msg_timer = False, "STANDARD MODE ENABLED", 20
        elif key in (ord('s'), ord('S')):
            if not DEBUG:
                msg, msg_timer = "DENIED: Enable Dev Mode first (TAB)", 20
            elif files and not files[cur_row]['is_dir'] and not files[cur_row]['encrypted']:
                fp = os.path.join(CURRENT_PATH, files[cur_row]['name'])
                if sign_and_encrypt(fp, FACTORY_KEY):
                    msg, msg_timer = f"SECURED: {files[cur_row]['name']}", 20
                    files = load_files(CURRENT_PATH)
        elif key in (ord('r'), ord('R')):
            if not DEBUG:
                msg, msg_timer = "DENIED: Enable Dev Mode first (TAB)", 20
            elif files and files[cur_row]['encrypted']:
                fp = os.path.join(CURRENT_PATH, files[cur_row]['name'])
                keep = ask_yes_no(stdscr, "Keep decrypted file after unlock?")
                revoke_and_decrypt(fp, keep)
                msg, msg_timer = f"UNLOCKED: {files[cur_row]['name']}", 20
                files = load_files(CURRENT_PATH)
        elif key in (ord('c'), ord('C')) and files:
            copy_file(os.path.join(CURRENT_PATH, files[cur_row]['name']))
            msg, msg_timer = f"COPIED: {files[cur_row]['name']}", 20
        elif key in (ord('v'), ord('V')):
            ok, txt = paste_file(CURRENT_PATH)
            msg, msg_timer = txt, 20
            files = load_files(CURRENT_PATH)
        elif key == 16:
            kill_process()
            msg, msg_timer = "PROCESS TERMINATED", 20

if __name__ == "__main__":
    curses.wrapper(main)
