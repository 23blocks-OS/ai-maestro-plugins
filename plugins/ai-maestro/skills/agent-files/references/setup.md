# AFP setup, spaces and troubleshooting

## Contents

- Installation
- Adding a space
- Command permissions for unattended agents (Claude Code)
- Where things are stored
- Limits of the reference scripts
- Troubleshooting

## Installation

Claude Code plugin, through AI Maestro: `update-aimaestro.sh` installs the skill and puts the `afp-*.sh` scripts on your PATH.

Any machine, from a clone:

```bash
git clone https://github.com/agentmessaging/agent-files.git ~/agent-files
~/agent-files/install.sh            # copies scripts/afp-*.sh to ~/.local/bin
```

Needs `curl` 7.75 or newer, `jq`, `openssl` and `shasum` or `sha256sum`. The stock macOS `openssl` (LibreSSL) is enough: the scripts do their own HMAC.

## Adding a space

A space is a bucket (optionally a key prefix inside it) on an S3-compatible store, reached with path-style requests. Add one on every machine that should use it:

```bash
afp-config.sh add shared \
  --endpoint http://100.76.17.128:3900 --bucket afp --region garage \
  --access-key GKxxxxxxxx --secret-file ~/.agent-files/shared.secret \
  --capabilities link,expire,ui --default
```

Put the secret key on the first line of the `--secret-file` and keep the file mode 600. `--secret-stdin` also works. `--secret-key` puts the secret in the shell history and `ps`, so avoid it. Secrets are never printed by any `afp-*.sh` command.

`--capabilities` records what the store can do. Garage supports `link`, `expire` (once a lifecycle rule is set) and `ui` (through any S3 client), and does not keep versions.

### Local store: Garage on your own network

Run Garage on one host and reach it over the LAN or a private mesh such as Tailscale. On the Garage host, create a bucket and a key:

```bash
garage bucket create afp
garage key create afp-agents
garage bucket allow --read --write --owner afp --key afp-agents
```

Use the key id and secret it prints in `afp-config.sh add`. Publish the S3 port only on the private address. On a local network the network is the trust boundary, so a link made here only works for machines that can reach the store.

### Self-hosted in the cloud: Garage on a VPS

Same commands with an `https://` endpoint behind a TLS reverse proxy. A store reachable from the internet needs one scoped key per host or agent, only the S3 port open, and short link lifetimes. Links then work for people outside your network.

### Hosted S3-compatible service

Any service that accepts SigV4 with path-style requests should work: set its endpoint, bucket, region and key. These scripts have been tested against Garage only. Before relying on another service, run `tests/run-tests.sh --live` against it and check that presigned links and expiry rules behave.

### Several spaces

Add as many as you need and pick one with `--space`, for example `shared` on a local store and `public` on a cloud store. `afp-config.sh default <name>` changes the default, and `afp-config.sh list` shows spaces without secrets.

## Command permissions for unattended agents (Claude Code)

Claude Code asks for approval before each Bash command that is not allow-listed. To let agents read and fetch shared files unattended, add these to `permissions.allow` in `~/.claude/settings.json` (merge into the existing array):

```json
"Bash(afp-ls.sh:*)",
"Bash(afp-get.sh:*)",
"Bash(afp-link.sh:*)",
"Bash(afp-capabilities.sh:*)"
```

`afp-put.sh` sends a file off the machine, `afp-rm.sh` deletes data and `afp-config.sh` changes which stores an agent can reach, so they are left out on purpose. Allow them only for agents whose job needs them.

## Where things are stored

| Path | Contents |
|---|---|
| `~/.agent-files/spaces.json` | Spaces and the default (mode 600) |
| `~/.agent-files/downloads/<space>/<path>` | Files fetched without `--dest` |

Environment: `AFP_HOME` moves the folder above, `AFP_OWNER` sets the manifest owner (otherwise the AMP primary address from `amp-identity.sh`, else `unknown`), `AFP_CONNECT_TIMEOUT` is the connect timeout in seconds (default 10).

## Limits of the reference scripts

- One PUT per file, so 5 GiB at most (no multipart yet). Larger files fail with `too_large` before any request.
- `put` reads the object back to verify it, so a large upload costs a second transfer.
- Path-style requests only; a space is one bucket plus an optional prefix.
- Garage has no object versioning, so overwriting is final. `put` refuses to overwrite without `--force`.
- No scanning: manifests are written with `scan: unscanned`. Another tool can set `clean`, `suspicious` or `rejected`, and `afp-get.sh` honors it.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `invalid_space`: no spaces configured | `afp-config.sh add ...` on this machine |
| `unreachable` | The store is down, or this machine cannot reach its address (for a Tailscale address, check the mesh is up) |
| `forbidden` on every request | Wrong key, or the key lacks read and write on the bucket |
| `forbidden` on a link | The link expired; make a new one with `afp-link.sh` |
| `digest_mismatch` on a fresh put | The store returned different bytes; the object was removed. Retry, and check the store's disk |
| `curl 7.75 or newer is required` | Update curl (`brew install curl`) |
| `get` says the object has no manifest | It was not stored with `afp-put.sh`. Pass `--digest` if you know the right value |
