#!/bin/bash

# Pre-migration verification script
# Checks if system is ready for Snap to Native Docker migration

BACKUP_DIR="/home/brandon/docker-migration-backup"
PROJECT_DIR="/home/brandon/projects/docker"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

check_pass() {
    echo -e "${GREEN}✅ PASS:${NC} $1"
    ((CHECKS_PASSED++))
}

check_fail() {
    echo -e "${RED}❌ FAIL:${NC} $1"
    ((CHECKS_FAILED++))
}

check_warn() {
    echo -e "${YELLOW}⚠️  WARN:${NC} $1"
    ((CHECKS_WARNING++))
}

echo "=========================================="
echo "Docker Migration Readiness Check"
echo "=========================================="
echo ""

echo "${BLUE}Checking Docker installations...${NC}"

# Check Snap Docker
if snap list docker &>/dev/null; then
    check_pass "Snap Docker is installed"
    SNAP_VERSION=$(snap list docker | grep docker | awk '{print $2}')
    echo "  Version: $SNAP_VERSION"
else
    check_fail "Snap Docker is not installed"
fi

# Check native Docker
if dpkg -l | grep -q docker.io; then
    check_pass "Native Docker (docker.io) is installed"
    NATIVE_VERSION=$(dpkg -l | grep docker.io | awk '{print $3}')
    echo "  Version: $NATIVE_VERSION"
else
    check_fail "Native Docker (docker.io) is not installed"
fi

echo ""
echo "${BLUE}Checking Docker daemons...${NC}"

# Check Snap Docker daemon
if systemctl is-active --quiet snap.docker.dockerd.service; then
    check_pass "Snap Docker daemon is running"
    SNAP_PID=$(pgrep -f "snap.docker.dockerd" || echo "Unknown")
    echo "  PID: $SNAP_PID"
else
    check_warn "Snap Docker daemon is not running"
fi

# Check native Docker daemon
if systemctl is-active --quiet docker.service; then
    check_warn "Native Docker daemon is running (should be stopped before migration)"
    NATIVE_PID=$(pgrep -f "/usr/bin/dockerd" || echo "Unknown")
    echo "  PID: $NATIVE_PID"
else
    check_pass "Native Docker daemon is stopped (good for migration)"
fi

echo ""
echo "${BLUE}Checking containers...${NC}"

CONTAINER_COUNT=$(docker ps -q | wc -l)
if [ "$CONTAINER_COUNT" -gt 0 ]; then
    check_pass "Found $CONTAINER_COUNT running containers"
else
    check_warn "No running containers found"
fi

echo ""
echo "${BLUE}Checking docker-compose files...${NC}"

COMPOSE_COUNT=$(find "$PROJECT_DIR" -name "docker-compose.yml" 2>/dev/null | wc -l)
if [ "$COMPOSE_COUNT" -gt 0 ]; then
    check_pass "Found $COMPOSE_COUNT docker-compose.yml files"
else
    check_fail "No docker-compose.yml files found"
fi

echo ""
echo "${BLUE}Checking backup...${NC}"

if [ -d "$BACKUP_DIR" ]; then
    check_pass "Backup directory exists: $BACKUP_DIR"
    
    if [ -f "$BACKUP_DIR/inventory.txt" ]; then
        check_pass "Backup inventory found"
        BACKUP_DATE=$(stat -c %y "$BACKUP_DIR/inventory.txt" | cut -d' ' -f1)
        echo "  Backup date: $BACKUP_DATE"
    else
        check_fail "Backup inventory not found - run backup script first"
    fi
    
    BACKUP_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
    echo "  Backup size: $BACKUP_SIZE"
else
    check_fail "Backup directory not found - run backup script first"
fi

echo ""
echo "${BLUE}Checking disk space...${NC}"

SNAP_USAGE=$(df -h /var/snap/docker 2>/dev/null | tail -1 | awk '{print $5}' || echo "N/A")
NATIVE_USAGE=$(df -h /var/lib/docker 2>/dev/null | tail -1 | awk '{print $5}' || echo "N/A")
ROOT_AVAILABLE=$(df -h / | tail -1 | awk '{print $4}')

echo "  Snap Docker usage: $SNAP_USAGE"
echo "  Native Docker usage: $NATIVE_USAGE"
echo "  Root partition available: $ROOT_AVAILABLE"

if [ "$ROOT_AVAILABLE" != "N/A" ]; then
    check_pass "Sufficient disk space available"
else
    check_warn "Could not determine disk space"
fi

echo ""
echo "${BLUE}Checking git status...${NC}"

cd "$PROJECT_DIR"
if git status &>/dev/null; then
    UNCOMMITTED=$(git status --porcelain | wc -l)
    if [ "$UNCOMMITTED" -eq 0 ]; then
        check_pass "All changes committed to git"
    else
        check_warn "$UNCOMMITTED uncommitted changes in git"
        echo "  Run: git status"
    fi
else
    check_warn "Not a git repository or git not available"
fi

echo ""
echo "${BLUE}Checking critical scripts...${NC}"

SCRIPTS=(
    "scripts/backup-before-migration.sh"
    "scripts/migrate-snap-to-native.sh"
    "scripts/rollback-migration.sh"
    "scripts/fix-all-docker-iptables.sh"
)

for script in "${SCRIPTS[@]}"; do
    if [ -f "$PROJECT_DIR/$script" ]; then
        if [ -x "$PROJECT_DIR/$script" ]; then
            check_pass "Script exists and is executable: $script"
        else
            check_warn "Script exists but not executable: $script"
            echo "  Run: chmod +x $PROJECT_DIR/$script"
        fi
    else
        check_fail "Script not found: $script"
    fi
done

echo ""
echo "=========================================="
echo "SUMMARY"
echo "=========================================="
echo -e "${GREEN}Passed:${NC}   $CHECKS_PASSED"
echo -e "${YELLOW}Warnings:${NC} $CHECKS_WARNING"
echo -e "${RED}Failed:${NC}   $CHECKS_FAILED"
echo ""

if [ "$CHECKS_FAILED" -eq 0 ]; then
    echo -e "${GREEN}✅ System is ready for migration!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Review backup: cat $BACKUP_DIR/inventory.txt"
    echo "  2. When ready: sudo $PROJECT_DIR/scripts/migrate-snap-to-native.sh"
    exit 0
else
    echo -e "${RED}❌ System is NOT ready for migration${NC}"
    echo ""
    echo "Fix the failed checks above before proceeding."
    exit 1
fi

