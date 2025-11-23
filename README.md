# Docker Containers

This repository contains Docker Compose configurations for various containers running on the Docker host.

## Structure

Each container/service has its own subdirectory:

- `immich-main/` - Main Immich photo management instance
- *(more containers to be added)*

## Version Management

This repo uses semantic versioning tracked in `version.txt`. Use the `gvc` function to commit with version bumps:

```bash
# Auto-increment patch version
gvc "your commit message"

# Specify version manually
gvc 1.2.0 "your commit message"
```

## General Guidelines

- Each container should have its own directory
- Include a `.env.template` file (never commit actual `.env` files with secrets)
- Include a `README.md` documenting the specific container setup
- Use `.gitignore` to exclude data directories and secrets
