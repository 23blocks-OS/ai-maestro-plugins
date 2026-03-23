#!/bin/bash
# Sync AMP scripts and skills from the claude-plugin submodule
#
# Usage:
#   ./scripts/sync-amp-plugin.sh          # Sync from current submodule state
#   ./scripts/sync-amp-plugin.sh --pull   # Pull latest from upstream first
#
# The agentmessaging/claude-plugin submodule lives at:
#   plugins/ai-maestro/amp-plugin/
#
# This script copies AMP scripts and skills into the expected paths
# so the installer and all platforms (macOS, Linux, WSL) work without symlinks.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUBMODULE="$REPO_ROOT/plugins/ai-maestro/amp-plugin"
TARGET_SCRIPTS="$REPO_ROOT/plugins/ai-maestro/scripts"
TARGET_SKILLS="$REPO_ROOT/plugins/ai-maestro/skills"

if [ ! -d "$SUBMODULE" ]; then
    echo "Error: Submodule not found at $SUBMODULE"
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

# Optionally pull latest from upstream
if [ "$1" = "--pull" ]; then
    echo "Pulling latest from upstream..."
    cd "$SUBMODULE"
    git fetch origin
    git checkout main
    git pull origin main
    cd "$REPO_ROOT"
    echo ""
fi

# Show upstream version
UPSTREAM_VERSION=$(cd "$SUBMODULE" && git describe --tags 2>/dev/null || git -C "$SUBMODULE" log --oneline -1)
echo "Syncing from claude-plugin: $UPSTREAM_VERSION"

# Sync AMP scripts
echo ""
echo "Syncing AMP scripts..."
count=0
for f in "$SUBMODULE"/scripts/amp-*.sh; do
    base=$(basename "$f")
    cp "$f" "$TARGET_SCRIPTS/$base"
    count=$((count + 1))
done
echo "  Copied $count AMP scripts"

# Sync agent-messaging skill
echo ""
echo "Syncing agent-messaging skill..."
rm -rf "$TARGET_SKILLS/agent-messaging"
cp -r "$SUBMODULE/skills/agent-messaging" "$TARGET_SKILLS/agent-messaging"
echo "  Done"

echo ""
echo "Sync complete. Don't forget to commit the updated files."
