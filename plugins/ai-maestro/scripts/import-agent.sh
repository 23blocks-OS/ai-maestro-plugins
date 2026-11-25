#!/bin/bash
#
# import-agent.sh - Import an agent from a portable ZIP file
#
# Usage: import-agent.sh <zip-file> [options]
#
# Options:
#   --alias <name>     Override the agent alias
#   --new-id           Generate a new agent ID
#   --skip-messages    Don't import messages
#   --overwrite        Overwrite existing agent with same alias
#
# Examples:
#   import-agent.sh backend-api-export.zip
#   import-agent.sh backend-api-export.zip --alias backend-api-v2
#   import-agent.sh backend-api-export.zip --new-id --overwrite
#

set -e

# Configuration - detect API URL if not set
if [ -z "$AIMAESTRO_API" ]; then
    # Try identity API first
    AIMAESTRO_API=$(curl -s --max-time 5 "http://127.0.0.1:23000/api/hosts/identity" | jq -r '.host.url // empty' 2>/dev/null)
    if [ -z "$AIMAESTRO_API" ]; then
        # Fallback to hostname
        AIMAESTRO_API="http://$(hostname | tr '[:upper:]' '[:lower:]'):23000"
    fi
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Show usage
show_usage() {
    echo "Usage: import-agent.sh <zip-file> [options]"
    echo ""
    echo "Import an AI Maestro agent from a portable ZIP file."
    echo ""
    echo "Arguments:"
    echo "  zip-file           Path to the agent export ZIP file"
    echo ""
    echo "Options:"
    echo "  --alias <name>     Override the agent alias"
    echo "  --new-id           Generate a new agent ID instead of keeping original"
    echo "  --skip-messages    Don't import messages"
    echo "  --overwrite        Overwrite existing agent with same alias"
    echo ""
    echo "Examples:"
    echo "  import-agent.sh backend-api-export.zip"
    echo "  import-agent.sh backend-api-export.zip --alias backend-api-v2"
    echo "  import-agent.sh backend-api-export.zip --new-id --overwrite"
    echo ""
    echo "Environment Variables:"
    echo "  AIMAESTRO_API  API endpoint (auto-detected from running instance)"
}

# Parse arguments
ZIP_FILE=""
NEW_ALIAS=""
NEW_ID="false"
SKIP_MESSAGES="false"
OVERWRITE="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        --alias)
            NEW_ALIAS="$2"
            shift 2
            ;;
        --new-id)
            NEW_ID="true"
            shift
            ;;
        --skip-messages)
            SKIP_MESSAGES="true"
            shift
            ;;
        --overwrite)
            OVERWRITE="true"
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        -*)
            echo -e "${RED}Error: Unknown option $1${NC}"
            echo ""
            show_usage
            exit 1
            ;;
        *)
            if [ -z "$ZIP_FILE" ]; then
                ZIP_FILE="$1"
            else
                echo -e "${RED}Error: Unexpected argument $1${NC}"
                echo ""
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Check arguments
if [ -z "$ZIP_FILE" ]; then
    echo -e "${RED}Error: ZIP file is required${NC}"
    echo ""
    show_usage
    exit 1
fi

# Expand ~ in path
ZIP_FILE="${ZIP_FILE/#\~/$HOME}"

# Check file exists
if [ ! -f "$ZIP_FILE" ]; then
    echo -e "${RED}Error: File not found: $ZIP_FILE${NC}"
    exit 1
fi

# Check it's a ZIP file
if ! file "$ZIP_FILE" | grep -q "Zip archive"; then
    echo -e "${RED}Error: Not a valid ZIP file: $ZIP_FILE${NC}"
    exit 1
fi

echo -e "${BLUE}Importing agent from: ${YELLOW}$ZIP_FILE${NC}"

# Show manifest preview
echo ""
echo -e "${BLUE}Package Contents:${NC}"
if command -v unzip &> /dev/null; then
    MANIFEST=$(unzip -p "$ZIP_FILE" manifest.json 2>/dev/null || echo "{}")
    if [ ! -z "$MANIFEST" ] && [ "$MANIFEST" != "{}" ]; then
        echo "$MANIFEST" | jq -r '
            "  Agent: \(.agent.alias // "Unknown") (\((.agent.id // "Unknown")[0:8])...)",
            "  Display Name: \(.agent.displayName // "N/A")",
            "  Exported: \(.exportedAt // "Unknown")",
            "  From: \(.exportedFrom.hostname // "Unknown") (\(.exportedFrom.platform // "Unknown"))",
            "  Database: \(if .contents.hasDatabase then "Yes" else "No" end)",
            (.contents.messageStats // {}) as $s
            | if .contents.hasMessages then "  Messages: \(($s.inbox // 0) + ($s.sent // 0) + ($s.archived // 0)) total (\($s.inbox // 0) inbox, \($s.sent // 0) sent, \($s.archived // 0) archived)" else "  Messages: None" end
        ' 2>/dev/null || echo "  (Could not parse manifest)"
    fi
fi

# Build options JSON
OPTIONS_JSON="{\"newId\":$NEW_ID,\"skipMessages\":$SKIP_MESSAGES,\"overwrite\":$OVERWRITE"
if [ ! -z "$NEW_ALIAS" ]; then
    OPTIONS_JSON="$OPTIONS_JSON,\"newAlias\":\"$NEW_ALIAS\""
fi
OPTIONS_JSON="$OPTIONS_JSON}"

echo ""
echo -e "${BLUE}Import Options:${NC}"
[ "$NEW_ALIAS" != "" ] && echo -e "  New Alias: ${YELLOW}$NEW_ALIAS${NC}"
[ "$NEW_ID" = "true" ] && echo -e "  Generate New ID: ${YELLOW}Yes${NC}"
[ "$SKIP_MESSAGES" = "true" ] && echo -e "  Skip Messages: ${YELLOW}Yes${NC}"
[ "$OVERWRITE" = "true" ] && echo -e "  Overwrite Existing: ${YELLOW}Yes${NC}"

echo ""
echo -e "${BLUE}Uploading to AI Maestro...${NC}"

# Make API request with multipart form data
RESPONSE=$(curl -s \
    -X POST \
    -F "file=@$ZIP_FILE" \
    -F "options=$OPTIONS_JSON" \
    "${AIMAESTRO_API}/api/agents/import")

# Parse response
SUCCESS=$(echo "$RESPONSE" | jq -r '.success // false' 2>/dev/null || echo "false")

if [ "$SUCCESS" = "True" ] || [ "$SUCCESS" = "true" ]; then
    echo ""
    echo -e "${GREEN}Import successful!${NC}"

    # Show imported agent details
    echo "$RESPONSE" | jq -r '
        (.agent // {}) as $a | (.stats // {}) as $st | (.stats.messagesImported // {}) as $m
        | "\nImported Agent:",
          "  ID: \($a.id // "Unknown")",
          "  Alias: \($a.alias // "Unknown")",
          "  Display Name: \($a.displayName // "N/A")",
          "  Program: \($a.program // "Unknown")",
          "\nImport Stats:",
          "  Registry: \(if $st.registryImported then "Yes" else "No" end)",
          "  Database: \(if $st.databaseImported then "Yes" else "No" end)",
          (($m.inbox // 0) + ($m.sent // 0) + ($m.archived // 0)) as $t
          | (if $t > 0 then "  Messages: \($t) (\($m.inbox // 0) inbox, \($m.sent // 0) sent, \($m.archived // 0) archived)" else empty end),
          (if ((.warnings // []) | length) > 0 then "\nWarnings:", ((.warnings // [])[] | "  - \(.)") else empty end)
    ' 2>/dev/null || true

    echo ""
    echo -e "${GREEN}The agent is now available in AI Maestro.${NC}"
    echo -e "You can create a session for it or link it to an existing tmux session."

else
    echo ""
    echo -e "${RED}Import failed!${NC}"

    # Show error details
    echo "$RESPONSE" | jq -r '
        if ((.errors // []) | length) > 0 then "Errors:", ((.errors)[] | "  - \(.)")
        else "Error: \(.error // "Unknown error")",
             (if .existingAgentId then "\nExisting agent ID: \(.existingAgentId)", "Use --overwrite to replace, or --alias to use a different name." else empty end)
        end
    ' 2>/dev/null || echo "Error: Could not parse server response"

    exit 1
fi
