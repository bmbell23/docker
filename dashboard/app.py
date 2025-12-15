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
    'kavita': {'name': 'kavita', 'compose_dir': 'kavita'},
    'audiobookshelf': {'name': 'audiobookshelf', 'compose_dir': 'audiobookshelf'},
    'navidrome': {'name': 'navidrome', 'compose_dir': 'navidrome'},
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
    'beets': {'name': 'beets', 'compose_dir': 'beets'},
    'stash': {'name': 'stash', 'compose_dir': 'stash'},
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

