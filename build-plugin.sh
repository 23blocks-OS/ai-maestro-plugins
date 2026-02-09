#!/bin/bash
# build-plugin.sh — Assemble an AI Maestro plugin from sources
#
# Reads plugin.manifest.json, fetches external sources, merges everything
# into the output directory (plugins/ai-maestro/).
#
# Usage:
#   ./build-plugin.sh              # Build from manifest
#   ./build-plugin.sh --clean      # Clean output and rebuild
#   ./build-plugin.sh --dry-run    # Show what would be done
#
# The output directory is a complete, self-contained Claude Code plugin
# ready for /install. It's committed to the repo so users get a working
# plugin without needing to run the build.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$SCRIPT_DIR/plugin.manifest.json"
CACHE_DIR="$SCRIPT_DIR/.build-cache"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Parse args
CLEAN=false
DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --clean) CLEAN=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help)
            echo "Usage: ./build-plugin.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --clean     Remove output dir and rebuild from scratch"
            echo "  --dry-run   Show what would be done without doing it"
            echo "  -h, --help  Show this help"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required. Install with: brew install jq${NC}"
    exit 1
fi

if ! command -v git &> /dev/null; then
    echo -e "${RED}Error: git is required.${NC}"
    exit 1
fi

# Read manifest
if [ ! -f "$MANIFEST" ]; then
    echo -e "${RED}Error: plugin.manifest.json not found${NC}"
    exit 1
fi

PLUGIN_NAME=$(jq -r '.name' "$MANIFEST")
PLUGIN_VERSION=$(jq -r '.version' "$MANIFEST")
OUTPUT_DIR="$SCRIPT_DIR/$(jq -r '.output' "$MANIFEST")"
SOURCE_COUNT=$(jq '.sources | length' "$MANIFEST")

echo ""
echo -e "${CYAN}Building ${PLUGIN_NAME} v${PLUGIN_VERSION}${NC}"
echo -e "${CYAN}Sources: ${SOURCE_COUNT}${NC}"
echo -e "${CYAN}Output:  ${OUTPUT_DIR}${NC}"
echo ""

# Clean if requested
if [ "$CLEAN" = true ]; then
    echo -e "${YELLOW}Cleaning output directory...${NC}"
    if [ "$DRY_RUN" = false ]; then
        rm -rf "$OUTPUT_DIR"
        rm -rf "$CACHE_DIR"
    fi
    echo -e "${GREEN}Cleaned${NC}"
fi

# Create output structure
if [ "$DRY_RUN" = false ]; then
    mkdir -p "$OUTPUT_DIR/.claude-plugin"
    mkdir -p "$OUTPUT_DIR/skills"
    mkdir -p "$OUTPUT_DIR/scripts"
    mkdir -p "$OUTPUT_DIR/hooks"
    mkdir -p "$CACHE_DIR"
fi

# Generate plugin.json from manifest
echo "Generating plugin.json..."
if [ "$DRY_RUN" = false ]; then
    jq '.plugin' "$MANIFEST" > "$OUTPUT_DIR/.claude-plugin/plugin.json"
fi

# Process each source
for i in $(seq 0 $((SOURCE_COUNT - 1))); do
    SOURCE_NAME=$(jq -r ".sources[$i].name" "$MANIFEST")
    SOURCE_TYPE=$(jq -r ".sources[$i].type" "$MANIFEST")
    SOURCE_DESC=$(jq -r ".sources[$i].description // empty" "$MANIFEST")

    echo -e "${CYAN}[$((i + 1))/$SOURCE_COUNT] ${SOURCE_NAME}${NC} (${SOURCE_TYPE})"
    [ -n "$SOURCE_DESC" ] && echo "  $SOURCE_DESC"

    SOURCE_DIR=""

    case "$SOURCE_TYPE" in
        local)
            SOURCE_PATH=$(jq -r ".sources[$i].path" "$MANIFEST")
            SOURCE_DIR="$SCRIPT_DIR/$SOURCE_PATH"

            if [ ! -d "$SOURCE_DIR" ]; then
                echo -e "${RED}  Error: local source not found: $SOURCE_PATH${NC}"
                exit 1
            fi
            echo -e "  Source: ${SOURCE_PATH}"
            ;;

        git)
            REPO_URL=$(jq -r ".sources[$i].repo" "$MANIFEST")
            REPO_REF=$(jq -r ".sources[$i].ref // \"main\"" "$MANIFEST")

            # Cache directory based on source name
            CLONE_DIR="$CACHE_DIR/$SOURCE_NAME"

            if [ "$DRY_RUN" = false ]; then
                if [ -d "$CLONE_DIR/.git" ]; then
                    echo "  Updating cached clone..."
                    git -C "$CLONE_DIR" fetch origin "$REPO_REF" --quiet 2>/dev/null
                    git -C "$CLONE_DIR" checkout "origin/$REPO_REF" --quiet 2>/dev/null || \
                        git -C "$CLONE_DIR" checkout "$REPO_REF" --quiet 2>/dev/null
                else
                    echo "  Cloning $REPO_URL ($REPO_REF)..."
                    git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$CLONE_DIR" --quiet
                fi
            fi

            SOURCE_DIR="$CLONE_DIR"
            echo -e "  Source: ${REPO_URL} @ ${REPO_REF}"
            ;;

        *)
            echo -e "${RED}  Error: unknown source type: $SOURCE_TYPE${NC}"
            exit 1
            ;;
    esac

    # Process mappings — iterate via jq index to avoid glob expansion
    MAP_COUNT=$(jq ".sources[$i].map | length" "$MANIFEST")

    for mi in $(seq 0 $((MAP_COUNT - 1))); do
        src_pattern=$(jq -r ".sources[$i].map | keys[$mi]" "$MANIFEST")
        [ -z "$src_pattern" ] && continue
        dst_pattern=$(jq -r ".sources[$i].map[\"$src_pattern\"]" "$MANIFEST")
        dst_full="$OUTPUT_DIR/$dst_pattern"

        if [ "$DRY_RUN" = true ]; then
            echo "  Map: $src_pattern -> $dst_pattern"
            continue
        fi

        # Case 1: Direct directory to directory (e.g., "skills/messaging" -> "skills/agent-messaging")
        if [ -d "$SOURCE_DIR/$src_pattern" ] && [[ "$dst_pattern" != */ ]]; then
            mkdir -p "$(dirname "$dst_full")"
            cp -r "$SOURCE_DIR/$src_pattern" "$dst_full"
            echo -e "  ${GREEN}Copied dir: $src_pattern -> $dst_pattern${NC}"
            continue
        fi

        # Case 2: Glob pattern (contains *) to directory (ends with /)
        # e.g., "scripts/*.sh" -> "scripts/" or "skills/*" -> "skills/"
        if [[ "$src_pattern" == *'*'* ]]; then
            mkdir -p "$dst_full"
            file_count=0
            # Expand glob safely using a subshell
            while IFS= read -r f; do
                [ -z "$f" ] && continue
                cp -r "$f" "$dst_full"
                file_count=$((file_count + 1))
            done < <(bash -c "for f in $SOURCE_DIR/$src_pattern; do [ -e \"\$f\" ] && echo \"\$f\"; done" 2>/dev/null)
            echo -e "  ${GREEN}Copied $file_count items: $src_pattern -> $dst_pattern${NC}"
            continue
        fi

        # Case 3: Single file
        if [ -f "$SOURCE_DIR/$src_pattern" ]; then
            mkdir -p "$(dirname "$dst_full")"
            cp "$SOURCE_DIR/$src_pattern" "$dst_full"
            echo -e "  ${GREEN}Copied: $src_pattern -> $dst_pattern${NC}"
            continue
        fi

        echo -e "  ${YELLOW}Warning: no match for $src_pattern${NC}"
    done

    echo ""
done

# Generate README for the built plugin
if [ "$DRY_RUN" = false ]; then
    SKILL_COUNT=$(find "$OUTPUT_DIR/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
    SCRIPT_COUNT=$(find "$OUTPUT_DIR/scripts" -type f 2>/dev/null | wc -l | tr -d ' ')

    cat > "$OUTPUT_DIR/README.md" << EOF
# AI Maestro Plugin

Built from plugin.manifest.json with $SOURCE_COUNT sources.

**Skills:** $SKILL_COUNT | **Scripts:** $SCRIPT_COUNT

Built at: $(date -u +%Y-%m-%dT%H:%M:%SZ)

See the [main repo](https://github.com/23blocks-OS/ai-maestro-plugins) for source files and build instructions.
EOF
fi

# Summary
if [ "$DRY_RUN" = false ]; then
    SKILL_COUNT=$(find "$OUTPUT_DIR/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
    SCRIPT_COUNT=$(find "$OUTPUT_DIR/scripts" -type f 2>/dev/null | wc -l | tr -d ' ')
    HOOK_COUNT=$([ -f "$OUTPUT_DIR/hooks/hooks.json" ] && echo "1" || echo "0")

    echo "═══════════════════════════════════════"
    echo -e "${GREEN}Build complete!${NC}"
    echo ""
    echo -e "  Plugin:  ${CYAN}${PLUGIN_NAME} v${PLUGIN_VERSION}${NC}"
    echo -e "  Skills:  ${SKILL_COUNT}"
    echo -e "  Scripts: ${SCRIPT_COUNT}"
    echo -e "  Hooks:   ${HOOK_COUNT}"
    echo -e "  Output:  ${OUTPUT_DIR}"
    echo ""
    echo "  Skills:"
    for skill_dir in "$OUTPUT_DIR/skills"/*/; do
        [ -d "$skill_dir" ] && echo "    - $(basename "$skill_dir")"
    done
    echo ""
    echo "═══════════════════════════════════════"
else
    echo -e "${YELLOW}Dry run complete — no files were modified${NC}"
fi
