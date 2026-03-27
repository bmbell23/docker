#!/usr/bin/env python3
"""
Simple Flask backend for Docker container management.
Provides REST API endpoints for restarting and recreating containers.
"""

from flask import Flask, jsonify, request, send_from_directory
from flask_cors import CORS
import subprocess
import logging
import os
import json
import uuid
import threading
import sqlite3
import time
from datetime import datetime
import requests

app = Flask(__name__, static_folder='static')
CORS(app)  # Enable CORS for frontend requests

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Container mappings: service_id -> {container_name, compose_dir, service (compose service name)}
CONTAINERS = {
    # Media
    'immich': {'name': 'immich', 'service': 'immich', 'compose_dir': 'immich'},
    'jellyfin': {'name': 'jellyfin', 'service': 'jellyfin', 'compose_dir': 'jellyfin'},
    'audiobookshelf': {'name': 'audiobookshelf', 'service': 'audiobookshelf', 'compose_dir': 'audiobookshelf'},
    'romm': {'name': 'romm', 'service': 'romm', 'compose_dir': 'romm'},

    # Downloads
    'qbittorrent': {'name': 'qbittorrent', 'service': 'qbittorrent', 'compose_dir': 'torrents'},
    'jackett': {'name': 'jackett', 'service': 'jackett', 'compose_dir': 'jackett'},
    'ytdlp': {'name': 'yt-dlp-web', 'service': 'yt-dlp-web', 'compose_dir': 'youtube-downloader'},
    'deemix': {'name': 'deemix', 'service': 'deemix', 'compose_dir': 'deemix'},

    # Forge Apps
    'lifeforge': {'name': 'lifeforge_app', 'service': 'lifeforge', 'compose_dir': '/home/brandon/projects/LifeForge'},
    'artforge': {'name': 'artforge', 'service': 'artforge', 'compose_dir': '/home/brandon/projects/ArtForge'},
    'wordforge': {'name': 'wordforge', 'service': 'wordforge', 'compose_dir': '/home/brandon/projects/WordForge'},
    'codeforge': {'name': 'codeforge_app', 'service': 'codeforge', 'compose_dir': '/home/brandon/projects/CodeForge'},

    # Reading
    'greatreads-prod': {'name': 'greatreads_app', 'service': 'greatreads', 'compose_dir': '/home/brandon/projects/GreatReads'},
    'booknews': {'name': 'booknews', 'service': 'booknews', 'compose_dir': '/home/brandon/projects/NerdNews'},
    'kidmedia': {'name': 'kidmedia', 'service': 'kidmedia', 'compose_dir': '/home/brandon/projects/KidMedia'},
    'calibre': {'name': 'calibre', 'service': 'calibre', 'compose_dir': 'calibre'},
    'libby-web': {'name': 'libby-web', 'service': 'libby-web', 'compose_dir': 'libby-web'},

    # Tools
    'stash': {'name': 'stash', 'service': 'stash', 'compose_dir': 'stash'},
    'trilium': {'name': 'trilium', 'service': 'trilium', 'compose_dir': 'trilium'},
    'dictionary': {'name': 'dictionary-api', 'service': 'dictionary-api', 'compose_dir': 'dictionary'},
}

# =============================================================================
# Infrastructure Monitoring — runs in a background thread every 60 s,
# persists to SQLite, caches latest snapshot for fast API responses.
# =============================================================================

DB_PATH = '/app/data/metrics.db'

# Every container we want to track on the health page (actual docker name → display info)
MONITORED_CONTAINERS = [
    {'name': 'booknews',       'label': 'NerdNews',       'category': 'Apps'},
    {'name': 'greatreads_app', 'label': 'GreatReads',     'category': 'Apps'},
    {'name': 'audiobookshelf', 'label': 'Audiobookshelf', 'category': 'Apps'},
    {'name': 'calibre',        'label': 'Calibre',        'category': 'Apps'},
    {'name': 'libby-web',      'label': 'Libby Browser',  'category': 'Apps'},
    {'name': 'lifeforge_app',  'label': 'LifeForge',      'category': 'Apps'},
    {'name': 'artforge',       'label': 'ArtForge',       'category': 'Apps'},
    {'name': 'wordforge',      'label': 'WordForge',      'category': 'Apps'},
    {'name': 'codeforge_app',  'label': 'CodeForge',      'category': 'Apps'},
    {'name': 'kidmedia',       'label': 'KidMedia',       'category': 'Apps'},
    {'name': 'immich',         'label': 'Immich',         'category': 'Media'},
    {'name': 'immich-db',      'label': 'Immich DB',      'category': 'Media'},
    {'name': 'jellyfin',       'label': 'Jellyfin',       'category': 'Media'},
    {'name': 'romm',           'label': 'RomM',           'category': 'Media'},
    {'name': 'romm-db',        'label': 'RomM DB',        'category': 'Media'},
    {'name': 'qbittorrent',    'label': 'qBittorrent',    'category': 'Downloads'},
    {'name': 'jackett',        'label': 'Jackett',        'category': 'Downloads'},
    {'name': 'flaresolverr',   'label': 'FlareSolverr',   'category': 'Downloads'},
    {'name': 'yt-dlp-web',     'label': 'YT-DLP',         'category': 'Downloads'},
    {'name': 'deemix',         'label': 'Deemix',         'category': 'Downloads'},
    {'name': 'trilium',        'label': 'Trilium',        'category': 'Tools'},
    {'name': 'stash',          'label': 'Stash',          'category': 'Tools'},
    {'name': 'dictionary-api', 'label': 'Dictionary',     'category': 'Tools'},
    {'name': 'mullvad-vpn',    'label': 'Mullvad VPN',    'category': 'Infrastructure'},
    {'name': 'dashboard',      'label': 'Dashboard',      'category': 'Infrastructure'},
]

THRESHOLDS = {
    'cpu':         {'warn': 85, 'crit': 95},
    'ram':         {'warn': 85, 'crit': 95},
    'swap':        {'warn': 50, 'crit': 75},
    'docker_disk': {'warn': 75, 'crit': 85},
    'nas_disk':    {'warn': 85, 'crit': 93},
}

_latest_status: dict = {}
_status_lock = threading.Lock()


def _init_db():
    os.makedirs('/app/data', exist_ok=True)
    con = sqlite3.connect(DB_PATH)
    con.executescript('''
        CREATE TABLE IF NOT EXISTS metrics (
            ts              INTEGER PRIMARY KEY,
            cpu_pct         REAL,
            ram_used_mb     INTEGER,
            ram_total_mb    INTEGER,
            swap_used_mb    INTEGER,
            swap_total_mb   INTEGER,
            docker_disk_pct INTEGER,
            nas_disk_pct    INTEGER
        );
        CREATE INDEX IF NOT EXISTS idx_m_ts ON metrics(ts);
        CREATE TABLE IF NOT EXISTS container_events (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            ts              INTEGER,
            container_name  TEXT,
            status          TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_ce_ts  ON container_events(ts);
        CREATE INDEX IF NOT EXISTS idx_ce_con ON container_events(container_name, ts);
    ''')
    con.commit()
    con.close()


def _read_cpu() -> float:
    """Return host CPU usage % by sampling /proc/stat twice 1 s apart."""
    def _stat():
        with open('/proc/stat') as f:
            v = list(map(int, f.readline().split()[1:]))
        return v[3] + v[4], sum(v)   # (idle+iowait, total)
    i1, t1 = _stat()
    time.sleep(1)
    i2, t2 = _stat()
    dt = t2 - t1
    return round((1 - (i2 - i1) / dt) * 100, 1) if dt else 0.0


def _read_mem() -> dict:
    """Parse /proc/meminfo for RAM and swap figures."""
    kv: dict = {}
    with open('/proc/meminfo') as f:
        for line in f:
            k, v = line.split(':')
            kv[k.strip()] = int(v.split()[0])   # values in kB
    return {
        'ram_used_mb':  (kv['MemTotal'] - kv['MemAvailable']) // 1024,
        'ram_total_mb':  kv['MemTotal']  // 1024,
        'swap_used_mb':  (kv['SwapTotal'] - kv['SwapFree']) // 1024,
        'swap_total_mb': kv['SwapTotal'] // 1024,
    }


def _read_disk(path: str) -> dict:
    try:
        st = os.statvfs(path)
        total = st.f_blocks * st.f_frsize
        avail = st.f_bavail * st.f_frsize
        used  = total - avail
        pct   = int(used / total * 100) if total else 0
        return {'used_gb': round(used / 1e9, 1), 'total_gb': round(total / 1e9, 1), 'pct': pct}
    except Exception:
        return {'used_gb': 0, 'total_gb': 0, 'pct': 0}


def _read_containers() -> list:
    """Get status of every monitored container in a single docker ps call."""
    try:
        r = subprocess.run(
            ['docker', 'ps', '-a', '--format', '{{.Names}}|{{.Status}}'],
            capture_output=True, text=True, timeout=15)
        live = {}
        for line in r.stdout.strip().splitlines():
            if '|' in line:
                n, s = line.split('|', 1)
                live[n.strip()] = s.strip()
    except Exception:
        live = {}

    out = []
    for c in MONITORED_CONTAINERS:
        raw = live.get(c['name'], '')
        if not raw:
            state, health = 'missing', None
        elif raw.lower().startswith('up'):
            state = 'running'
            health = ('unhealthy' if '(unhealthy)' in raw else
                      'healthy'   if '(healthy)'   in raw else
                      'starting'  if '(starting)'  in raw else None)
        else:
            state, health = 'stopped', None
        out.append({**c, 'state': state, 'health': health, 'raw_status': raw})
    return out


def _sev(value: float, key: str) -> str:
    t = THRESHOLDS.get(key, {})
    return ('crit' if value >= t.get('crit', 101) else
            'warn' if value >= t.get('warn', 101) else 'ok')


def _read_container_stats() -> list:
    """Per-container CPU % and memory usage via a single docker stats call."""
    try:
        r = subprocess.run(
            ['docker', 'stats', '--no-stream', '--format',
             '{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}}'],
            capture_output=True, text=True, timeout=30)
        out = []
        for line in r.stdout.strip().splitlines():
            parts = line.split(',', 3)
            if len(parts) < 4:
                continue
            name, cpu_s, mem_s, memp_s = parts
            try:
                cpu_pct  = float(cpu_s.strip().rstrip('%') or 0)
                mem_pct  = float(memp_s.strip().rstrip('%') or 0)
                mem_used = mem_s.split('/')[0].strip()
            except ValueError:
                continue
            out.append({'name': name.strip(), 'cpu_pct': round(cpu_pct, 2),
                        'mem_pct': round(mem_pct, 2), 'mem_used': mem_used})
        # Sort by CPU descending so the frontend can just slice [:N]
        out.sort(key=lambda x: x['cpu_pct'], reverse=True)
        return out
    except Exception as ex:
        logger.warning(f'docker stats error: {ex}')
        return []


def _collect() -> dict:
    cpu        = _read_cpu()
    mem        = _read_mem()
    dsk        = _read_disk('/mnt/docker')
    nas        = _read_disk('/mnt/boston')
    ctrs       = _read_containers()
    ctr_stats  = _read_container_stats()   # per-container CPU/RAM for pie charts

    ram_pct  = int(mem['ram_used_mb']  / mem['ram_total_mb']  * 100) if mem['ram_total_mb']  else 0
    swap_pct = int(mem['swap_used_mb'] / mem['swap_total_mb'] * 100) if mem['swap_total_mb'] else 0

    sevs = [_sev(cpu, 'cpu'), _sev(ram_pct, 'ram'), _sev(swap_pct, 'swap'),
            _sev(dsk['pct'], 'docker_disk'), _sev(nas['pct'], 'nas_disk')]
    ctr_problem = any(c['state'] != 'running' or c['health'] == 'unhealthy' for c in ctrs)
    overall = ('crit' if ('crit' in sevs or ctr_problem) else
               'warn' if 'warn' in sevs else 'ok')

    return {
        'ts': int(time.time()),
        'overall': overall,
        'cpu':           {'pct': cpu, 'severity': _sev(cpu, 'cpu')},
        'ram':           {'used_mb': mem['ram_used_mb'], 'total_mb': mem['ram_total_mb'],
                          'pct': ram_pct, 'severity': _sev(ram_pct, 'ram')},
        'swap':          {'used_mb': mem['swap_used_mb'], 'total_mb': mem['swap_total_mb'],
                          'pct': swap_pct, 'severity': _sev(swap_pct, 'swap')},
        'docker_disk':   {**dsk, 'severity': _sev(dsk['pct'], 'docker_disk')},
        'nas_disk':      {**nas, 'severity': _sev(nas['pct'], 'nas_disk')},
        'containers':    ctrs,
        'container_stats': ctr_stats,
        'thresholds':    THRESHOLDS,
    }


def _persist_snap(snap: dict):
    try:
        con = sqlite3.connect(DB_PATH)
        con.execute('INSERT OR REPLACE INTO metrics VALUES (?,?,?,?,?,?,?,?)', (
            snap['ts'],
            snap['cpu']['pct'],
            snap['ram']['used_mb'],  snap['ram']['total_mb'],
            snap['swap']['used_mb'], snap['swap']['total_mb'],
            snap['docker_disk']['pct'], snap['nas_disk']['pct'],
        ))
        con.execute('DELETE FROM metrics WHERE ts < ?', (snap['ts'] - 30 * 86400,))
        con.commit()
        con.close()
    except Exception as ex:
        logger.warning(f'DB write error: {ex}')


def _metrics_loop():
    _init_db()
    while True:
        try:
            snap = _collect()
            _persist_snap(snap)
            with _status_lock:
                _latest_status.clear()
                _latest_status.update(snap)
        except Exception as ex:
            logger.warning(f'Metrics collection error: {ex}')
        time.sleep(60)


# Kick off background collector immediately on startup
threading.Thread(target=_metrics_loop, daemon=True, name='metrics-collector').start()


@app.route('/api/restart/<service_id>', methods=['POST'])
def restart_container(service_id):
    """Restart a Docker container."""
    if service_id not in CONTAINERS:
        return jsonify({'error': 'Unknown service'}), 404

    container_name = CONTAINERS[service_id]['name']

    try:
        logger.info(f"Restarting container: {container_name}")
        result = subprocess.run(
            ['docker', 'restart', container_name],
            capture_output=True,
            text=True,
            timeout=30
        )

        if result.returncode == 0:
            logger.info(f"Successfully restarted {container_name}")
            return jsonify({'success': True, 'message': f'Restarted {container_name}'})
        else:
            logger.error(f"Failed to restart {container_name}: {result.stderr}")
            return jsonify({'error': result.stderr}), 500

    except subprocess.TimeoutExpired:
        return jsonify({'error': 'Restart timed out'}), 500
    except Exception as e:
        logger.error(f"Error restarting {container_name}: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/recreate/<service_id>', methods=['POST'])
def recreate_container(service_id):
    """Recreate a Docker container using docker compose."""
    if service_id not in CONTAINERS:
        return jsonify({'error': 'Unknown service'}), 404

    compose_dir = CONTAINERS[service_id]['compose_dir']
    container_name = CONTAINERS[service_id]['name']
    service_name = CONTAINERS[service_id]['service']

    try:
        logger.info(f"Recreating container: {container_name} (service: {service_name}) in {compose_dir}")
        result = subprocess.run(
            ['docker', 'compose', 'up', '-d', '--force-recreate', service_name],
            cwd=compose_dir if compose_dir.startswith('/') else f'/home/brandon/projects/docker/{compose_dir}',
            capture_output=True,
            text=True,
            timeout=120
        )

        if result.returncode == 0:
            logger.info(f"Successfully recreated {container_name}")
            return jsonify({'success': True, 'message': f'Recreated {container_name}'})
        else:
            logger.error(f"Failed to recreate {container_name}: {result.stderr}")
            return jsonify({'error': result.stderr}), 500

    except subprocess.TimeoutExpired:
        return jsonify({'error': 'Recreate timed out'}), 500
    except Exception as e:
        logger.error(f"Error recreating {container_name}: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/scan/jellyfin', methods=['POST'])
def scan_jellyfin():
    """Trigger a library scan on Jellyfin."""
    try:
        # Jellyfin API endpoint for library refresh
        # Note: This requires an API key to be configured in Jellyfin
        # Users should set the JELLYFIN_API_KEY environment variable
        api_key = os.environ.get('JELLYFIN_API_KEY', '')

        if not api_key:
            return jsonify({'error': 'JELLYFIN_API_KEY environment variable not set'}), 500

        jellyfin_url = 'http://100.123.154.40:8096'
        url = f'{jellyfin_url}/Library/Refresh?api_key={api_key}'

        logger.info(f"Triggering Jellyfin library scan")
        response = requests.post(url, timeout=10)

        if response.status_code == 204 or response.status_code == 200:
            logger.info("Successfully triggered Jellyfin library scan")
            return jsonify({'success': True, 'message': 'Jellyfin library scan started'})
        else:
            logger.error(f"Failed to trigger Jellyfin scan: {response.status_code}")
            return jsonify({'error': f'Jellyfin API returned status {response.status_code}'}), 500

    except requests.exceptions.Timeout:
        return jsonify({'error': 'Request to Jellyfin timed out'}), 500
    except Exception as e:
        logger.error(f"Error triggering Jellyfin scan: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/scan/audiobookshelf', methods=['POST'])
def scan_audiobookshelf():
    """Trigger a library scan on Audiobookshelf."""
    try:
        # Audiobookshelf API endpoint for library scan
        # Note: This requires an API token to be configured
        # Users should set the AUDIOBOOKSHELF_API_TOKEN environment variable
        api_token = os.environ.get('AUDIOBOOKSHELF_API_TOKEN', '')

        if not api_token:
            return jsonify({'error': 'AUDIOBOOKSHELF_API_TOKEN environment variable not set'}), 500

        audiobookshelf_url = 'http://100.123.154.40:13378'

        # First, get the library ID (assuming first library, or we could make this configurable)
        headers = {'Authorization': f'Bearer {api_token}'}
        libraries_url = f'{audiobookshelf_url}/api/libraries'

        logger.info(f"Getting Audiobookshelf libraries")
        libraries_response = requests.get(libraries_url, headers=headers, timeout=10)

        if libraries_response.status_code != 200:
            logger.error(f"Failed to get Audiobookshelf libraries: {libraries_response.status_code}")
            return jsonify({'error': f'Failed to get libraries: {libraries_response.status_code}'}), 500

        libraries = libraries_response.json().get('libraries', [])
        if not libraries:
            return jsonify({'error': 'No libraries found in Audiobookshelf'}), 404

        # Scan all libraries
        scan_results = []
        for library in libraries:
            library_id = library.get('id')
            scan_url = f'{audiobookshelf_url}/api/libraries/{library_id}/scan'

            logger.info(f"Triggering Audiobookshelf library scan for library {library_id}")
            scan_response = requests.post(scan_url, headers=headers, timeout=10)

            if scan_response.status_code == 200:
                scan_results.append(f"Library {library.get('name', library_id)} scan started")
            else:
                scan_results.append(f"Library {library.get('name', library_id)} scan failed")

        logger.info("Successfully triggered Audiobookshelf library scans")
        return jsonify({'success': True, 'message': ', '.join(scan_results)})

    except requests.exceptions.Timeout:
        return jsonify({'error': 'Request to Audiobookshelf timed out'}), 500
    except Exception as e:
        logger.error(f"Error triggering Audiobookshelf scan: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/tag/stash', methods=['POST'])
def tag_stash():
    """Trigger auto-tagging on Stash via its GraphQL API."""
    try:
        api_key = os.environ.get('STASH_API_KEY', '')

        if not api_key:
            return jsonify({'error': 'STASH_API_KEY environment variable not set'}), 500

        stash_url = 'http://100.123.154.40:9999'
        graphql_url = f'{stash_url}/graphql'

        headers = {
            'Content-Type': 'application/json',
            'ApiKey': api_key,
        }

        # Auto-tag all scenes against all performers, studios, and tags
        # Using ["*"] signals Stash to match everything
        query = """
        mutation MetadataAutoTag {
            metadataAutoTag(input: {performers: ["*"], studios: ["*"], tags: ["*"]})
        }
        """

        logger.info("Triggering Stash auto-tagging")
        response = requests.post(
            graphql_url,
            json={'query': query},
            headers=headers,
            timeout=10
        )

        if response.status_code == 200:
            data = response.json()
            if 'errors' in data:
                logger.error(f"Stash GraphQL errors: {data['errors']}")
                return jsonify({'error': str(data['errors'])}), 500
            logger.info("Successfully triggered Stash auto-tagging")
            return jsonify({'success': True, 'message': 'Stash auto-tagging started'})
        elif response.status_code == 401:
            return jsonify({'error': 'Authentication failed. Check STASH_API_KEY.'}), 500
        else:
            logger.error(f"Failed to trigger Stash auto-tagging: {response.status_code}")
            return jsonify({'error': f'Stash API returned status {response.status_code}'}), 500

    except requests.exceptions.Timeout:
        return jsonify({'error': 'Request to Stash timed out'}), 500
    except Exception as e:
        logger.error(f"Error triggering Stash auto-tagging: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/download/youtube', methods=['POST'])
def download_youtube():
    """Download YouTube video as MP3 audio or full video using yt-dlp."""
    try:
        data = request.get_json()
        if not data or 'url' not in data:
            return jsonify({'error': 'YouTube URL is required'}), 400

        youtube_url = data['url'].strip()
        if not youtube_url:
            return jsonify({'error': 'YouTube URL cannot be empty'}), 400

        # Basic URL validation
        if not ('youtube.com' in youtube_url or 'youtu.be' in youtube_url):
            return jsonify({'error': 'Invalid YouTube URL'}), 400

        # Get download type (default to mp3 for backward compatibility)
        download_type = data.get('type', 'mp3').lower()

        logger.info(f"Starting YouTube download ({download_type}) for URL: {youtube_url}")

        # Build yt-dlp command based on download type
        if download_type == 'video':
            # Download full video in best quality with robust retry options
            cmd = [
                'docker', 'exec', 'yt-dlp-web', 'yt-dlp',
                '--format', 'bestvideo[ext=mp4][height<=1080]+bestaudio[ext=m4a]/bestvideo[ext=mp4]+bestaudio/best[ext=mp4]/best',
                '--merge-output-format', 'mp4',
                '--add-metadata',
                '--no-part',
                '--retries', '10',
                '--fragment-retries', '10',
                '--file-access-retries', '10',
                '--output', '/downloads/video/%(title)s.%(ext)s',
                youtube_url
            ]
            success_msg = 'Video download completed! File saved to /mnt/boston/media/downloads/youtube/video/'
        else:
            # Download audio as MP3 (default)
            cmd = [
                'docker', 'exec', 'yt-dlp-web', 'yt-dlp',
                '--extract-audio',
                '--audio-format', 'mp3',
                '--audio-quality', '0',
                '--embed-thumbnail',
                '--add-metadata',
                '--parse-metadata', '%(title)s:%(meta_title)s',
                '--parse-metadata', '%(uploader)s:%(meta_artist)s',
                '--output', '/downloads/music/%(title)s.%(ext)s',
                youtube_url
            ]
            success_msg = 'MP3 download completed! File saved to /mnt/boston/media/downloads/youtube/music/'

        # Run yt-dlp inside the yt-dlp-web container
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=300  # 5 minute timeout for download
        )

        if result.returncode == 0:
            logger.info(f"Successfully downloaded YouTube {download_type}: {youtube_url}")
            return jsonify({
                'success': True,
                'message': success_msg
            })
        else:
            logger.error(f"Failed to download YouTube {download_type}: {result.stderr}")
            return jsonify({'error': f'Download failed: {result.stderr}'}), 500

    except subprocess.TimeoutExpired:
        return jsonify({'error': 'Download timed out (max 5 minutes)'}), 500
    except Exception as e:
        logger.error(f"Error downloading YouTube video: {str(e)}")
        return jsonify({'error': str(e)}), 500

def _delayed_self_command(cmd, delay=1.0):
    """Run a command after a delay in a background thread (fire-and-forget)."""
    def run():
        import time
        time.sleep(delay)
        logger.info(f"Executing delayed self-command: {' '.join(cmd)}")
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    t = threading.Thread(target=run, daemon=True)
    t.start()

@app.route('/api/self/restart', methods=['POST'])
def self_restart():
    """Restart the dashboard container itself. Returns immediately, then restarts."""
    logger.info("Self-restart requested")
    _delayed_self_command(['docker', 'restart', 'dashboard'], delay=0.5)
    return jsonify({'success': True, 'message': 'Dashboard is restarting...'})

@app.route('/api/self/recreate', methods=['POST'])
def self_recreate():
    """Recreate the dashboard container itself via a sibling container.

    We can't run 'docker compose up --force-recreate' from inside the container
    being recreated — Docker kills us before starting the replacement. Instead,
    spin up a short-lived sibling container that performs the recreate for us.
    """
    logger.info("Self-recreate requested — spawning sibling recreator container")

    def run():
        import time
        time.sleep(0.5)
        # Clean up any leftover recreator
        subprocess.run(['docker', 'rm', '-f', 'dashboard-recreator'],
                       capture_output=True, timeout=5)
        # Spawn a detached sibling container that does the actual recreate.
        # It shares the docker socket and has the dashboard source mounted.
        subprocess.Popen([
            'docker', 'run', '--rm', '-d',
            '--name', 'dashboard-recreator',
            '-v', '/var/run/docker.sock:/var/run/docker.sock',
            '-v', '/home/brandon/projects/docker/dashboard:/workspace',
            '-w', '/workspace',
            'dashboard-dashboard',
            'sh', '-c', 'sleep 1 && docker compose up -d --force-recreate --build dashboard'
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    t = threading.Thread(target=run, daemon=True)
    t.start()
    return jsonify({'success': True, 'message': 'Dashboard is recreating...'})

@app.route('/api/health', methods=['GET'])
def health():
    """Health check endpoint."""
    return jsonify({'status': 'ok'})

# --- Bookmarks Feature ---
BOOKMARKS_FILE = os.path.join(os.path.dirname(__file__), 'data', 'bookmarks.json')

def _ensure_bookmarks_dir():
    os.makedirs(os.path.dirname(BOOKMARKS_FILE), exist_ok=True)

def _load_bookmarks():
    _ensure_bookmarks_dir()
    if not os.path.exists(BOOKMARKS_FILE):
        return []
    with open(BOOKMARKS_FILE, 'r') as f:
        return json.load(f)

def _save_bookmarks(bookmarks):
    _ensure_bookmarks_dir()
    with open(BOOKMARKS_FILE, 'w') as f:
        json.dump(bookmarks, f, indent=2)

@app.route('/api/bookmarks', methods=['GET'])
def get_bookmarks():
    """Get all bookmarks."""
    return jsonify(_load_bookmarks())

@app.route('/api/bookmarks', methods=['POST'])
def add_bookmark():
    """Add a new bookmark or folder."""
    data = request.get_json()
    if not data:
        return jsonify({'error': 'Request body required'}), 400

    bookmark = {
        'id': str(uuid.uuid4()),
        'name': data.get('name', 'Untitled'),
        'url': data.get('url', ''),
        'type': data.get('type', 'bookmark'),  # 'bookmark' or 'folder'
        'parent_id': data.get('parent_id', None),
        'created': datetime.now().isoformat(),
    }

    bookmarks = _load_bookmarks()
    bookmarks.append(bookmark)
    _save_bookmarks(bookmarks)
    return jsonify(bookmark), 201

@app.route('/api/bookmarks/<bookmark_id>', methods=['PUT'])
def update_bookmark(bookmark_id):
    """Update a bookmark."""
    data = request.get_json()
    if not data:
        return jsonify({'error': 'Request body required'}), 400

    bookmarks = _load_bookmarks()
    for bm in bookmarks:
        if bm['id'] == bookmark_id:
            bm['name'] = data.get('name', bm['name'])
            bm['url'] = data.get('url', bm['url'])
            bm['parent_id'] = data.get('parent_id', bm.get('parent_id'))
            _save_bookmarks(bookmarks)
            return jsonify(bm)
    return jsonify({'error': 'Bookmark not found'}), 404

@app.route('/api/bookmarks/<bookmark_id>', methods=['DELETE'])
def delete_bookmark(bookmark_id):
    """Delete a bookmark and any children (if folder)."""
    bookmarks = _load_bookmarks()

    # Collect IDs to delete (the target + all descendants)
    def collect_ids(parent_id):
        ids = {parent_id}
        for bm in bookmarks:
            if bm.get('parent_id') == parent_id:
                ids |= collect_ids(bm['id'])
        return ids

    ids_to_delete = collect_ids(bookmark_id)
    new_bookmarks = [bm for bm in bookmarks if bm['id'] not in ids_to_delete]

    if len(new_bookmarks) == len(bookmarks):
        return jsonify({'error': 'Bookmark not found'}), 404

    _save_bookmarks(new_bookmarks)
    return jsonify({'success': True, 'deleted': len(bookmarks) - len(new_bookmarks)})

@app.route('/')
def index():
    """Serve the main dashboard page."""
    return send_from_directory('static', 'index.html')

@app.route('/bookmarks')
def bookmarks_page():
    """Serve the bookmarks page."""
    return send_from_directory('static', 'bookmarks.html')

@app.route('/server-health')
def server_health_page():
    """Serve the Server Health page."""
    return send_from_directory('static', 'infra.html')

@app.route('/api/infra/status')
def infra_status():
    """Return the latest cached infrastructure snapshot."""
    with _status_lock:
        snap = dict(_latest_status)
    if not snap:
        return jsonify({'error': 'collecting', 'overall': 'unknown'}), 202
    return jsonify(snap)

@app.route('/api/infra/history')
def infra_history():
    """Return time-series metrics from SQLite for chart rendering."""
    hours = int(request.args.get('hours', 24))
    since = int(time.time()) - hours * 3600
    try:
        con = sqlite3.connect(DB_PATH)
        rows = con.execute(
            'SELECT ts, cpu_pct, ram_used_mb, ram_total_mb, '
            '       swap_used_mb, swap_total_mb, docker_disk_pct, nas_disk_pct '
            'FROM metrics WHERE ts >= ? ORDER BY ts',
            (since,)
        ).fetchall()
        con.close()
    except Exception as ex:
        return jsonify({'error': str(ex)}), 500
    return jsonify([{
        'ts':             r[0],
        'cpu_pct':        r[1],
        'ram_pct':        int(r[2] / r[3] * 100) if r[3] else 0,
        'swap_pct':       int(r[4] / r[5] * 100) if r[5] else 0,
        'docker_disk_pct': r[6],
        'nas_disk_pct':   r[7],
    } for r in rows])

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8001, debug=False)

