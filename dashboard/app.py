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
import requests

app = Flask(__name__, static_folder='static')
CORS(app)  # Enable CORS for frontend requests

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Container mappings: service_id -> {container_name, compose_dir}
CONTAINERS = {
    # Media
    'immich': {'name': 'immich_server', 'compose_dir': 'immich-main'},
    'jellyfin': {'name': 'jellyfin', 'compose_dir': 'jellyfin'},
    'audiobookshelf': {'name': 'audiobookshelf', 'compose_dir': 'audiobookshelf'},
    'romm': {'name': 'romm', 'compose_dir': 'romm'},

    # Downloads
    'qbittorrent': {'name': 'qbittorrent', 'compose_dir': 'torrents'},
    'jackett': {'name': 'jackett', 'compose_dir': 'jackett'},
    'ytdlp': {'name': 'yt-dlp-web', 'compose_dir': 'ytd'},

    # Forge Apps
    'lifeforge': {'name': 'lifeforge_app', 'compose_dir': 'lifeforge'},
    'artforge': {'name': 'artforge', 'compose_dir': 'artforge'},
    'wordforge': {'name': 'wordforge', 'compose_dir': 'wordforge'},
    'codeforge': {'name': 'codeforge_app', 'compose_dir': 'codeforge'},

    # Reading
    'greatreads-prod': {'name': 'greatreads_app', 'compose_dir': 'greatreads'},
    'greatreads-dev': {'name': 'greatreads_dev', 'compose_dir': 'greatreads'},

    # Tools
    'stash': {'name': 'stash', 'compose_dir': 'stash'},
    'outline': {'name': 'outline', 'compose_dir': 'outline'},
}

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
    """Recreate a Docker container using docker-compose."""
    if service_id not in CONTAINERS:
        return jsonify({'error': 'Unknown service'}), 404

    compose_dir = CONTAINERS[service_id]['compose_dir']
    container_name = CONTAINERS[service_id]['name']

    try:
        logger.info(f"Recreating container: {container_name} in {compose_dir}")
        result = subprocess.run(
            ['docker-compose', 'up', '-d', '--force-recreate', container_name],
            cwd=f'/home/brandon/projects/docker/{compose_dir}',
            capture_output=True,
            text=True,
            timeout=60
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

@app.route('/api/download/youtube', methods=['POST'])
def download_youtube():
    """Download YouTube video as MP3 audio using yt-dlp."""
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

        logger.info(f"Starting YouTube download for URL: {youtube_url}")

        # Run yt-dlp inside the yt-dlp-web container
        # This downloads audio as MP3 with metadata
        result = subprocess.run(
            [
                'docker', 'exec', 'yt-dlp-web', 'yt-dlp',
                '--extract-audio',
                '--audio-format', 'mp3',
                '--audio-quality', '0',
                '--embed-thumbnail',
                '--add-metadata',
                '--parse-metadata', '%(title)s:%(meta_title)s',
                '--parse-metadata', '%(uploader)s:%(meta_artist)s',
                '--output', '/downloads/%(title)s.%(ext)s',
                youtube_url
            ],
            capture_output=True,
            text=True,
            timeout=300  # 5 minute timeout for download
        )

        if result.returncode == 0:
            logger.info(f"Successfully downloaded YouTube video: {youtube_url}")
            return jsonify({
                'success': True,
                'message': 'YouTube download completed! File saved to /mnt/boston/media/downloads/youtube'
            })
        else:
            logger.error(f"Failed to download YouTube video: {result.stderr}")
            return jsonify({'error': f'Download failed: {result.stderr}'}), 500

    except subprocess.TimeoutExpired:
        return jsonify({'error': 'Download timed out (max 5 minutes)'}), 500
    except Exception as e:
        logger.error(f"Error downloading YouTube video: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/health', methods=['GET'])
def health():
    """Health check endpoint."""
    return jsonify({'status': 'ok'})

@app.route('/')
def index():
    """Serve the main dashboard page."""
    return send_from_directory('static', 'index.html')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)

