#!/bin/bash
#
# list-agents.sh - List all agents available for export
#
# Usage: list-agents.sh [--json]
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
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check for --json flag
if [ "$1" = "--json" ]; then
    curl -s "${AIMAESTRO_API}/api/agents" | jq . 2>/dev/null || curl -s "${AIMAESTRO_API}/api/agents"
    exit 0
fi

echo -e "${BLUE}AI Maestro Agents${NC}"
echo -e "${BLUE}=================${NC}"
echo ""

# Get agents
RESPONSE=$(curl -s "${AIMAESTRO_API}/api/agents")

# Check if response is valid
if [ -z "$RESPONSE" ] || [ "$RESPONSE" = "null" ]; then
    echo -e "${RED}Error: Could not connect to AI Maestro API at $AIMAESTRO_API${NC}"
    echo -e "Make sure AI Maestro is running."
    exit 1
fi

# Parse and display agents
# jq, not python3: AI Maestro needs jq already, and Windows has no python3 (F041)
echo "$RESPONSE" | jq -r '
  (.agents // []) as $agents
  | if ($agents | length) == 0 then
      "No agents found.\n\nRegister agents using the AI Maestro dashboard or:\n  POST /api/agents/register\n"
    else
      "Found \($agents | length) agent(s):\n",
      ($agents[]
        | (.alias // .name // "Unknown") as $alias
        | (if .status == "active" then "\u001b[32m●\u001b[0m" elif .status == "idle" then "\u001b[33m●\u001b[0m" else "\u001b[90m●\u001b[0m" end) as $icon
        | "\($icon) \($alias)\(if (.displayName // "") != "" and .displayName != $alias then " (\(.displayName))" else "" end)",
          "    ID: \((.id // "Unknown")[0:8])...",
          (if (.currentSession // "") != "" then "    Session: \(.currentSession)" else empty end),
          "    Export: export-agent.sh \($alias)",
          "")
    end' 2>/dev/null || { echo "Error: Invalid response from API"; exit 1; }

echo -e "${BLUE}Commands:${NC}"
echo -e "  export-agent.sh <alias>          Export an agent to ZIP"
echo -e "  import-agent.sh <file.zip>       Import an agent from ZIP"
