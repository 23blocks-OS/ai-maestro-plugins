#!/bin/bash
# AI Maestro - Search conversation history
# Usage: memory-search.sh <query> [--mode MODE] [--role ROLE] [--limit N]
#        memory-search.sh --about <entity>
# Example: memory-search.sh "authentication"
#          memory-search.sh "component design" --mode semantic
#          memory-search.sh "user request" --role user

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/memory-helper.sh"

show_help() {
    echo "Usage: memory-search.sh <query> [options]"
    echo "       memory-search.sh --about <entity>"
    echo ""
    echo "Search your conversation history for past discussions and context."
    echo ""
    echo "Options:"
    echo "  --mode MODE    Search mode: hybrid (default), semantic, term, symbol"
    echo "  --role ROLE    Filter by role: user, assistant"
    echo "  --limit N      Limit results (default: 10)"
    echo "  --about NAME   What memory knows about one entity (host, agent, service, file, person...)"
    echo ""
    echo "Examples:"
    echo "  memory-search.sh \"authentication\"           # Hybrid search"
    echo "  memory-search.sh \"component design\" --mode semantic"
    echo "  memory-search.sh \"what did user ask\" --role user"
    echo "  memory-search.sh \"previous solution\" --limit 5"
}

if [ -z "$1" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 1
fi

# --about <entity>: the entity's relations and the memory cards that mention it
if [ "$1" = "--about" ]; then
    if [ -z "$2" ]; then show_help; exit 1; fi
    init_memory || exit 1
    ENCODED_NAME=$(printf '%s' "$2" | jq -sRr @uri)
    ABOUT=$(memory_entity "$AGENT_ID" "name=${ENCODED_NAME}") || { echo "Nothing in memory about: $2"; exit 0; }
    if [ "$(echo "$ABOUT" | jq -r '.entity.name // empty')" = "" ]; then
        echo "Nothing in memory about: $2"
        exit 0
    fi
    echo "$ABOUT" | jq -r '"\(.entity.name) (\(.entity.type), mentioned in \(.entity.mention_count) memories)" + (if (.entity.aliases | length) > 0 then "\n  also known as: " + (.entity.aliases | join(", ")) else "" end)'
    echo ""
    if [ "$(echo "$ABOUT" | jq '.relations | length')" != "0" ]; then
        echo "Relations:"
        echo "$ABOUT" | jq -r '.relations[] | if .direction == "out" then "  \(.predicate) \(.name)" else "  \(.name) \(.predicate) this" end'
        echo ""
    fi
    echo "Memories:"
    echo "$ABOUT" | jq -r '.memories[] | "[\(.category) · \((.created_at // 0) / 1000 | strftime("%Y-%m-%d"))] \((if .card.status == "done" then .card.statement else .content end)[0:400] | gsub("\n"; " "))"'
    exit 0
fi

QUERY="$1"
shift

MODE="hybrid"
ROLE=""
LIMIT="10"

while [ $# -gt 0 ]; do
    case "$1" in
        --mode)
            MODE="$2"
            shift 2
            ;;
        --role)
            ROLE="$2"
            shift 2
            ;;
        --limit)
            LIMIT="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# Initialize (gets SESSION and AGENT_ID)
init_memory || exit 1

# URL encode the query
ENCODED_QUERY=$(echo "$QUERY" | jq -sRr @uri)

echo "Searching memory for: $QUERY"
echo "Mode: $MODE"
echo "---"

# Long-term memories first: decisions, facts, preferences, patterns, insights and
# reasoning already classified from past sessions. Best-effort; older servers
# without the recall endpoint just skip this section.
RECALL=$(memory_recall "$AGENT_ID" "q=${ENCODED_QUERY}&limit=5&maxDistance=0.45" 2>/dev/null || true)
RECALL_COUNT=$(echo "$RECALL" | jq '.memories // [] | length' 2>/dev/null || echo 0)
if [ "${RECALL_COUNT:-0}" != "0" ]; then
    echo "Long-term memories ($RECALL_COUNT):"
    echo ""
    echo "$RECALL" | jq -r '.memories[] | "[\(.category) · \((.created_at // 0) / 1000 | strftime("%Y-%m-%d"))]\n  \(((.statement // .content) // "")[0:400] | gsub("\n"; " "))\n"'
    echo "---"
    echo "Conversation history:"
    echo ""
fi

# Build params
PARAMS="q=${ENCODED_QUERY}&mode=${MODE}&limit=${LIMIT}"
if [ -n "$ROLE" ]; then
    PARAMS="${PARAMS}&role=${ROLE}"
fi

# Make the query
RESPONSE=$(memory_query "$AGENT_ID" "$PARAMS") || exit 1

# Display results
RESULTS=$(echo "$RESPONSE" | jq '.results // []')
COUNT=$(echo "$RESULTS" | jq 'length')

if [ "$COUNT" = "0" ]; then
    echo "No conversations found matching: $QUERY"
    echo ""
    echo "Tips:"
    echo "  - Try different keywords or phrasing"
    echo "  - Use --mode semantic for conceptual matches"
    echo "  - Check if conversation history is indexed"
else
    echo "Found $COUNT result(s):"
    echo ""
    echo "$RESULTS" | jq -r '.[] | "[\(.role)] Score: \(.score | tostring[0:4])\n  \(.text[0:200] | gsub("\n"; " "))...\n"'
fi
