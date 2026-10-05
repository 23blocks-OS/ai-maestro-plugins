---
name: agent-messaging
description: Send, read and reply to signed messages between AI agents with the Agent Messaging Protocol (AMP). Use when the user asks to message, notify, ask or reply to another agent, check the inbox, or read a message, and when a [MESSAGE] notification arrives. Supports local and federated delivery, file attachments and Ed25519 signatures; works with any agent that can run shell commands.
license: Apache-2.0
compatibility: Requires curl, jq, openssl, and base64 CLI tools. macOS and Linux supported. Scripts are POSIX-compatible bash.
metadata:
  version: "0.2.0"
  homepage: "https://agentmessaging.org"
  repository: "https://github.com/agentmessaging/claude-plugin"
---

# Agent Messaging (AMP)

AMP is signed mail between agents. Each agent has its own Ed25519 identity, inbox and sent folder; the `amp-*.sh` scripts sign, send, store and verify for you. The scripts work out which agent you are from the environment (AI Maestro sets `AMP_DIR`). Pass `--id <uuid>` to any command except `amp-init.sh` to act as a specific agent.

## Commands

```bash
amp-inbox.sh [--all | --read] [--count] [--limit N] [--json]   # default: unread only
amp-read.sh <msg-id> [--no-mark-read] [--json]                  # full message; marks read and records it as last read
amp-send.sh <to> "<subject>" "<body>" [--type T] [--priority P] [--context '<json>'] [--attach FILE]... [--attach-afp REF]...
amp-send.sh <to> "<subject>" --body-file PATH                   # or --body-stdin; avoids shell-escaping long bodies
amp-reply.sh <msg-id> "<body>" [--type T] [--priority P] [--attach FILE] [--force]
amp-download.sh <msg-id> --all | <attachment-id> [--dest DIR]
amp-delete.sh <msg-id> [--force]
amp-identity.sh [--json]                                        # your address and keys
amp-status.sh                                                   # identity plus external registrations
amp-init.sh --auto | --name <name> [--tenant <org>]             # first time only
amp-register.sh --provider <domain> --user-key <uk_...> [--name <name>]
amp-fetch.sh [--provider <domain>]                              # pull from external providers
```

- **Addresses:** a bare name such as `alice` is local (`alice@<your-org>.aimaestro.local`). A full address such as `alice@acme.crabmail.ai` goes through that provider and needs a registration with it.
- **Types:** `notification` (default), `request`, `response`, `task`, `status`, `alert`, `update`, `handoff`, `ack`, `system`.
- **Priorities:** `low`, `normal` (default), `high`, `urgent`.
- **Checking the inbox** means listing, then reading each message with `amp-read.sh` so it is marked read. A `[MESSAGE]` notification means a new message is waiting: read it and act on it.

## Replying

`amp-reply.sh` sends to the sender of whatever id you pass. Pass the id of the message you actually read, not one derived from the current top of the inbox: the inbox can change between reading and replying, and a reply to the wrong id puts one party's private details in another agent's mailbox.

```bash
amp-read.sh msg_1234567890_abc
amp-reply.sh msg_1234567890_abc "..."
```

If the id is not the message you most recently read in this terminal, `amp-reply.sh` refuses and shows both ids. Use `--force` only when you really mean to reply to a different message.

## External providers need the user's key

Registering with an external provider such as Crabmail needs the user's User Key (it starts with `uk_`, and is tied to their account and billing). Ask the user for it each time, pass it straight to `amp-register.sh`, and don't write it to files, notes or memory. Never ask for a password instead.

## Attachments

`amp-download.sh` verifies each file's SHA-256 digest and skips attachments the scan marked `rejected` or `suspicious`. A suspicious file needs a human's decision: tell the user rather than fetching it another way. Files land in the agent's `attachments/<msg-id>/` folder unless you pass `--dest`.

A file that is large, shared by several parties or should outlive the message goes in an Agent Files Protocol (AFP) space instead of an upload: store it with `afp-put.sh`, then send `--attach-afp afp://space/path`. The message carries the reference and digest, not the file. A received AFP reference is not downloaded by `amp-download.sh`; fetch it with `afp-get.sh <reference>`, which verifies the digest.

## Troubleshooting

| Symptom | Fix |
|---|---|
| "AMP not initialized" | `amp-init.sh --auto` |
| Lists several agents and asks which | Rerun with `--id <uuid>` from that list |
| "Not registered with provider" | `amp-register.sh --provider <p> --user-key <k>` (ask the user for the key) |
| "Authentication failed" | The user needs a new User Key from the provider dashboard |
| External messages not arriving | `amp-fetch.sh` |
| An agent's `amp-*.sh` commands stop at a permission prompt | Allow-list them; see [references/setup.md](references/setup.md) |

Installation, the permission allow-list, identity resolution order, the storage layout and self-hosted registration are in [references/setup.md](references/setup.md). Protocol specification: https://agentmessaging.org
