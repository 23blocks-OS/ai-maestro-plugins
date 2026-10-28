#!/usr/bin/env bats
# Allow-list for `aimaestro-agent.sh create --program`. Extracts the list and the
# check function from the script so the test does not need a running server.

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../src/scripts/agent-commands.sh"
    eval "$(sed -n '/^AIMAESTRO_ALLOWED_PROGRAMS=/p' "$SCRIPT")"
    eval "$(sed -n '/^is_allowed_program() {/,/^}/p' "$SCRIPT")"
}

@test "accepts every kind and alias the server resolves" {
    for p in claude-code claude codex aider cursor gemini opencode openclaw grok \
             pi pi-agent pi-coding-agent copilot copilot-cli github-copilot github-copilot-cli \
             none terminal; do
        is_allowed_program "$p" || { echo "rejected: $p"; return 1; }
    done
}

@test "is case-insensitive" {
    is_allowed_program "Pi"
    is_allowed_program "CLAUDE-CODE"
}

@test "rejects unknown and partial names" {
    ! is_allowed_program "bogus"
    ! is_allowed_program "p"
    ! is_allowed_program "pi-agent-x"
    ! is_allowed_program ""
    ! is_allowed_program "claude code"
}
