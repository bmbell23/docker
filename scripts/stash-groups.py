#!/usr/bin/env python3
"""
stash-groups.py — Create/update Stash Groups from video subdirectories.

For every subdirectory under the watched video paths that contains 2+ scenes,
this script creates a Stash Group (if one doesn't already exist) and associates
all scenes in that folder with it.

Top-level dirs (Full, Short, Media) are NOT made into groups — only subdirs within them.
"""

import json, sys, requests, logging
from pathlib import PurePosixPath

STASH_URL = "http://localhost:9999/graphql"
LOG_FILE   = "/home/brandon/projects/docker/logs/stash-groups.log"

# Video root dirs to process — top-level names here are skipped as group names
VIDEO_ROOTS = {"/data/Videos/Full", "/data/Videos/Short", "/data/Videos/Media"}

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[logging.FileHandler(LOG_FILE), logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger()


def gql(query, variables=None):
    payload = {"query": query}
    if variables:
        payload["variables"] = variables
    r = requests.post(STASH_URL, json=payload, timeout=30)
    r.raise_for_status()
    data = r.json()
    if "errors" in data:
        raise RuntimeError(data["errors"])
    return data["data"]


def get_all_scenes():
    """Return list of {id, path} for every scene, paginated."""
    scenes = []
    page = 1
    while True:
        result = gql("""
            query FindScenes($filter: FindFilterType) {
                findScenes(filter: $filter) {
                    count
                    scenes { id files { path } }
                }
            }
        """, {"filter": {"page": page, "per_page": 100}})
        batch = result["findScenes"]["scenes"]
        scenes.extend(batch)
        if len(scenes) >= result["findScenes"]["count"]:
            break
        page += 1
    return scenes


def get_existing_groups():
    """Return dict of {name_lower: group_id}."""
    result = gql("""
        query {
            findGroups(filter: {per_page: 200}) {
                groups { id name }
            }
        }
    """)
    return {g["name"].lower(): g["id"] for g in result["findGroups"]["groups"]}


def create_group(name):
    result = gql("""
        mutation CreateGroup($input: GroupCreateInput!) {
            groupCreate(input: $input) { id }
        }
    """, {"input": {"name": name}})
    return result["groupCreate"]["id"]


def assign_scenes_to_group(group_id, scene_ids):
    """Add scenes to a group, preserving any existing group associations."""
    for idx, scene_id in enumerate(scene_ids, start=1):
        gql("""
            mutation UpdateScene($input: SceneUpdateInput!) {
                sceneUpdate(input: $input) { id }
            }
        """, {"input": {
            "id": scene_id,
            "groups": [{"group_id": group_id, "scene_index": idx}]
        }})


def folder_group_name(path_str):
    """
    Return the group name for a scene path, or None if it lives directly
    in a top-level root (no subfolder to name).
    e.g. /data/Videos/Full/BangBros/ep1.mp4  → 'BangBros'
         /data/Videos/Full/ep1.mp4           → None
    """
    p = PurePosixPath(path_str)
    parent = str(p.parent)
    if parent in VIDEO_ROOTS:
        return None
    # Walk up until we find the first dir that is one level inside a root
    for root in VIDEO_ROOTS:
        try:
            rel = PurePosixPath(parent).relative_to(root)
            parts = rel.parts
            if parts:
                return parts[0]  # immediate subdirectory name
        except ValueError:
            continue
    return None


def main():
    log.info("=== Stash Groups sync started ===")

    scenes = get_all_scenes()
    log.info(f"Found {len(scenes)} total scenes")

    # Group scenes by their folder group name
    folder_map: dict[str, list[str]] = {}
    for scene in scenes:
        for f in scene["files"]:
            name = folder_group_name(f["path"])
            if name:
                folder_map.setdefault(name, [])
                if scene["id"] not in folder_map[name]:
                    folder_map[name].append(scene["id"])

    if not folder_map:
        log.info("No subdirectory groups found — all scenes are in root video dirs")
        log.info("=== Done ===")
        return

    existing = get_existing_groups()
    created = updated = 0

    for name, scene_ids in sorted(folder_map.items()):
        if len(scene_ids) < 2:
            log.info(f"  Skipping '{name}' — only {len(scene_ids)} scene(s)")
            continue

        if name.lower() in existing:
            group_id = existing[name.lower()]
            log.info(f"  Updating existing group '{name}' (id={group_id}) with {len(scene_ids)} scenes")
            updated += 1
        else:
            group_id = create_group(name)
            log.info(f"  Created new group '{name}' (id={group_id}) with {len(scene_ids)} scenes")
            created += 1

        assign_scenes_to_group(group_id, scene_ids)

    log.info(f"=== Done — {created} groups created, {updated} updated ===")


if __name__ == "__main__":
    main()
