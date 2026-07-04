#!/bin/bash
# ============================================================
# Wallpaper Cache - Universal Installer v2.3
# Supports: Niri, KDE Plasma, KDE Plasma Caelestia
# Now with automatic Bash aliases and Fish abbreviations
# ============================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Version
SCRIPT_VERSION="2.3"
APP_VERSION="7.9"

# Installation paths
INSTALL_DIR="$HOME/Downloads"
VENV_DIR="$HOME/wallpaper-cache-env"
CONFIG_DIR="$HOME/.config/wallpaper_cache"
AUTOSTART_DIR="$HOME/.config/autostart"
BIN_DIR="$HOME/.local/bin"
SERVICE_DIR="$HOME/.config/systemd/user"
NIRI_CONFIG="$HOME/.config/niri/config.kdl"
FISH_CONFIG="$HOME/.config/fish/config.fish"
BASH_CONFIG="$HOME/.bashrc"
BASH_ALIASES="$HOME/.bash_aliases"

# Colors for output
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "${CYAN}$1${NC}"; }
print_question() { echo -e "${MAGENTA}[?]${NC} $1"; }

# ============================================================
# Detection Functions
# ============================================================

detect_desktop() {
    # Check for Niri
    if pgrep -x "niri" > /dev/null 2>&1; then
        echo "niri"
        return
    fi
    
    # Check for KDE Plasma
    if [ -n "$XDG_CURRENT_DESKTOP" ]; then
        if [[ "$XDG_CURRENT_DESKTOP" == *"KDE"* ]] || [[ "$XDG_CURRENT_DESKTOP" == *"Plasma"* ]]; then
            # Check if Caelestia
            if [[ "$XDG_CURRENT_DESKTOP" == *"Caelestia"* ]] || [ -f "/usr/share/plasma/shells/org.kde.caelestia.desktop" ]; then
                echo "kde-caelestia"
            else
                echo "kde-plasma"
            fi
            return
        fi
    fi
    
    # Check for Caelestia via process
    if pgrep -f "caelestia" > /dev/null 2>&1; then
        echo "kde-caelestia"
        return
    fi
    
    # Check session type
    if [ -n "$DESKTOP_SESSION" ]; then
        if [[ "$DESKTOP_SESSION" == *"caelestia"* ]]; then
            echo "kde-caelestia"
            return
        elif [[ "$DESKTOP_SESSION" == *"plasma"* ]]; then
            echo "kde-plasma"
            return
        fi
    fi
    
    # Check Wayland display
    if [ -n "$WAYLAND_DISPLAY" ]; then
        if pgrep -f "plasmashell" > /dev/null 2>&1; then
            echo "kde-plasma"
            return
        fi
    fi
    
    echo "unknown"
}

detect_shell() {
    local shell_name=""
    
    # Check current shell
    if [ -n "$SHELL" ]; then
        shell_name=$(basename "$SHELL")
    fi
    
    # Check if running in fish
    if [ -n "$FISH_VERSION" ] || [[ "$shell_name" == "fish" ]]; then
        echo "fish"
        return
    fi
    
    # Check if running in bash
    if [ -n "$BASH_VERSION" ] || [[ "$shell_name" == "bash" ]]; then
        echo "bash"
        return
    fi
    
    # Check parent process
    local parent_process=$(ps -p $PPID -o comm= 2>/dev/null | xargs basename 2>/dev/null)
    if [[ "$parent_process" == "fish" ]]; then
        echo "fish"
        return
    elif [[ "$parent_process" == "bash" ]]; then
        echo "bash"
        return
    fi
    
    # Default to bash
    echo "bash"
}

get_display_number() {
    if [ -n "$DISPLAY" ]; then
        echo "$DISPLAY"
    elif [ -n "$WAYLAND_DISPLAY" ]; then
        echo ":1"
    else
        echo ":0"
    fi
}

# ============================================================
# Installation Functions
# ============================================================

install_dependencies() {
    print_info "Installing system dependencies..."
    
    # Check if pacman is available (Arch Linux)
    if command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm --needed \
            tk \
            python-pip \
            python-virtualenv \
            desktop-file-utils \
            xorg-xwayland \
            || print_warning "Some packages may already be installed"
    else
        print_warning "pacman not found. Please install dependencies manually:"
        echo "  - tk"
        echo "  - python-pip"
        echo "  - python-virtualenv"
        echo "  - desktop-file-utils"
        echo "  - xorg-xwayland"
    fi
    
    print_success "System dependencies installed"
}

create_directories() {
    print_info "Creating directories..."
    
    # Create all required directories
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$VENV_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$AUTOSTART_DIR"
    mkdir -p "$BIN_DIR"
    mkdir -p "$SERVICE_DIR"
    mkdir -p "$(dirname "$FISH_CONFIG")"
    mkdir -p "$HOME/Pictures/WallpaperCache"
    
    print_success "Directories created"
}

create_virtual_env() {
    print_info "Creating Python virtual environment..."
    
    if [ -d "$VENV_DIR" ]; then
        print_warning "Virtual environment already exists, removing..."
        rm -rf "$VENV_DIR"
    fi
    
    python -m venv "$VENV_DIR"
    source "$VENV_DIR/bin/activate"
    print_success "Virtual environment created"
}

install_python_packages() {
    print_info "Installing Python dependencies..."
    
    source "$VENV_DIR/bin/activate"
    pip install --upgrade pip --quiet
    pip install requests beautifulsoup4 customtkinter pillow cryptography schedule pystray imagehash --quiet
    deactivate
    
    print_success "Python dependencies installed"
}

create_script() {
    print_info "Creating Wallpaper Cache script..."
    
    cat > "$INSTALL_DIR/wallpaper_cache.py" << 'EOF'
#!/usr/bin/env python3
# Wallpaper Cache - Niri Downloader v7.9
import os
# Use system display - don't hardcode
# os.environ["DISPLAY"] = ":0"  # Let system handle it
os.environ["QT_QPA_PLATFORM"] = "xcb"
os.environ["GDK_BACKEND"] = "x11"
os.environ["CLUTTER_BACKEND"] = "x11"

"""
Wallpaper Cache - Niri Downloader v7.9
Complete version with all 8 tabs and multi-page search
"""

import re
import json
import sqlite3
import threading
import argparse
import sys
import subprocess
import time
import hashlib
import io
import shutil
import atexit
import signal
from pathlib import Path
from datetime import datetime
from tkinter import filedialog, messagebox, Listbox
from typing import List, Dict, Optional, Tuple, Set, Any
from contextlib import contextmanager
import logging
from logging.handlers import RotatingFileHandler
from concurrent.futures import ThreadPoolExecutor, as_completed, TimeoutError
from queue import Queue, Empty
import weakref

import requests
from bs4 import BeautifulSoup
import customtkinter as ctk
from PIL import Image
from cryptography.fernet import Fernet
import schedule

# ----------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------
APP_NAME = "Wallpaper Cache"
VERSION = "7.9"
DEFAULT_DOWNLOAD_DIR = str(Path.home() / "Pictures" / "WallpaperCache")
CONFIG_DIR = Path.home() / ".config" / "wallpaper_cache"
CONFIG_DIR.mkdir(parents=True, exist_ok=True)

THUMB_CACHE_DIR = CONFIG_DIR / "thumb_cache"
THUMB_CACHE_DIR.mkdir(exist_ok=True)

KEYS_FILE = CONFIG_DIR / "api_keys.json"
KEY_FILE = CONFIG_DIR / ".secret.key"
DB_FILE = CONFIG_DIR / "history.db"
KEYWORDS_FILE = CONFIG_DIR / "keywords.json"
SETTINGS_FILE = CONFIG_DIR / "settings.json"
COLLECTIONS_FILE = CONFIG_DIR / "collections.json"
QUEUE_DB_FILE = CONFIG_DIR / "queue.db"

# Logging
log_handler = RotatingFileHandler(CONFIG_DIR / "app.log", maxBytes=5*1024*1024, backupCount=3)
log_handler.setFormatter(logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s'))
logging.basicConfig(level=logging.INFO, handlers=[log_handler, logging.StreamHandler()])
logger = logging.getLogger(__name__)

ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("dark-blue")

# Global flag for graceful shutdown
SHUTDOWN_FLAG = threading.Event()

def signal_handler(signum, frame):
    """Handle shutdown signals gracefully"""
    logger.info(f"Received signal {signum}, shutting down...")
    SHUTDOWN_FLAG.set()

# Register signal handlers
signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

# ----------------------------------------------------------------------
# Database helpers with connection pooling
# ----------------------------------------------------------------------
class DatabasePool:
    """Simple connection pool for SQLite to prevent connection leaks"""
    def __init__(self, db_path, max_connections=5):
        self.db_path = db_path
        self.max_connections = max_connections
        self._connections = []
        self._lock = threading.Lock()
        
    @contextmanager
    def get_connection(self):
        conn = None
        with self._lock:
            if self._connections:
                conn = self._connections.pop()
            else:
                conn = sqlite3.connect(self.db_path, timeout=10)
                conn.execute("PRAGMA journal_mode=WAL")
                conn.execute("PRAGMA synchronous=NORMAL")
        
        try:
            yield conn
            conn.commit()
        except Exception as e:
            conn.rollback()
            logger.error(f"Database error: {e}")
            raise
        finally:
            with self._lock:
                if len(self._connections) < self.max_connections:
                    self._connections.append(conn)
                else:
                    conn.close()
    
    def close_all(self):
        with self._lock:
            for conn in self._connections:
                try:
                    conn.close()
                except:
                    pass
            self._connections.clear()

# Initialize database pool
db_pool = DatabasePool(DB_FILE)

@contextmanager
def get_db_connection():
    """Context manager for database connections using the pool"""
    with db_pool.get_connection() as conn:
        yield conn

def init_db():
    """Initialize database schema if it doesn't exist"""
    with get_db_connection() as conn:
        c = conn.cursor()
        c.execute('''CREATE TABLE IF NOT EXISTS downloads
                     (id INTEGER PRIMARY KEY AUTOINCREMENT,
                      filename TEXT, filepath TEXT, source_url TEXT,
                      source_name TEXT, resolution TEXT, file_size INTEGER,
                      download_date TEXT, file_hash TEXT, collection_name TEXT)''')
        c.execute('''CREATE TABLE IF NOT EXISTS keywords
                     (keyword TEXT PRIMARY KEY, count INTEGER DEFAULT 1, last_used TEXT, last_page INTEGER DEFAULT 1)''')
        c.execute('''CREATE INDEX IF NOT EXISTS idx_downloads_url ON downloads(source_url)''')
        c.execute('''CREATE INDEX IF NOT EXISTS idx_downloads_date ON downloads(download_date)''')
        c.execute('''CREATE INDEX IF NOT EXISTS idx_keywords_name ON keywords(keyword)''')

init_db()

def get_downloaded_urls() -> Set[str]:
    with get_db_connection() as conn:
        c = conn.cursor()
        c.execute('SELECT source_url FROM downloads')
        return {row[0] for row in c.fetchall()}

def get_keyword_last_page(keyword: str) -> int:
    with get_db_connection() as conn:
        c = conn.cursor()
        c.execute('SELECT last_page FROM keywords WHERE keyword = ?', (keyword,))
        row = c.fetchone()
        return row[0] if row else 1

def update_keyword_last_page(keyword: str, page: int):
    with get_db_connection() as conn:
        c = conn.cursor()
        c.execute('''INSERT INTO keywords (keyword, count, last_used, last_page) 
                     VALUES (?, 1, ?, ?) 
                     ON CONFLICT(keyword) DO UPDATE SET 
                     count = count + 1, last_used = ?, last_page = ?''',
                  (keyword, datetime.now().isoformat(), page, datetime.now().isoformat(), page))

def add_download_record(filename, filepath, source_url, source_name, file_size, file_hash):
    with get_db_connection() as conn:
        c = conn.cursor()
        c.execute('INSERT INTO downloads (filename, filepath, source_url, source_name, file_size, download_date, file_hash) VALUES (?,?,?,?,?,?,?)',
                  (filename, str(filepath), source_url, source_name, file_size, datetime.now().isoformat(), file_hash))

def get_recent_downloads(limit=100):
    with get_db_connection() as conn:
        c = conn.cursor()
        c.execute("SELECT filename, source_name, download_date, file_size FROM downloads ORDER BY download_date DESC LIMIT ?", (limit,))
        return c.fetchall()

# ----------------------------------------------------------------------
# Persistent Queue with better error handling
# ----------------------------------------------------------------------
def init_queue_db():
    conn = sqlite3.connect(QUEUE_DB_FILE)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        url TEXT UNIQUE,
        filename TEXT,
        title TEXT,
        collection TEXT,
        added TIMESTAMP,
        retries INTEGER DEFAULT 0,
        status TEXT DEFAULT 'pending'
    )''')
    c.execute('''CREATE INDEX IF NOT EXISTS idx_queue_status ON queue(status)''')
    c.execute('''CREATE INDEX IF NOT EXISTS idx_queue_url ON queue(url)''')
    conn.commit()
    conn.close()

init_queue_db()

def add_to_persistent_queue(url, filename, title=None, collection=None):
    conn = sqlite3.connect(QUEUE_DB_FILE)
    try:
        c = conn.cursor()
        c.execute('INSERT OR IGNORE INTO queue (url, filename, title, collection, added, status) VALUES (?,?,?,?,?,?)',
                  (url, filename, title, collection, datetime.now().isoformat(), 'pending'))
        conn.commit()
    except Exception as e:
        logger.error(f"Error adding to persistent queue: {e}")
    finally:
        conn.close()

def remove_from_persistent_queue(url):
    conn = sqlite3.connect(QUEUE_DB_FILE)
    try:
        c = conn.cursor()
        c.execute('DELETE FROM queue WHERE url = ?', (url,))
        conn.commit()
    except Exception as e:
        logger.error(f"Error removing from persistent queue: {e}")
    finally:
        conn.close()

def load_persistent_queue():
    conn = sqlite3.connect(QUEUE_DB_FILE)
    try:
        c = conn.cursor()
        c.execute('SELECT url, filename, title, collection, retries FROM queue WHERE status = "pending" ORDER BY added')
        return c.fetchall()
    except Exception as e:
        logger.error(f"Error loading persistent queue: {e}")
        return []
    finally:
        conn.close()

def clear_persistent_queue():
    conn = sqlite3.connect(QUEUE_DB_FILE)
    try:
        c = conn.cursor()
        c.execute('DELETE FROM queue')
        conn.commit()
    except Exception as e:
        logger.error(f"Error clearing persistent queue: {e}")
    finally:
        conn.close()

# ----------------------------------------------------------------------
# Disk space management
# ----------------------------------------------------------------------
def get_free_space_gb(path):
    try:
        stat = shutil.disk_usage(path)
        return stat.free / (1024**3)
    except:
        return -1

def get_folder_size_gb(path):
    total = 0
    try:
        for entry in Path(path).rglob('*'):
            if entry.is_file():
                total += entry.stat().st_size
    except Exception as e:
        logger.error(f"Error calculating folder size: {e}")
    return total / (1024**3)

def delete_oldest_downloads(download_dir, target_size_gb):
    files = []
    for ext in ['*.jpg', '*.jpeg', '*.png', '*.gif', '*.mp4']:
        files.extend(Path(download_dir).rglob(ext))
    files.sort(key=lambda f: f.stat().st_mtime)
    total_gb = get_folder_size_gb(download_dir)
    deleted = []
    while total_gb > target_size_gb and files:
        oldest = files.pop(0)
        size_gb = oldest.stat().st_size / (1024**3)
        try:
            oldest.unlink()
            deleted.append(oldest.name)
            total_gb -= size_gb
            with get_db_connection() as conn:
                c = conn.cursor()
                c.execute("DELETE FROM downloads WHERE filepath = ?", (str(oldest),))
        except Exception as e:
            logger.error(f"Error deleting file {oldest}: {e}")
    return deleted, total_gb

# ----------------------------------------------------------------------
# Settings
# ----------------------------------------------------------------------
def load_settings():
    default = {
        "auto_download_on_startup": True,
        "startup_keywords": ["nature", "city", "cyberpunk", "space", "abstract"],
        "startup_limit_per_keyword": 10,
        "startup_source": "Wallhaven",
        "org_mode": "detailed",
        "max_concurrent": 3,
        "rate_limit_delay": 1.0,
        "minimize_to_tray": True,
        "show_notifications": True,
        "download_dir": DEFAULT_DOWNLOAD_DIR,
        "theme": "Dark",
        "disk_limit_gb": 10,
        "auto_clean_on_startup": False,
        "max_search_pages": 5
    }
    if SETTINGS_FILE.exists():
        try:
            with open(SETTINGS_FILE, 'r') as f:
                saved = json.load(f)
                default.update(saved)
        except Exception as e:
            logger.error(f"Error loading settings: {e}")
    return default

def save_settings(settings):
    try:
        with open(SETTINGS_FILE, 'w') as f:
            json.dump(settings, f, indent=2)
    except Exception as e:
        logger.error(f"Error saving settings: {e}")

# ----------------------------------------------------------------------
# Keywords, Collections, API Keys
# ----------------------------------------------------------------------
def load_keywords():
    if KEYWORDS_FILE.exists():
        try:
            with open(KEYWORDS_FILE, 'r') as f:
                return json.load(f)
        except:
            return {"last_used": [], "favorites": []}
    return {"last_used": [], "favorites": []}

def save_keywords(keywords_dict):
    try:
        with open(KEYWORDS_FILE, 'w') as f:
            json.dump(keywords_dict, f, indent=2)
    except Exception as e:
        logger.error(f"Error saving keywords: {e}")

def load_collections():
    if COLLECTIONS_FILE.exists():
        try:
            with open(COLLECTIONS_FILE, 'r') as f:
                return json.load(f)
        except:
            return {}
    return {}

def save_collections(collections):
    try:
        with open(COLLECTIONS_FILE, 'w') as f:
            json.dump(collections, f, indent=2)
    except Exception as e:
        logger.error(f"Error saving collections: {e}")

def get_or_create_key():
    if KEY_FILE.exists():
        with open(KEY_FILE, 'rb') as f:
            return f.read()
    else:
        key = Fernet.generate_key()
        with open(KEY_FILE, 'wb') as f:
            f.write(key)
        return key

def encrypt_api_keys(keys_dict):
    cipher = Fernet(get_or_create_key())
    return cipher.encrypt(json.dumps(keys_dict).encode())

def decrypt_api_keys(encrypted_data):
    try:
        cipher = Fernet(get_or_create_key())
        return json.loads(cipher.decrypt(encrypted_data).decode())
    except:
        return {}

def load_api_keys():
    if KEYS_FILE.exists():
        try:
            with open(KEYS_FILE, 'rb') as f:
                return decrypt_api_keys(f.read())
        except:
            return {}
    return {}

def save_api_keys(keys_dict):
    try:
        with open(KEYS_FILE, 'wb') as f:
            f.write(encrypt_api_keys(keys_dict))
    except Exception as e:
        logger.error(f"Error saving API keys: {e}")

# ----------------------------------------------------------------------
# Main Application
# ----------------------------------------------------------------------
class WallpaperCacheApp(ctk.CTk):
    def __init__(self):
        super().__init__()
        self.title(f"{APP_NAME} v{VERSION}")
        self.geometry("1200x850")
        self.minsize(1000, 750)

        self.settings = load_settings()
        self.download_dir = self.settings.get("download_dir", DEFAULT_DOWNLOAD_DIR)
        os.makedirs(self.download_dir, exist_ok=True)

        self.keywords_data = load_keywords()
        self.collections = load_collections()
        self.api_keys = load_api_keys()

        self.download_queue = []
        self.active_downloads = 0
        self.max_concurrent = self.settings.get("max_concurrent", 3)
        self.queue_lock = threading.RLock()  # Reentrant lock for better safety
        self.current_results = []
        self.result_widgets = []
        self.api_entries = {}
        self.thumbnail_cache = {}  # In-memory cache for thumbnails
        self.downloaded_urls = get_downloaded_urls()
        
        # Thread pool for managing concurrent operations
        self.executor = ThreadPoolExecutor(max_workers=5, thread_name_prefix="WPC")
        
        # Queue for background tasks
        self.task_queue = Queue()
        self.running_tasks = set()
        self.task_lock = threading.Lock()
        
        # Register cleanup on exit
        atexit.register(self.cleanup)
        
        # Flag for shutdown
        self._shutting_down = False
        
        self._create_widgets()
        
        self.protocol("WM_DELETE_WINDOW", self.on_closing)
        
        self.after(100, self._restore_persistent_queue)
        self.after(1000, self._process_queue)
        self.after(3600000, self._check_disk_space)
        
        # Start background task processor
        self.after(100, self._process_task_queue)

        if self.settings.get("auto_download_on_startup", True):
            self.after(3000, self.run_startup_download)

    def cleanup(self):
        """Clean up resources on exit"""
        if self._shutting_down:
            return
        self._shutting_down = True
        logger.info("Cleaning up resources...")
        
        # Close database connections
        db_pool.close_all()
        
        # Shutdown thread pool
        if hasattr(self, 'executor'):
            self.executor.shutdown(wait=False, cancel_futures=True)
        
        # Clear caches
        self.thumbnail_cache.clear()
        
        logger.info("Cleanup complete")

    def on_closing(self):
        if self.settings.get("minimize_to_tray", True):
            self.withdraw()
        else:
            self.quit()
            self.cleanup()

    def _send_notification(self, title, message, urgency="normal"):
        if self.settings.get("show_notifications", True):
            try:
                subprocess.run(['notify-send', title, message, '-t', '3000', '-u', urgency], check=False)
            except:
                pass

    def _restore_persistent_queue(self):
        try:
            pending = load_persistent_queue()
            with self.queue_lock:
                for url, filename, title, collection, retries in pending:
                    if not any(item.get('url') == url for item in self.download_queue):
                        self.download_queue.append({
                            'url': url, 'filename': filename, 'title': title,
                            'retries': retries, 'status': 'pending'
                        })
            if pending:
                self.status_var.set(f"📋 Restored {len(pending)} pending downloads")
                self._refresh_queue_display()
        except Exception as e:
            logger.error(f"Error restoring queue: {e}")

    def _check_disk_space(self):
        try:
            free = get_free_space_gb(self.download_dir)
            if 0 < free < 1.0:
                self.status_var.set(f"⚠️ Low disk space: {free:.1f} GB remaining")
                self._send_notification("Low Disk Space", f"Only {free:.1f} GB left", "critical")
        except Exception as e:
            logger.error(f"Error checking disk space: {e}")
        self.after(3600000, self._check_disk_space)

    def _create_widgets(self):
        header = ctk.CTkLabel(self, text=f"🎬 {APP_NAME}", font=ctk.CTkFont(size=28, weight="bold"))
        header.pack(pady=(15,5))

        sub = ctk.CTkLabel(self, text="Search | Collections | Keywords | API Keys | History | Queue | Scheduler | Settings",
                          font=ctk.CTkFont(size=12))
        sub.pack(pady=(0,15))

        self.tabview = ctk.CTkTabview(self, width=1100, height=620)
        self.tabview.pack(fill="both", expand=True, padx=20, pady=(0,10))

        self.tabview.add("Search")
        self.tabview.add("Collections")
        self.tabview.add("Keywords")
        self.tabview.add("API Keys")
        self.tabview.add("History")
        self.tabview.add("Queue")
        self.tabview.add("Scheduler")
        self.tabview.add("Settings")

        self._setup_search_tab()
        self._setup_collections_tab()
        self._setup_keywords_tab()
        self._setup_api_keys_tab()
        self._setup_history_tab()
        self._setup_queue_tab()
        self._setup_scheduler_tab()
        self._setup_settings_tab()

        self.status_var = ctk.StringVar(value="✅ Ready")
        self.status_bar = ctk.CTkLabel(self, textvariable=self.status_var, anchor="w", font=ctk.CTkFont(size=11))
        self.status_bar.pack(fill="x", padx=20, pady=(0,10))

        self.progress_bar = ctk.CTkProgressBar(self, width=1060, height=8)
        self.progress_bar.pack(padx=20, pady=(0,5))
        self.progress_bar.set(0)

        dir_frame = ctk.CTkFrame(self)
        dir_frame.pack(fill="x", padx=20, pady=(0,10))
        self.dir_label = ctk.CTkLabel(dir_frame, text=f"📁 Download folder: {self.download_dir}", anchor="w")
        self.dir_label.pack(side="left", fill="x", expand=True)
        ctk.CTkButton(dir_frame, text="Change Folder", command=self._change_dir, width=120).pack(side="right", padx=(0,10))
        ctk.CTkButton(dir_frame, text="Open Folder", command=self._open_folder, width=120).pack(side="right")

    def _setup_search_tab(self):
        tab = self.tabview.tab("Search")
        top_frame = ctk.CTkFrame(tab)
        top_frame.pack(fill="x", padx=10, pady=10)

        ctk.CTkLabel(top_frame, text="Source:").pack(side="left", padx=5)
        self.source_combo = ctk.CTkComboBox(top_frame, values=["Wallhaven", "Reddit", "MoeWalls"], width=120)
        self.source_combo.set("Wallhaven")
        self.source_combo.pack(side="left", padx=5)

        self.search_entry = ctk.CTkEntry(top_frame, placeholder_text="Search keywords...", width=400)
        self.search_entry.pack(side="left", padx=10, fill="x", expand=True)
        self.search_entry.bind("<Return>", lambda e: self._perform_search())
        self.search_btn = ctk.CTkButton(top_frame, text="🔍 Search", command=self._perform_search, width=100)
        self.search_btn.pack(side="left", padx=5)

        select_frame = ctk.CTkFrame(tab)
        select_frame.pack(fill="x", padx=10, pady=5)
        self.select_all_var = ctk.BooleanVar()
        self.select_all_cb = ctk.CTkCheckBox(select_frame, text="Select All", variable=self.select_all_var, command=self._toggle_select_all)
        self.select_all_cb.pack(side="left", padx=5)
        self.download_selected_btn = ctk.CTkButton(select_frame, text="⬇ Download Selected (0)", command=self._download_selected, fg_color="green", width=200)
        self.download_selected_btn.pack(side="left", padx=10)

        self.results_frame = ctk.CTkScrollableFrame(tab, label_text="Results")
        self.results_frame.pack(fill="both", expand=True, padx=10, pady=5)

    def _perform_search(self, retries=3):
        query = self.search_entry.get().strip()
        if not query:
            messagebox.showwarning("Empty", "Enter search keywords")
            return
        
        self.status_var.set(f"🔍 Searching for '{query}'...")
        self.search_btn.configure(state="disabled")

        # Clear old results
        for widget in self.results_frame.winfo_children():
            widget.destroy()
        self.current_results.clear()
        self.select_all_var.set(False)
        self.download_selected_btn.configure(text="⬇ Download Selected (0)")

        # Submit search task
        future = self.executor.submit(self._fetch_results, query, retries)
        with self.task_lock:
            self.running_tasks.add(future)

    def _fetch_results(self, query, retries=3):
        for attempt in range(retries):
            if SHUTDOWN_FLAG.is_set() or self._shutting_down:
                return
            
            try:
                params = {"q": query, "categories": "111", "purity": "100", "sorting": "relevance", "page": 1}
                
                # Add API key if available
                if 'wallhaven_api' in self.api_keys and self.api_keys['wallhaven_api']:
                    params["apikey"] = self.api_keys['wallhaven_api']
                
                resp = requests.get("https://wallhaven.cc/api/v1/search", params=params, timeout=30)
                resp.raise_for_status()
                data = resp.json()
                items = data.get("data", [])[:30]
                
                for i, item in enumerate(items):
                    if SHUTDOWN_FLAG.is_set():
                        return
                    title = item.get("title", f"WH_{item['id']}")
                    img_url = item.get("path")
                    thumb_url = item.get("thumbs", {}).get("large", img_url)
                    resolution = item.get('resolution', 'unknown')
                    self.after(0, self._add_result_item, i, title, img_url, thumb_url, resolution)
                
                self.after(0, lambda: self.status_var.set(f"✅ Found {len(items)} results"))
                return  # Success
                
            except requests.exceptions.RequestException as e:
                logger.error(f"Search attempt {attempt+1} failed: {e}")
                if attempt == retries - 1:
                    self.after(0, lambda: self._show_error(f"Search failed after {retries} attempts: {str(e)}"))
                else:
                    time.sleep(2 ** attempt)  # Exponential backoff
            except Exception as e:
                logger.error(f"Unexpected error in search: {e}")
                self.after(0, lambda: self._show_error(f"Search failed: {str(e)}"))
                break
            finally:
                if attempt == retries - 1:
                    self.after(0, lambda: self.search_btn.configure(state="normal"))
                    
        # Clean up task reference
        with self.task_lock:
            self.running_tasks.discard(threading.current_thread())

    def _add_result_item(self, index, title, url, thumb_url, resolution):
        frame = ctk.CTkFrame(self.results_frame)
        frame.pack(fill="x", padx=5, pady=3)

        var = ctk.BooleanVar()
        cb = ctk.CTkCheckBox(frame, variable=var, text="", width=30)
        cb.pack(side="left", padx=5)

        is_downloaded = url in self.downloaded_urls

        thumb_label = ctk.CTkLabel(frame, text="🖼️", width=100, height=70, fg_color="gray20", corner_radius=5)
        thumb_label.pack(side="left", padx=5, pady=5)
        
        # Use thread pool for thumbnail loading
        self.executor.submit(self._load_thumb, thumb_url, thumb_label)

        info_frame = ctk.CTkFrame(frame, fg_color="transparent")
        info_frame.pack(side="left", fill="x", expand=True, padx=10)
        title_label = ctk.CTkLabel(info_frame, text=title[:70], anchor="w", wraplength=400)
        title_label.pack(anchor="w")

        status_text = "✅ Already Downloaded" if is_downloaded else "📥 New"
        status_color = "green" if is_downloaded else "blue"
        status_label = ctk.CTkLabel(info_frame, text=status_text, font=ctk.CTkFont(size=10), fg_color=status_color, corner_radius=3)
        status_label.pack(anchor="w", pady=(2,0))

        res_badge = ctk.CTkLabel(info_frame, text=f"📐 {resolution}", font=ctk.CTkFont(size=10), fg_color="gray20", corner_radius=3)
        res_badge.pack(anchor="w", pady=(2,0))

        download_btn = ctk.CTkButton(frame, text="⬇ Download" if not is_downloaded else "✅ Done", 
                                     width=100,
                                     fg_color="green" if not is_downloaded else "gray",
                                     state="normal" if not is_downloaded else "disabled",
                                     command=lambda u=url, t=title: self._download_single(u, t))
        download_btn.pack(side="right", padx=5)

        self.current_results.append({
            "title": title, "url": url, "var": var,
            "resolution": resolution, "frame": frame, "download_btn": download_btn,
            "is_downloaded": is_downloaded
        })
        self._update_selected_count()

    def _load_thumb(self, url, label):
        cache_key = hashlib.md5(url.encode()).hexdigest()
        cache_path = THUMB_CACHE_DIR / f"{cache_key}.jpg"
        
        # Check in-memory cache first
        if cache_key in self.thumbnail_cache:
            try:
                img = self.thumbnail_cache[cache_key]
                ctk_img = ctk.CTkImage(light_image=img, dark_image=img, size=(100,70))
                label.configure(image=ctk_img, text="")
                label.image = ctk_img
                return
            except:
                pass
        
        # Check disk cache
        if cache_path.exists():
            try:
                img = Image.open(cache_path)
                img.thumbnail((100,70), Image.Resampling.LANCZOS)
                self.thumbnail_cache[cache_key] = img
                ctk_img = ctk.CTkImage(light_image=img, dark_image=img, size=(100,70))
                label.configure(image=ctk_img, text="")
                label.image = ctk_img
                return
            except:
                pass
                
        try:
            resp = requests.get(url, timeout=10)
            resp.raise_for_status()
            img = Image.open(io.BytesIO(resp.content))
            img.thumbnail((100,70), Image.Resampling.LANCZOS)
            img.save(cache_path, "JPEG", quality=85)
            self.thumbnail_cache[cache_key] = img
            ctk_img = ctk.CTkImage(light_image=img, dark_image=img, size=(100,70))
            label.configure(image=ctk_img, text="")
            label.image = ctk_img
        except Exception as e:
            logger.error(f"Thumbnail load error: {e}")
            label.configure(text="🖼️")

    def _update_selected_count(self):
        count = sum(1 for res in self.current_results if res["var"].get() and not res["is_downloaded"])
        self.download_selected_btn.configure(text=f"⬇ Download Selected ({count})")

    def _toggle_select_all(self):
        select = self.select_all_var.get()
        for res in self.current_results:
            if not res["is_downloaded"]:
                res["var"].set(select)
        self._update_selected_count()

    def _download_single(self, url, title):
        if url in self.downloaded_urls:
            self.status_var.set(f"⏭️ Already downloaded: {title[:50]}")
            return
        filename = self._sanitize_filename(f"{title}.jpg")
        add_to_persistent_queue(url, filename, title, None)
        with self.queue_lock:
            self.download_queue.append({'url': url, 'filename': filename, 'title': title, 'retries': 0, 'status': 'pending'})
        self.status_var.set(f"📋 Added to queue: {title[:50]}")
        self._send_notification("Added to Queue", title[:50])
        self._refresh_queue_display()
        self.downloaded_urls.add(url)

    def _download_selected(self):
        selected = [res for res in self.current_results if res["var"].get() and not res["is_downloaded"]]
        if not selected:
            messagebox.showinfo("No selection", "No new wallpapers selected.")
            return
        for res in selected:
            self._download_single(res['url'], res['title'])
        self.status_var.set(f"📋 Added {len(selected)} items to queue")

    # ------------------------------------------------------------------
    # Collections Tab
    # ------------------------------------------------------------------
    def _setup_collections_tab(self):
        tab = self.tabview.tab("Collections")
        add_frame = ctk.CTkFrame(tab)
        add_frame.pack(fill="x", padx=10, pady=10)

        ctk.CTkLabel(add_frame, text="Name:").pack(side="left", padx=5)
        self.collection_name_entry = ctk.CTkEntry(add_frame, placeholder_text="e.g., Cyberpunk", width=150)
        self.collection_name_entry.pack(side="left", padx=5)

        ctk.CTkLabel(add_frame, text="Keywords (comma):").pack(side="left", padx=5)
        self.collection_keywords_entry = ctk.CTkEntry(add_frame, placeholder_text="cyberpunk, neon, future", width=200)
        self.collection_keywords_entry.pack(side="left", padx=5)

        ctk.CTkLabel(add_frame, text="Source:").pack(side="left", padx=5)
        self.collection_source_combo = ctk.CTkComboBox(add_frame, values=["Wallhaven", "Reddit", "MoeWalls"], width=100)
        self.collection_source_combo.set("Wallhaven")
        self.collection_source_combo.pack(side="left", padx=5)

        ctk.CTkLabel(add_frame, text="Limit:").pack(side="left", padx=5)
        self.collection_limit_entry = ctk.CTkEntry(add_frame, placeholder_text="10", width=60)
        self.collection_limit_entry.insert(0, "10")
        self.collection_limit_entry.pack(side="left", padx=5)

        ctk.CTkButton(add_frame, text="➕ Add Collection", command=self._add_collection).pack(side="left", padx=10)

        self.collections_list_frame = ctk.CTkScrollableFrame(tab, label_text="Saved Collections")
        self.collections_list_frame.pack(fill="both", expand=True, padx=10, pady=10)
        self._refresh_collections_list()

    def _add_collection(self):
        name = self.collection_name_entry.get().strip()
        keywords_str = self.collection_keywords_entry.get().strip()
        source = self.collection_source_combo.get()
        limit = self.collection_limit_entry.get().strip()

        if not name or not keywords_str:
            messagebox.showwarning("Incomplete", "Name and keywords required")
            return

        keywords = [k.strip() for k in keywords_str.split(',') if k.strip()]
        if not keywords:
            messagebox.showwarning("Invalid", "At least one keyword required")
            return
            
        self.collections[name] = {
            "keywords": keywords,
            "source": source,
            "limit": int(limit) if limit.isdigit() else 10
        }
        save_collections(self.collections)
        self._refresh_collections_list()
        self.collection_name_entry.delete(0, 'end')
        self.collection_keywords_entry.delete(0, 'end')
        self.status_var.set(f"✅ Collection '{name}' added")

    def _refresh_collections_list(self):
        for widget in self.collections_list_frame.winfo_children():
            widget.destroy()
            
        for name, data in self.collections.items():
            frame = ctk.CTkFrame(self.collections_list_frame)
            frame.pack(fill="x", padx=5, pady=2)
            
            label = ctk.CTkLabel(frame, 
                               text=f"{name} | {data['source']} | {', '.join(data['keywords'])} | limit {data['limit']}", 
                               anchor="w")
            label.pack(side="left", fill="x", expand=True, padx=10)
            
            # Use lambda with default argument to capture the current name
            ctk.CTkButton(frame, text="🗑️", width=50, 
                         command=lambda n=name: self._delete_collection(n)).pack(side="right", padx=5)
            ctk.CTkButton(frame, text="⬇ Download", width=100, 
                         command=lambda n=name: self._download_collection_now(n)).pack(side="right", padx=5)

    def _delete_collection(self, name):
        if messagebox.askyesno("Confirm", f"Delete collection '{name}'?"):
            del self.collections[name]
            save_collections(self.collections)
            self._refresh_collections_list()
            self.status_var.set(f"🗑️ Collection '{name}' deleted")

    def _download_collection_now(self, name):
        data = self.collections.get(name)
        if not data:
            return
        for kw in data["keywords"]:
            self.executor.submit(self._download_keyword, kw, data["limit"])

    # ------------------------------------------------------------------
    # Keywords Tab
    # ------------------------------------------------------------------
    def _setup_keywords_tab(self):
        tab = self.tabview.tab("Keywords")
        add_frame = ctk.CTkFrame(tab)
        add_frame.pack(fill="x", padx=10, pady=10)
        self.new_keyword_entry = ctk.CTkEntry(add_frame, placeholder_text="New keyword")
        self.new_keyword_entry.pack(side="left", fill="x", expand=True, padx=(0,10))
        ctk.CTkButton(add_frame, text="➕ Add Keyword", command=self._add_keyword).pack(side="right")

        self.keywords_list_frame = ctk.CTkScrollableFrame(tab, label_text="My Keywords")
        self.keywords_list_frame.pack(fill="both", expand=True, padx=10, pady=10)
        self._refresh_keywords_list()

    def _add_keyword(self):
        kw = self.new_keyword_entry.get().strip()
        if not kw:
            return
        if kw not in self.keywords_data.get("favorites", []):
            if "favorites" not in self.keywords_data:
                self.keywords_data["favorites"] = []
            self.keywords_data["favorites"].append(kw)
            save_keywords(self.keywords_data)
            self._refresh_keywords_list()
            self.new_keyword_entry.delete(0, 'end')
            self.status_var.set(f"✅ Keyword '{kw}' added")

    def _delete_keyword(self, kw):
        if kw in self.keywords_data.get("favorites", []):
            self.keywords_data["favorites"].remove(kw)
            save_keywords(self.keywords_data)
            self._refresh_keywords_list()
            self.status_var.set(f"🗑️ Keyword '{kw}' deleted")

    def _refresh_keywords_list(self):
        for widget in self.keywords_list_frame.winfo_children():
            widget.destroy()
        for kw in self.keywords_data.get("favorites", []):
            frame = ctk.CTkFrame(self.keywords_list_frame)
            frame.pack(fill="x", padx=5, pady=2)
            label = ctk.CTkLabel(frame, text=kw, anchor="w")
            label.pack(side="left", fill="x", expand=True, padx=10)
            ctk.CTkButton(frame, text="🗑️", width=50, command=lambda k=kw: self._delete_keyword(k)).pack(side="right", padx=5)
            ctk.CTkButton(frame, text="🔍", width=50, command=lambda k=kw: self._quick_search(k)).pack(side="right", padx=5)

    def _quick_search(self, keyword):
        self.search_entry.delete(0, 'end')
        self.search_entry.insert(0, keyword)
        self._perform_search()
        self.tabview.set("Search")

    # ------------------------------------------------------------------
    # API Keys Tab
    # ------------------------------------------------------------------
    def _setup_api_keys_tab(self):
        tab = self.tabview.tab("API Keys")
        info = ctk.CTkLabel(tab, text="API keys are optional but improve rate limits.\nKeys are encrypted locally.", justify="left")
        info.pack(pady=10)

        scroll = ctk.CTkScrollableFrame(tab)
        scroll.pack(fill="both", expand=True, padx=10, pady=10)

        services = [
            ("wallhaven_api", "Wallhaven API Key", "Get from wallhaven.cc/settings"),
            ("reddit_client_id", "Reddit Client ID", "Get from reddit.com/prefs/apps"),
            ("reddit_client_secret", "Reddit Client Secret", ""),
        ]

        for key, label, hint in services:
            frame = ctk.CTkFrame(scroll)
            frame.pack(fill="x", pady=5)
            ctk.CTkLabel(frame, text=label, width=150).pack(side="left", padx=5)
            entry = ctk.CTkEntry(frame, placeholder_text=hint, width=300, show="*")
            entry.pack(side="left", fill="x", expand=True, padx=5)
            if key in self.api_keys and self.api_keys[key]:
                entry.insert(0, self.api_keys[key])
            self.api_entries[key] = entry
            ctk.CTkButton(frame, text="👁️", width=40, command=lambda e=entry: self._toggle_visibility(e)).pack(side="left", padx=2)
            ctk.CTkButton(frame, text="🗑️", width=40, command=lambda e=entry, k=key: self._clear_api_entry(e, k)).pack(side="left")

        btn_frame = ctk.CTkFrame(tab)
        btn_frame.pack(fill="x", padx=10, pady=10)
        ctk.CTkButton(btn_frame, text="💾 Save Keys", command=self._save_api_keys).pack(side="left", padx=5)
        ctk.CTkButton(btn_frame, text="Clear All", command=self._clear_all_keys, fg_color="darkred").pack(side="left", padx=5)

    def _toggle_visibility(self, entry):
        entry.configure(show="" if entry.cget("show") == "*" else "*")

    def _clear_api_entry(self, entry, key):
        entry.delete(0, 'end')
        if key in self.api_keys:
            del self.api_keys[key]
            save_api_keys(self.api_keys)

    def _save_api_keys(self):
        for key, entry in self.api_entries.items():
            val = entry.get().strip()
            if val:
                self.api_keys[key] = val
            elif key in self.api_keys:
                del self.api_keys[key]
        save_api_keys(self.api_keys)
        self.status_var.set("✅ API keys saved securely")
        messagebox.showinfo("Success", "API keys saved securely")

    def _clear_all_keys(self):
        if messagebox.askyesno("Confirm", "Delete ALL API keys?"):
            for entry in self.api_entries.values():
                entry.delete(0, 'end')
            self.api_keys = {}
            save_api_keys(self.api_keys)
            self.status_var.set("🗑️ All API keys cleared")

    # ------------------------------------------------------------------
    # History Tab
    # ------------------------------------------------------------------
    def _setup_history_tab(self):
        tab = self.tabview.tab("History")
        refresh_btn = ctk.CTkButton(tab, text="🔄 Refresh History", command=self._refresh_history, width=150)
        refresh_btn.pack(pady=5)

        self.history_text = ctk.CTkTextbox(tab, font=ctk.CTkFont(size=11))
        self.history_text.pack(fill="both", expand=True, padx=10, pady=10)
        self._refresh_history()

    def _refresh_history(self):
        self.history_text.delete("1.0", "end")
        try:
            rows = get_recent_downloads(100)
            if rows:
                self.history_text.insert("1.0", "📜 Recent downloads:\n\n")
                for row in rows:
                    filename, source, date, size = row
                    size_mb = size / (1024*1024) if size else 0
                    self.history_text.insert("end", f"📄 {filename} ({size_mb:.1f} MB) - {source} - {date[:10]}\n")
            else:
                self.history_text.insert("1.0", "No downloads yet. Start searching and downloading!")
        except Exception as e:
            logger.error(f"Error refreshing history: {e}")
            self.history_text.insert("1.0", "Error loading history")

    # ------------------------------------------------------------------
    # Queue Tab
    # ------------------------------------------------------------------
    def _setup_queue_tab(self):
        tab = self.tabview.tab("Queue")
        self.queue_text = ctk.CTkTextbox(tab, font=ctk.CTkFont(size=11))
        self.queue_text.pack(fill="both", expand=True, padx=10, pady=10)

        btn_frame = ctk.CTkFrame(tab)
        btn_frame.pack(fill="x", padx=10, pady=5)
        ctk.CTkButton(btn_frame, text="Clear Queue", command=self._clear_queue, fg_color="red").pack(side="left", padx=5)
        ctk.CTkButton(btn_frame, text="Refresh", command=self._refresh_queue_display).pack(side="left", padx=5)
        self._refresh_queue_display()

    def _refresh_queue_display(self):
        self.queue_text.delete("1.0", "end")
        with self.queue_lock:
            items = list(self.download_queue)
        if not items:
            self.queue_text.insert("1.0", "No pending downloads.")
            return
        for item in items:
            status = item.get('status', 'pending')
            retries = item.get('retries', 0)
            title = item.get('title', item['filename'][:50])
            self.queue_text.insert("end", f"{title[:60]} - {status} (retries: {retries})\n")

    def _clear_queue(self):
        if messagebox.askyesno("Clear Queue", "Remove all pending downloads?"):
            with self.queue_lock:
                self.download_queue.clear()
            clear_persistent_queue()
            self._refresh_queue_display()
            self.status_var.set("🗑️ Queue cleared")

    # ------------------------------------------------------------------
    # Scheduler Tab
    # ------------------------------------------------------------------
    def _setup_scheduler_tab(self):
        tab = self.tabview.tab("Scheduler")
        self.schedule_enabled_var = ctk.BooleanVar(value=self.settings.get("auto_download_schedule_enabled", False))
        ctk.CTkCheckBox(tab, text="✅ Enable automatic downloads", variable=self.schedule_enabled_var,
                        command=self._toggle_schedule).pack(anchor="w", padx=10, pady=5)

        ctk.CTkLabel(tab, text="Keywords to auto-download (select from favorites):").pack(anchor="w", padx=10, pady=(10,0))

        self.schedule_keywords_listbox = Listbox(tab, selectmode="multiple", height=6,
                                                  bg="#2b2b2b", fg="white", selectbackground="#3b8ed0")
        self.schedule_keywords_listbox.pack(fill="x", padx=10, pady=5)
        self._refresh_keywords_listbox()

        limit_frame = ctk.CTkFrame(tab)
        limit_frame.pack(fill="x", padx=10, pady=5)
        ctk.CTkLabel(limit_frame, text="Limit per keyword:").pack(side="left", padx=5)
        self.schedule_limit_entry = ctk.CTkEntry(limit_frame, width=80)
        self.schedule_limit_entry.insert(0, str(self.settings.get("schedule_limit", 10)))
        self.schedule_limit_entry.pack(side="left", padx=5)

        ctk.CTkButton(tab, text="💾 Save Schedule Settings", command=self._save_schedule_settings,
                     height=35, fg_color="green").pack(pady=10)

    def _refresh_keywords_listbox(self):
        self.schedule_keywords_listbox.delete(0, 'end')
        for kw in self.keywords_data.get("favorites", []):
            self.schedule_keywords_listbox.insert('end', kw)

    def _toggle_schedule(self):
        enabled = self.schedule_enabled_var.get()
        self.settings["auto_download_schedule_enabled"] = enabled
        save_settings(self.settings)
        self.status_var.set(f"Schedule {'enabled' if enabled else 'disabled'}")

    def _save_schedule_settings(self):
        indices = self.schedule_keywords_listbox.curselection()
        keywords = [self.schedule_keywords_listbox.get(i) for i in indices]
        self.settings["schedule_keywords"] = keywords
        self.settings["schedule_limit"] = int(self.schedule_limit_entry.get()) if self.schedule_limit_entry.get().isdigit() else 10
        save_settings(self.settings)
        self.status_var.set(f"✅ Schedule saved: {len(keywords)} keywords")

    # ------------------------------------------------------------------
    # Settings Tab
    # ------------------------------------------------------------------
    def _setup_settings_tab(self):
        tab = self.tabview.tab("Settings")

        theme_frame = ctk.CTkFrame(tab)
        theme_frame.pack(fill="x", padx=10, pady=5)
        ctk.CTkLabel(theme_frame, text="🎨 Theme", font=ctk.CTkFont(weight="bold")).pack(anchor="w")
        self.theme_var = ctk.StringVar(value=self.settings.get("theme", "Dark"))
        ctk.CTkRadioButton(theme_frame, text="Dark", variable=self.theme_var, value="Dark", command=self._toggle_theme).pack(anchor="w", padx=20)
        ctk.CTkRadioButton(theme_frame, text="Light", variable=self.theme_var, value="Light", command=self._toggle_theme).pack(anchor="w", padx=20)

        disk_frame = ctk.CTkFrame(tab)
        disk_frame.pack(fill="x", padx=10, pady=5)
        ctk.CTkLabel(disk_frame, text="💾 Disk Space", font=ctk.CTkFont(weight="bold")).pack(anchor="w")
        self.disk_status_label = ctk.CTkLabel(disk_frame, text="")
        self.disk_status_label.pack(anchor="w", padx=20, pady=2)
        self._update_disk_status()

        limit_frame = ctk.CTkFrame(disk_frame, fg_color="transparent")
        limit_frame.pack(anchor="w", padx=20, pady=5)
        ctk.CTkLabel(limit_frame, text="Max allowed (GB):").pack(side="left")
        self.disk_limit_var = ctk.IntVar(value=self.settings.get("disk_limit_gb", 10))
        self.disk_limit_entry = ctk.CTkEntry(limit_frame, width=80, textvariable=self.disk_limit_var)
        self.disk_limit_entry.pack(side="left", padx=5)
        ctk.CTkButton(limit_frame, text="Set Limit", command=self._save_disk_limit, width=80).pack(side="left", padx=5)
        ctk.CTkButton(disk_frame, text="🧹 Clean Now", command=self._clean_disk_space, fg_color="orange").pack(anchor="w", padx=20, pady=5)
        self.auto_clean_var = ctk.BooleanVar(value=self.settings.get("auto_clean_on_startup", False))
        ctk.CTkCheckBox(disk_frame, text="Auto-clean on startup", variable=self.auto_clean_var, command=self._toggle_auto_clean).pack(anchor="w", padx=20)

        startup_frame = ctk.CTkFrame(tab)
        startup_frame.pack(fill="x", padx=10, pady=5)
        ctk.CTkLabel(startup_frame, text="🚀 Startup Downloads", font=ctk.CTkFont(weight="bold")).pack(anchor="w")
        self.startup_dl_var = ctk.BooleanVar(value=self.settings.get("auto_download_on_startup", True))
        ctk.CTkCheckBox(startup_frame, text="Download on startup", variable=self.startup_dl_var,
                        command=self._toggle_startup_dl).pack(anchor="w", padx=20)

        kw_frame = ctk.CTkFrame(startup_frame, fg_color="transparent")
        kw_frame.pack(anchor="w", padx=20, pady=5)
        ctk.CTkLabel(kw_frame, text="Keywords (comma):").pack(side="left")
        self.startup_keywords_entry = ctk.CTkEntry(kw_frame, width=300)
        self.startup_keywords_entry.insert(0, ", ".join(self.settings.get("startup_keywords", [])))
        self.startup_keywords_entry.pack(side="left", padx=5)

        limit_f = ctk.CTkFrame(startup_frame, fg_color="transparent")
        limit_f.pack(anchor="w", padx=20, pady=5)
        ctk.CTkLabel(limit_f, text="Limit per keyword:").pack(side="left")
        self.startup_limit_entry = ctk.CTkEntry(limit_f, width=80)
        self.startup_limit_entry.insert(0, str(self.settings.get("startup_limit_per_keyword", 10)))
        self.startup_limit_entry.pack(side="left", padx=5)

        pages_frame = ctk.CTkFrame(startup_frame, fg_color="transparent")
        pages_frame.pack(anchor="w", padx=20, pady=5)
        ctk.CTkLabel(pages_frame, text="Search pages for new wallpapers:").pack(side="left")
        self.startup_pages_entry = ctk.CTkEntry(pages_frame, width=80)
        self.startup_pages_entry.insert(0, str(self.settings.get("max_search_pages", 5)))
        self.startup_pages_entry.pack(side="left", padx=5)

        ctk.CTkButton(startup_frame, text="Save Startup Settings", command=self._save_startup_settings).pack(anchor="w", padx=20, pady=5)

        org_frame = ctk.CTkFrame(tab)
        org_frame.pack(fill="x", padx=10, pady=5)
        ctk.CTkLabel(org_frame, text="📁 Organization", font=ctk.CTkFont(weight="bold")).pack(anchor="w")
        self.org_mode_var = ctk.StringVar(value=self.settings.get("org_mode", "detailed"))
        ctk.CTkRadioButton(org_frame, text="Detailed (folders by date)", variable=self.org_mode_var, value="detailed", command=self._save_org_mode).pack(anchor="w", padx=20)
        ctk.CTkRadioButton(org_frame, text="Flat (single folder)", variable=self.org_mode_var, value="flat", command=self._save_org_mode).pack(anchor="w", padx=20)

        notif_frame = ctk.CTkFrame(tab)
        notif_frame.pack(fill="x", padx=10, pady=5)
        ctk.CTkLabel(notif_frame, text="🔔 Notifications", font=ctk.CTkFont(weight="bold")).pack(anchor="w")
        self.notif_var = ctk.BooleanVar(value=self.settings.get("show_notifications", True))
        ctk.CTkCheckBox(notif_frame, text="Show desktop notifications", variable=self.notif_var, command=self._toggle_notifications).pack(anchor="w", padx=20)

    def _save_startup_settings(self):
        keywords = [k.strip() for k in self.startup_keywords_entry.get().split(",") if k.strip()]
        self.settings["startup_keywords"] = keywords
        self.settings["startup_limit_per_keyword"] = int(self.startup_limit_entry.get()) if self.startup_limit_entry.get().isdigit() else 10
        self.settings["max_search_pages"] = int(self.startup_pages_entry.get()) if self.startup_pages_entry.get().isdigit() else 5
        save_settings(self.settings)
        self.status_var.set(f"✅ Startup: {len(keywords)} keywords, {self.settings['max_search_pages']} pages")

    def _toggle_theme(self):
        mode = self.theme_var.get().lower()
        ctk.set_appearance_mode(mode)
        self.settings["theme"] = self.theme_var.get()
        save_settings(self.settings)

    def _toggle_notifications(self):
        self.settings["show_notifications"] = self.notif_var.get()
        save_settings(self.settings)

    def _toggle_startup_dl(self):
        self.settings["auto_download_on_startup"] = self.startup_dl_var.get()
        save_settings(self.settings)

    def _save_org_mode(self):
        self.settings["org_mode"] = self.org_mode_var.get()
        save_settings(self.settings)

    def _save_disk_limit(self):
        limit = self.disk_limit_var.get()
        if limit > 0:
            self.settings["disk_limit_gb"] = limit
            save_settings(self.settings)
            self.status_var.set(f"✅ Disk limit set to {limit} GB")

    def _toggle_auto_clean(self):
        self.settings["auto_clean_on_startup"] = self.auto_clean_var.get()
        save_settings(self.settings)

    def _clean_disk_space(self):
        limit = self.settings.get("disk_limit_gb", 10)
        current = get_folder_size_gb(self.download_dir)
        if current <= limit:
            messagebox.showinfo("Disk Cleanup", f"Current size {current:.1f} GB is under limit ({limit} GB).")
            return
        deleted, new_size = delete_oldest_downloads(self.download_dir, limit)
        messagebox.showinfo("Cleanup Complete", f"Deleted {len(deleted)} files.\nSize reduced from {current:.1f} GB to {new_size:.1f} GB.")
        self.status_var.set(f"🧹 Cleaned {len(deleted)} files")
        self._update_disk_status()

    def _update_disk_status(self):
        total = get_folder_size_gb(self.download_dir)
        free = get_free_space_gb(self.download_dir)
        self.disk_status_label.configure(text=f"📊 Used: {total:.1f} GB | Free: {free:.1f} GB")

    # ------------------------------------------------------------------
    # DOWNLOAD FUNCTIONS - Multi-page search
    # ------------------------------------------------------------------
    def _download_keyword(self, keyword, limit, retries=3):
        for attempt in range(retries):
            if SHUTDOWN_FLAG.is_set() or self._shutting_down:
                return
                
            try:
                last_page = get_keyword_last_page(keyword)
                max_pages = self.settings.get("max_search_pages", 5)
                start_page = last_page
                new_downloads = 0
                downloaded_urls = get_downloaded_urls()
                
                for page in range(start_page, start_page + max_pages):
                    if new_downloads >= limit or SHUTDOWN_FLAG.is_set():
                        break
                        
                    self.status_var.set(f"🔍 Searching page {page} for '{keyword}'...")
                    params = {
                        "q": keyword, 
                        "categories": "111", 
                        "purity": "100", 
                        "sorting": "relevance", 
                        "page": page
                    }
                    if 'wallhaven_api' in self.api_keys and self.api_keys['wallhaven_api']:
                        params["apikey"] = self.api_keys['wallhaven_api']
                        
                    resp = requests.get("https://wallhaven.cc/api/v1/search", 
                                       params=params, 
                                       headers={"User-Agent": "WallpaperCache/1.0"}, 
                                       timeout=30)
                    resp.raise_for_status()
                    data = resp.json()
                    items = data.get("data", [])
                    
                    if not items:
                        self.status_var.set(f"📭 No more wallpapers for '{keyword}'")
                        break
                        
                    for item in items:
                        if new_downloads >= limit or SHUTDOWN_FLAG.is_set():
                            break
                        img_url = item.get("path")
                        if not img_url or img_url in downloaded_urls:
                            continue
                            
                        title = item.get("title", f"WH_{item['id']}")
                        filename = self._sanitize_filename(f"{title}.jpg")
                        
                        add_to_persistent_queue(img_url, filename, title, None)
                        with self.queue_lock:
                            self.download_queue.append({
                                'url': img_url, 
                                'filename': filename, 
                                'title': title, 
                                'retries': 0, 
                                'status': 'pending'
                            })
                        downloaded_urls.add(img_url)
                        new_downloads += 1
                        time.sleep(0.3)
                    
                    update_keyword_last_page(keyword, page + 1)
                    time.sleep(0.5)
                
                if new_downloads > 0:
                    self.after(0, self._refresh_queue_display)
                    self.status_var.set(f"✅ Found {new_downloads} new wallpapers for '{keyword}'")
                    self._send_notification(f"New Wallpapers: {keyword}", f"Found {new_downloads} new wallpapers")
                else:
                    self.status_var.set(f"📭 No new wallpapers for '{keyword}'")
                return  # Success
                
            except requests.exceptions.RequestException as e:
                logger.error(f"Keyword download error for {keyword} (attempt {attempt+1}): {e}")
                if attempt == retries - 1:
                    self.after(0, lambda: self.status_var.set(f"❌ Error searching '{keyword}': {str(e)[:50]}"))
                else:
                    time.sleep(2 ** attempt)  # Exponential backoff
            except Exception as e:
                logger.error(f"Unexpected error for {keyword}: {e}")
                self.after(0, lambda: self.status_var.set(f"❌ Error searching '{keyword}': {str(e)[:50]}"))
                break

    def run_startup_download(self):
        if self._shutting_down:
            return
        keywords = self.settings.get("startup_keywords", [])
        limit = self.settings.get("startup_limit_per_keyword", 10)
        if keywords:
            self.status_var.set(f"🚀 Startup: searching for new wallpapers for {len(keywords)} keywords...")
            for kw in keywords:
                if self._shutting_down:
                    break
                self.executor.submit(self._download_keyword, kw, limit)
                time.sleep(1)

    def _process_task_queue(self):
        """Process background tasks from the queue"""
        try:
            while not self.task_queue.empty() and not self._shutting_down:
                task = self.task_queue.get_nowait()
                if callable(task):
                    self.executor.submit(task)
        except Empty:
            pass
        finally:
            if not self._shutting_down:
                self.after(100, self._process_task_queue)

    def _process_queue(self):
        """Process the download queue with proper locking"""
        if self._shutting_down:
            return
            
        with self.queue_lock:
            pending = [item for item in self.download_queue if item.get('status') == 'pending']
            if self.active_downloads < self.max_concurrent and pending:
                item = pending[0]
                item['status'] = 'active'
                self.active_downloads += 1
                self.executor.submit(self._download_with_retry, item.copy())
        self.after(1000, self._process_queue)

    def _download_with_retry(self, item):
        """Download with retry logic"""
        url = item['url']
        filename = item['filename']
        title = item.get('title', filename)
        max_retries = 3

        for attempt in range(max_retries):
            if SHUTDOWN_FLAG.is_set() or self._shutting_down:
                with self.queue_lock:
                    if item in self.download_queue:
                        self.download_queue.remove(item)
                self.active_downloads -= 1
                return False
                
            try:
                if self._do_download(url, filename, title):
                    with self.queue_lock:
                        if item in self.download_queue:
                            self.download_queue.remove(item)
                    remove_from_persistent_queue(url)
                    self.active_downloads -= 1
                    self.after(0, self._refresh_queue_display)
                    return True
            except Exception as e:
                logger.error(f"Download attempt {attempt+1} failed for {filename}: {e}")
                if attempt < max_retries - 1:
                    delay = 2 ** (attempt + 1)  # Exponential backoff
                    self.status_var.set(f"🔄 Retry {attempt+1}/{max_retries} for {filename[:30]} in {delay}s")
                    time.sleep(delay)
                else:
                    self.status_var.set(f"❌ Failed after {max_retries} attempts: {filename[:30]}")
                    self._send_notification("Download Failed", title[:50], "critical")
                    with self.queue_lock:
                        if item in self.download_queue:
                            self.download_queue.remove(item)
                    remove_from_persistent_queue(url)
                    self.active_downloads -= 1
                    self.after(0, self._refresh_queue_display)
                    return False

    def _do_download(self, url, filename, title):
        """Perform the actual download"""
        org_mode = self.settings.get("org_mode", "detailed")
        if org_mode == "flat":
            filepath = Path(self.download_dir) / filename
        else:
            date_folder = datetime.now().strftime("%Y-%m")
            filepath = Path(self.download_dir) / "Wallhaven" / date_folder / filename
            filepath.parent.mkdir(parents=True, exist_ok=True)

        if filepath.exists():
            self.after(0, lambda: self.status_var.set(f"⏭️ Already exists: {filename[:40]}"))
            return True

        try:
            response = requests.get(url, stream=True, timeout=60)
            response.raise_for_status()
            total_size = int(response.headers.get('content-length', 0))
            downloaded = 0
            
            # Write to temporary file first to avoid corruption
            temp_path = filepath.with_suffix('.tmp')
            with open(temp_path, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    if SHUTDOWN_FLAG.is_set():
                        temp_path.unlink(missing_ok=True)
                        return False
                    if chunk:
                        f.write(chunk)
                        downloaded += len(chunk)
                        if total_size > 0:
                            percent = (downloaded / total_size) * 100
                            self.after(0, lambda p=percent: self.progress_bar.set(p/100))
                            self.after(0, lambda p=percent: self.status_var.set(f"📥 {filename[:30]}... {p:.0f}%"))
            
            # Rename temp file to final name
            temp_path.rename(filepath)

            file_hash = hashlib.md5(filepath.read_bytes()).hexdigest()
            add_download_record(filename, filepath, url, "Wallhaven", filepath.stat().st_size, file_hash)

            self.downloaded_urls.add(url)
            self.after(0, lambda: self.status_var.set(f"✅ Downloaded: {filename[:40]}"))
            self.after(0, self._refresh_history)
            self._send_notification("Download Complete", title[:50], "low")
            return True
        except Exception as e:
            # Clean up temp file on error
            if 'temp_path' in locals():
                temp_path.unlink(missing_ok=True)
            logger.error(f"Download error: {e}")
            raise  # Re-raise to trigger retry

    # ------------------------------------------------------------------
    # Utility Functions
    # ------------------------------------------------------------------
    def _change_dir(self):
        new_dir = filedialog.askdirectory(initialdir=self.download_dir)
        if new_dir and new_dir != self.download_dir:
            self.download_dir = new_dir
            self.settings["download_dir"] = new_dir
            save_settings(self.settings)
            self.dir_label.configure(text=f"📁 Download folder: {self.download_dir}")

    def _open_folder(self):
        try:
            subprocess.run(['xdg-open', self.download_dir], check=False)
        except Exception as e:
            logger.error(f"Error opening folder: {e}")

    def _sanitize_filename(self, name):
        name = re.sub(r'[<>:"/\\|?*]', '_', name)
        name = re.sub(r'[^a-zA-Z0-9_\-\. ]', '', name)
        return name[:150].strip()

    def _show_error(self, msg):
        messagebox.showerror("Error", msg)
        self.status_var.set("❌ Error")

    def __del__(self):
        self.cleanup()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--minimized", action="store_true")
    args = parser.parse_args()
    
    app = WallpaperCacheApp()
    if args.minimized:
        app.withdraw()
    app.mainloop()

if __name__ == "__main__":
    main()
EOF

    chmod +x "$INSTALL_DIR/wallpaper_cache.py"
    print_success "Script created"
}

create_launcher() {
    local de=$1
    local display=$2
    
    print_info "Creating launcher for $de..."
    
    # Determine display settings
    local display_env=""
    local wayland_env=""
    
    if [[ "$de" == "niri" ]]; then
        display_env=":0"
        wayland_env="wayland-0"
    elif [[ "$de" == "kde-plasma" ]]; then
        display_env=":1"
        wayland_env="wayland-0"
    elif [[ "$de" == "kde-caelestia" ]]; then
        display_env=":1"
        wayland_env="wayland-0"
    else
        display_env=":0"
        wayland_env="wayland-0"
    fi
    
    cat > "$BIN_DIR/wallpaper-cache" << EOF
#!/bin/bash
# Wallpaper Cache Launcher for $de
export DISPLAY=$display_env
export WAYLAND_DISPLAY=$wayland_env
export XDG_RUNTIME_DIR=/run/user/\$(id -u)

source "$VENV_DIR/bin/activate"
python "$INSTALL_DIR/wallpaper_cache.py" "\$@"
EOF

    chmod +x "$BIN_DIR/wallpaper-cache"
    print_success "Launcher created at $BIN_DIR/wallpaper-cache"
}

configure_autostart() {
    local de=$1
    
    print_info "Configuring auto-start for $de..."
    
    case "$de" in
        niri)
            if [ -f "$NIRI_CONFIG" ]; then
                if ! grep -q "wallpaper-cache" "$NIRI_CONFIG"; then
                    echo "" >> "$NIRI_CONFIG"
                    echo "# Auto-start Wallpaper Cache" >> "$NIRI_CONFIG"
                    echo "spawn-at-startup { command \"sh\" \"-c\" \"sleep 5 && $BIN_DIR/wallpaper-cache --minimized\"; }" >> "$NIRI_CONFIG"
                    print_success "Added to Niri config"
                else
                    print_warning "Already in Niri config"
                fi
            else
                print_warning "Niri config not found"
            fi
            ;;
            
        kde-plasma|kde-caelestia)
            cat > "$AUTOSTART_DIR/wallpaper-cache.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Wallpaper Cache
Exec=env DISPLAY=:1 WAYLAND_DISPLAY=wayland-0 $VENV_DIR/bin/python $INSTALL_DIR/wallpaper_cache.py --minimized
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Comment=Download wallpapers automatically
X-GNOME-Autostart-Delay=5
EOF
            print_success "Added to KDE autostart"
            ;;
            
        *)
            print_warning "Unknown desktop: $de"
            ;;
    esac
}

add_to_path() {
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
        print_warning "Added ~/.local/bin to PATH. Please restart your shell or run: source ~/.bashrc"
    fi
}

# ============================================================
# Bash Aliases
# ============================================================

add_bash_aliases() {
    print_info "Adding Bash aliases..."
    
    # Determine which bash config file to use
    local bash_config=""
    if [ -f "$BASH_ALIASES" ]; then
        bash_config="$BASH_ALIASES"
    elif [ -f "$BASH_CONFIG" ]; then
        bash_config="$BASH_CONFIG"
    else
        print_warning "No bash config file found. Creating $BASH_CONFIG..."
        bash_config="$BASH_CONFIG"
        touch "$bash_config"
    fi
    
    # Check if aliases already exist
    if grep -q "alias wc=" "$bash_config" 2>/dev/null; then
        print_warning "Bash aliases already exist in $bash_config"
        return
    fi
    
    # Add aliases to bash config
    echo "" >> "$bash_config"
    echo "# ============================================================" >> "$bash_config"
    echo "# Wallpaper Cache Aliases" >> "$bash_config"
    echo "# ============================================================" >> "$bash_config"
    echo "alias wc=\"$BIN_DIR/wallpaper-cache\"" >> "$bash_config"
    echo "alias wcm=\"$BIN_DIR/wallpaper-cache --minimized\"" >> "$bash_config"
    echo "alias wcl=\"tail -f $CONFIG_DIR/app.log\"" >> "$bash_config"
    echo "alias wck=\"pkill -f wallpaper_cache.py\"" >> "$bash_config"
    echo "alias wcs=\"systemctl --user status wallpaper-cache.service\"" >> "$bash_config"
    echo "alias wcr=\"systemctl --user restart wallpaper-cache.service\"" >> "$bash_config"
    echo "alias wcf=\"cd $CONFIG_DIR\"" >> "$bash_config"
    echo "alias wcd=\"cd ~/Pictures/WallpaperCache\"" >> "$bash_config"
    
    print_success "Bash aliases added to $bash_config"
    print_info "Available aliases:"
    echo "  wc  - Start Wallpaper Cache"
    echo "  wcm - Start Wallpaper Cache (minimized)"
    echo "  wcl - View logs"
    echo "  wck - Kill the app"
    echo "  wcs - Check service status"
    echo "  wcr - Restart service"
    echo "  wcf - Go to config directory"
    echo "  wcd - Go to downloads directory"
    
    # Source the config file if it's the current shell
    if [[ "$bash_config" == "$BASH_CONFIG" ]] && [ -n "$BASH_VERSION" ]; then
        print_info "To apply aliases in current shell: source $bash_config"
    fi
}

# ============================================================
# Fish Shell Abbreviations
# ============================================================

add_fish_abbreviations() {
    print_info "Adding Fish shell abbreviations..."
    
    # Check if Fish config exists
    if [ -f "$FISH_CONFIG" ]; then
        # Check if abbreviations already exist with proper pattern matching
        if grep -q "abbr.*wallpaper-cache" "$FISH_CONFIG" 2>/dev/null; then
            print_warning "Fish abbreviations already exist in config"
        else
            # Add abbreviations to Fish config
            echo "" >> "$FISH_CONFIG"
            echo "# ============================================================" >> "$FISH_CONFIG"
            echo "# Wallpaper Cache Abbreviations" >> "$FISH_CONFIG"
            echo "# ============================================================" >> "$FISH_CONFIG"
            echo "abbr -a wc \"$BIN_DIR/wallpaper-cache\"" >> "$FISH_CONFIG"
            echo "abbr -a wcm \"$BIN_DIR/wallpaper-cache --minimized\"" >> "$FISH_CONFIG"
            echo "abbr -a wcl \"tail -f $CONFIG_DIR/app.log\"" >> "$FISH_CONFIG"
            echo "abbr -a wck \"pkill -f wallpaper_cache.py\"" >> "$FISH_CONFIG"
            echo "abbr -a wcs \"systemctl --user status wallpaper-cache.service\"" >> "$FISH_CONFIG"
            echo "abbr -a wcr \"systemctl --user restart wallpaper-cache.service\"" >> "$FISH_CONFIG"
            echo "abbr -a wcf \"cd $CONFIG_DIR\"" >> "$FISH_CONFIG"
            echo "abbr -a wcd \"cd ~/Pictures/WallpaperCache\"" >> "$FISH_CONFIG"
            
            print_success "Fish abbreviations added to $FISH_CONFIG"
            print_info "Available abbreviations:"
            echo "  wc  - Start Wallpaper Cache"
            echo "  wcm - Start Wallpaper Cache (minimized)"
            echo "  wcl - View logs"
            echo "  wck - Kill the app"
            echo "  wcs - Check service status"
            echo "  wcr - Restart service"
            echo "  wcf - Go to config directory"
            echo "  wcd - Go to downloads directory"
        fi
    else
        print_warning "Fish config not found at $FISH_CONFIG"
        print_info "Create it manually with:"
        echo ""
        echo "  # Add to ~/.config/fish/config.fish"
        echo "  abbr -a wc \"$BIN_DIR/wallpaper-cache\""
        echo "  abbr -a wcm \"$BIN_DIR/wallpaper-cache --minimized\""
    fi
}

# ============================================================
# Shell Integration (Main Function)
# ============================================================

setup_shell_integration() {
    local current_shell=$(detect_shell)
    local de=$1
    
    print_info "Setting up shell integration for $current_shell..."
    
    # Add bash aliases (always add for bash)
    if [[ "$current_shell" == "bash" ]] || [[ -f "$BASH_CONFIG" ]]; then
        add_bash_aliases
    fi
    
    # Add fish abbreviations (always add for fish)
    if [[ "$current_shell" == "fish" ]] || [[ -f "$FISH_CONFIG" ]]; then
        add_fish_abbreviations
    fi
    
    # If KDE Caelestia is detected, ensure fish abbreviations are added
    if [[ "$de" == "kde-caelestia" ]]; then
        print_info "KDE Caelestia detected - ensuring Fish shell support..."
        if [[ "$current_shell" != "fish" ]]; then
            print_info "Current shell is $current_shell, but Caelestia uses Fish by default"
            print_info "Adding Fish abbreviations as well..."
            add_fish_abbreviations
        fi
    fi
    
    # If Niri is detected, ensure bash aliases are added
    if [[ "$de" == "niri" ]]; then
        print_info "Niri detected - ensuring Bash shell support..."
        if [[ "$current_shell" != "bash" ]]; then
            print_info "Current shell is $current_shell, but Niri uses Bash by default"
            print_info "Adding Bash aliases as well..."
            add_bash_aliases
        fi
    fi
    
    print_success "Shell integration complete!"
}

# ============================================================
# Interactive Desktop Selection
# ============================================================

select_desktop() {
    clear
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                         ║"
    echo "║   🖥️  SELECT DESKTOP ENVIRONMENT                        ║"
    echo "║                                                         ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    echo "  1) Niri (Wayland) - ${GREEN}Recommended${NC} - Uses Bash"
    echo "  2) KDE Plasma (Wayland) - Uses Bash"
    echo "  3) KDE Plasma Caelestia (Wayland) - Uses Fish"
    echo "  4) Auto-detect (try to detect automatically)"
    echo ""
    echo "  Detected: $(detect_desktop)"
    echo "  Shell: $(detect_shell)"
    echo ""
    read -p "Select option [1-4]: " choice
    
    # Validate input
    if [[ ! "$choice" =~ ^[1-4]$ ]]; then
        print_error "Invalid choice. Using auto-detect..."
        choice=4
    fi
    
    case $choice in
        1) echo "niri" ;;
        2) echo "kde-plasma" ;;
        3) echo "kde-caelestia" ;;
        4) echo "$(detect_desktop)" ;;
    esac
}

# ============================================================
# Main Script
# ============================================================

main() {
    clear
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                         ║"
    echo "║   🖼️  Wallpaper Cache - Universal Installer v2.3        ║"
    echo "║                                                         ║"
    echo "║   Auto-download wallpapers for Niri & KDE Plasma       ║"
    echo "║   + Bash aliases & Fish abbreviations                  ║"
    echo "║                                                         ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    
    # Detect or select desktop
    local detected_de=$(detect_desktop)
    local detected_shell=$(detect_shell)
    
    print_info "Detected desktop: $detected_de"
    print_info "Detected shell: $detected_shell"
    echo ""
    
    if [[ "$detected_de" != "unknown" ]]; then
        read -p "Use detected desktop? (y/n): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            local DE="$detected_de"
        else
            local DE=$(select_desktop)
        fi
    else
        print_warning "Could not detect desktop environment"
        local DE=$(select_desktop)
    fi
    
    if [[ "$DE" == "unknown" ]]; then
        print_error "Could not determine desktop. Please select manually."
        local DE=$(select_desktop)
    fi
    
    print_info "Installing for: $GREEN$DE$NC"
    echo ""
    
    # Run installation
    install_dependencies
    create_directories
    create_virtual_env
    install_python_packages
    create_script
    create_launcher "$DE"
    configure_autostart "$DE"
    add_to_path
    
    # Setup shell integration (Bash aliases and Fish abbreviations)
    setup_shell_integration "$DE"
    
    # Summary
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                         ║"
    echo "║   ✅ INSTALLATION COMPLETE!                            ║"
    echo "║                                                         ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    echo "  📁 Script: $INSTALL_DIR/wallpaper_cache.py"
    echo "  🎯 Launcher: $BIN_DIR/wallpaper-cache"
    echo "  ⚙️  Config: $CONFIG_DIR"
    echo "  🖥️  Desktop: $DE"
    echo "  🐚  Shell: $detected_shell"
    echo ""
    echo "  🚀 To start: $BIN_DIR/wallpaper-cache"
    echo "  🖥️  Minimized: $BIN_DIR/wallpaper-cache --minimized"
    echo ""
    echo "  📝 Shell Aliases/Abbreviations:"
    echo "     wc  - Start Wallpaper Cache"
    echo "     wcm - Start Wallpaper Cache (minimized)"
    echo "     wcl - View logs"
    echo "     wck - Kill the app"
    echo "     wcs - Check service status"
    echo "     wcr - Restart service"
    echo "     wcf - Go to config directory"
    echo "     wcd - Go to downloads directory"
    echo ""
    
    # Show shell-specific reload instructions
    if [[ "$detected_shell" == "bash" ]]; then
        echo "  💡 To apply aliases in current shell:"
        echo "     source ~/.bashrc  (or ~/.bash_aliases)"
    elif [[ "$detected_shell" == "fish" ]]; then
        echo "  💡 To apply abbreviations in current shell:"
        echo "     exec fish"
    fi
    echo ""
    
    # Ask to start
    read -p "Start Wallpaper Cache now? (y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        "$BIN_DIR/wallpaper-cache" --minimized &
        print_success "Wallpaper Cache started!"
        echo ""
        echo "  📝 Check logs: tail -f $CONFIG_DIR/app.log"
    fi
    
    echo ""
    echo "  ✨ For Fish users:"
    echo "     Your abbreviations will work after restarting Fish: exec fish"
    echo ""
}

# Run main
main
