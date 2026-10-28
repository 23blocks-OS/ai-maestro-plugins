#!/usr/bin/env bats
# Permission profiles for `aimaestro-agent.sh create --permissions`. Sources the
# helper (no server needed) and runs the function that writes
# .claude/settings.local.json in a temp directory.

setup() {
    HELPER="$BATS_TEST_DIRNAME/../src/scripts/agent-helper.sh"
    COMMANDS="$BATS_TEST_DIRNAME/../src/scripts/agent-commands.sh"
    # shellcheck disable=SC1090
    source "$HELPER"
    TMP_DIR="$(mktemp -d)"
    export HOME="$TMP_DIR/home"
    mkdir -p "$HOME"
    PROJ="$TMP_DIR/proj"
    mkdir -p "$PROJ"
}

teardown() {
    rm -rf "$TMP_DIR"
}

settings() { echo "$PROJ/.claude/settings.local.json"; }

@test "full profile writes the exact default permissions, without mcp__*" {
    write_agent_permissions "$PROJ" full
    expected='{"permissions":{"allow":["Bash(*)","Read(*)","Write(*)","Edit(*)","Glob(*)","Grep(*)","WebFetch(*)","WebSearch(*)","Task(*)"]}}'
    [ "$(jq -c . "$(settings)")" = "$expected" ]
    ! grep -q 'mcp__' "$(settings)"
}

@test "profile defaults to full" {
    write_agent_permissions "$PROJ"
    [ "$(jq -r '.permissions.allow[0]' "$(settings)")" = "Bash(*)" ]
}

@test "messaging profile writes the exact read-only plus AMP permissions" {
    write_agent_permissions "$PROJ" messaging
    expected='{"permissions":{"allow":["Read","Glob","Grep","Bash(amp-inbox.sh:*)","Bash(amp-read.sh:*)","Bash(amp-reply.sh:*)","Bash(amp-send.sh:*)","Bash(amp-status.sh:*)","Bash(amp-inbox:*)","Bash(amp-read:*)","Bash(amp-reply:*)","Bash(amp-send:*)","Bash(amp-status:*)"],"deny":["Write","Edit","NotebookEdit","WebFetch","WebSearch","Task"]}}'
    [ "$(jq -c . "$(settings)")" = "$expected" ]
}

@test "messaging profile has no wildcard Bash and no mcp__*" {
    write_agent_permissions "$PROJ" messaging
    ! jq -e '.permissions.allow[] | select(. == "Bash(*)" or . == "Bash" or startswith("mcp__"))' "$(settings)"
}

@test "existing env is preserved and permissions are replaced" {
    mkdir -p "$PROJ/.claude"
    echo '{"env":{"CLAUDE_AGENT_NAME":"bot"},"permissions":{"allow":["Bash(*)"]},"model":"opus"}' > "$(settings)"
    write_agent_permissions "$PROJ" messaging
    [ "$(jq -r '.env.CLAUDE_AGENT_NAME' "$(settings)")" = "bot" ]
    [ "$(jq -r '.model' "$(settings)")" = "opus" ]
    [ "$(jq -r '.permissions.allow | index("Bash(*)")' "$(settings)")" = "null" ]
    [ "$(jq -r '.permissions.deny | length' "$(settings)")" = "6" ]
}

@test "bad profile errors, lists valid ones and writes nothing" {
    run write_agent_permissions "$PROJ" bogus
    [ "$status" -ne 0 ]
    [[ "$output" == *"Valid profiles: full messaging"* ]]
    [ ! -e "$(settings)" ]
}

@test "unparseable existing file is left untouched" {
    mkdir -p "$PROJ/.claude"
    echo 'not json' > "$(settings)"
    run write_agent_permissions "$PROJ" full
    [ "$status" -ne 0 ]
    [ "$(cat "$(settings)")" = "not json" ]
}

@test "create_project_template passes the profile through" {
    create_project_template "$PROJ/new" agent-x messaging >/dev/null
    [ "$(jq -r '.permissions.deny | length' "$PROJ/new/.claude/settings.local.json")" = "6" ]
}

@test "create --permissions rejects an unknown profile before touching anything" {
    source "$COMMANDS"
    check_agent_exists() { return 1; }
    run cmd_create agent-y --dir "$HOME/agent-y" --permissions bogus
    [ "$status" -ne 0 ]
    [[ "$output" == *"Valid profiles: full messaging"* ]]
    [ ! -e "$HOME/agent-y" ]
}

@test "create --help documents --permissions" {
    source "$COMMANDS"
    run cmd_create --help
    [[ "$output" == *"--permissions"* ]]
    [[ "$output" == *"messaging"* ]]
}
