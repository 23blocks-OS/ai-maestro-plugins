#!/usr/bin/env bats
# `aimaestro-agent.sh plugin install` scans skill folders it finds for the plugin.
# A plugin with no such folder left the list empty, and under set -u macOS
# /bin/bash 3.2 aborted with "plugin_skill_dirs[@]: unbound variable" after the
# install had succeeded (no success message, no agent restart).

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../src/scripts/agent-plugin.sh"
    HOME="$BATS_TEST_TMPDIR/home"
    AGENT_DIR="$BATS_TEST_TMPDIR/agent"
    mkdir -p "$HOME/.claude/skills" "$AGENT_DIR"
    export HOME AGENT_DIR SCRIPT
}

# Runs the install command with the claude CLI, agent lookup and restart stubbed
# out, in /bin/bash with set -u like aimaestro-agent.sh.
run_install() {
    run /bin/bash -c '
        set -uo pipefail
        print_info() { :; }
        print_error() { echo "ERROR: $*"; }
        print_success() { echo "OK: $*"; }
        resolve_agent() { RESOLVED_AGENT_ID=id-1; RESOLVED_ALIAS=test-agent; }
        get_agent_working_dir() { echo "$AGENT_DIR"; }
        require_claude() { :; }
        run_claude_command() { :; }
        is_current_session() { return 1; }
        restart_agent() { echo "RESTART $1"; }
        scan_skill_security() { echo "SCAN $1"; }
        source "$SCRIPT"
        cmd_plugin_install test-agent "$@"
    ' _ "$@"
}

@test "plugin without a skill folder installs and restarts the agent" {
    run_install my-plugin@my-marketplace
    [ "$status" -eq 0 ]
    [[ "$output" != *"unbound variable"* ]]
    [[ "$output" == *"OK: Plugin installed: my-plugin@my-marketplace"* ]]
    [[ "$output" == *"RESTART id-1"* ]]
    [[ "$output" != *"SCAN"* ]]
}

@test "plugin with a skill folder still gets scanned" {
    mkdir -p "$HOME/.claude/skills/my-plugin"
    touch "$HOME/.claude/skills/my-plugin/SKILL.md"
    run_install my-plugin@my-marketplace
    [ "$status" -eq 0 ]
    [[ "$output" == *"SCAN $HOME/.claude/skills/my-plugin"* ]]
    [[ "$output" == *"OK: Plugin installed"* ]]
}
