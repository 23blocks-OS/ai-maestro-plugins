---
name: canvas-actions
description: Create, manage, and interact with canvas HTML pages. Write visual UIs that users see in the AI Maestro dashboard, receive structured interactions when users click/submit/select, and update pages in response. Full lifecycle management for agent-rendered canvases.
license: Apache-2.0
compatibility: Requires AI Maestro dashboard. Agent must have an ID registered in ~/.aimaestro/agents/.
metadata:
  version: "1.1.0"
  homepage: "https://agentactions.org"
  repository: "https://github.com/agentmessaging/agent-actions"
---

# Agent Canvas

Create visual, interactive HTML pages that users see in the AI Maestro dashboard. Embed live data, receive structured actions when users interact, and update pages in response.

## When to use this skill

Use canvas whenever the output is better experienced visually than as terminal text.

### Proactive triggers -- create a canvas when:

- **User asks to see data visually**: "show me", "display", "visualize", "report on", "dashboard for", "chart of", "table of", "summary of"
- **User asks for a form or config UI**: "let me configure", "settings for", "create a form", "let me pick", "I want to choose"
- **User asks for an approval or review flow**: "let me approve", "review these", "I need to decide", "show me the options"
- **User asks you to build something interactive**: "build me a", "create a page", "make a UI", "wizard for", "control panel"
- **Your output has structured data**: test results, API responses, file listings, metrics, logs, comparisons -- anything that would benefit from sorting, filtering, or visual hierarchy
- **Your output has actions the user should take**: approve/reject, select from options, configure settings, trigger operations
- **You are presenting a status or progress report**: build status, deployment state, system health, task progress

### Do NOT use canvas for:

- Quick one-line answers
- Code that should go in a file
- Terminal commands the user should run
- Simple text responses

**Default behavior: When in doubt, create a canvas.** A visual, interactive page is almost always more useful than a wall of terminal text. The user can always read it in the Canvas tab of the dashboard.

## Architecture: Data-Driven Interactive Pages

**CRITICAL: Canvas pages must be data-driven, not static HTML.**

Never hardcode data into HTML elements. Always embed data as JSON in a `<script>` block and render it with JavaScript. This makes pages interactive (sortable, filterable, searchable) instead of dead static text.

### The pattern: Embedded JSON + JS rendering

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Test Results</title>
    <style>/* styles here */</style>
</head>
<body>
    <div id="app"></div>

    <!-- DATA BLOCK: Embed all data as JSON -->
    <script type="application/json" id="page-data">
    {
        "generatedAt": "2026-05-18T15:30:00Z",
        "summary": { "total": 142, "passed": 135, "failed": 5, "skipped": 2 },
        "tests": [
            { "name": "auth.login", "status": "passed", "duration": 230, "suite": "auth" },
            { "name": "auth.logout", "status": "passed", "duration": 45, "suite": "auth" },
            { "name": "api.users.create", "status": "failed", "duration": 1200, "suite": "api", "error": "Timeout exceeded" },
            { "name": "api.users.list", "status": "passed", "duration": 89, "suite": "api" }
        ]
    }
    </script>

    <!-- RENDER LOGIC: JavaScript reads the data and builds the UI -->
    <script>
        const DATA = JSON.parse(document.getElementById('page-data').textContent);

        // State
        let filter = 'all';
        let sortBy = 'name';
        let sortDir = 'asc';
        let search = '';

        function render() {
            let tests = [...DATA.tests];

            // Filter
            if (filter !== 'all') tests = tests.filter(t => t.status === filter);
            if (search) tests = tests.filter(t => t.name.toLowerCase().includes(search.toLowerCase()));

            // Sort
            tests.sort((a, b) => {
                const val = a[sortBy] > b[sortBy] ? 1 : -1;
                return sortDir === 'asc' ? val : -val;
            });

            const app = document.getElementById('app');
            app.innerHTML = `
                <h1>Test Results</h1>
                <p class="subtitle">Generated ${new Date(DATA.generatedAt).toLocaleString()}</p>

                <div class="summary">
                    <div class="stat">${DATA.summary.total} <span>Total</span></div>
                    <div class="stat good">${DATA.summary.passed} <span>Passed</span></div>
                    <div class="stat bad">${DATA.summary.failed} <span>Failed</span></div>
                    <div class="stat skip">${DATA.summary.skipped} <span>Skipped</span></div>
                </div>

                <div class="controls">
                    <input type="text" placeholder="Search tests..." value="${search}"
                        oninput="search = this.value; render()" />
                    <select onchange="filter = this.value; render()">
                        <option value="all" ${filter === 'all' ? 'selected' : ''}>All</option>
                        <option value="passed" ${filter === 'passed' ? 'selected' : ''}>Passed</option>
                        <option value="failed" ${filter === 'failed' ? 'selected' : ''}>Failed</option>
                        <option value="skipped" ${filter === 'skipped' ? 'selected' : ''}>Skipped</option>
                    </select>
                </div>

                <table>
                    <thead>
                        <tr>
                            <th onclick="sortBy='name'; sortDir = sortDir === 'asc' ? 'desc' : 'asc'; render()">Test</th>
                            <th onclick="sortBy='suite'; sortDir = sortDir === 'asc' ? 'desc' : 'asc'; render()">Suite</th>
                            <th onclick="sortBy='status'; sortDir = sortDir === 'asc' ? 'desc' : 'asc'; render()">Status</th>
                            <th onclick="sortBy='duration'; sortDir = sortDir === 'asc' ? 'desc' : 'asc'; render()">Duration</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${tests.map(t => `
                            <tr class="${t.status}">
                                <td>${t.name}</td>
                                <td>${t.suite}</td>
                                <td><span class="badge ${t.status}">${t.status}</span></td>
                                <td>${t.duration}ms</td>
                            </tr>
                        `).join('')}
                    </tbody>
                </table>

                ${tests.length === 0 ? '<p class="empty">No tests match your filters.</p>' : ''}
            `;
        }

        render();
    </script>
</body>
</html>
```

### Why this pattern matters

| Approach | Result |
|----------|--------|
| Static HTML `<table>` with hardcoded rows | Dead page. User can only read. No sorting, no filtering, no search. |
| Embedded JSON + JS rendering | **Interactive page.** User can sort columns, filter by status, search by name. Same data, 10x more useful. |

### Data block rules

1. **Always use `<script type="application/json" id="page-data">`** for the data block. This prevents execution and is parseable.
2. **Put ALL data in one JSON block.** Don't scatter data across multiple variables.
3. **Include metadata** in the data: timestamps, totals, source info. The page should explain itself.
4. **Keep the render function pure.** It reads from `DATA` + state variables, rebuilds the DOM. No side effects.
5. **Make every list sortable and filterable.** If you have 5+ items, add search. If items have categories/statuses, add a filter dropdown. If items have numeric fields, make columns sortable.

### Data block examples by content type

**API response data:**
```html
<script type="application/json" id="page-data">
{
    "endpoint": "/api/v1/users",
    "method": "GET",
    "status": 200,
    "responseTime": 142,
    "headers": { "content-type": "application/json", "x-request-id": "abc123" },
    "body": { "users": [...], "total": 50, "page": 1 }
}
</script>
```

**File listing / directory tree:**
```html
<script type="application/json" id="page-data">
{
    "root": "/Users/project/src",
    "totalFiles": 42,
    "totalSize": 284000,
    "files": [
        { "path": "index.ts", "size": 1200, "modified": "2026-05-18T10:00:00Z", "type": "typescript" },
        { "path": "utils/helpers.ts", "size": 3400, "modified": "2026-05-17T09:00:00Z", "type": "typescript" }
    ]
}
</script>
```

**Metrics / monitoring:**
```html
<script type="application/json" id="page-data">
{
    "collectedAt": "2026-05-18T15:30:00Z",
    "services": [
        { "name": "api-gateway", "status": "healthy", "uptime": 99.97, "latency": 45, "requests": 12400 },
        { "name": "auth-service", "status": "degraded", "uptime": 98.5, "latency": 230, "requests": 8200 }
    ],
    "alerts": [
        { "id": "a1", "severity": "warning", "message": "Auth latency above threshold", "since": "2026-05-18T14:00:00Z" }
    ]
}
</script>
```

**Comparison / diff data:**
```html
<script type="application/json" id="page-data">
{
    "left": { "label": "v1.2.0", "date": "2026-05-10" },
    "right": { "label": "v1.3.0", "date": "2026-05-18" },
    "changes": [
        { "file": "src/auth.ts", "type": "modified", "additions": 42, "deletions": 15 },
        { "file": "src/new-feature.ts", "type": "added", "additions": 120, "deletions": 0 }
    ],
    "summary": { "filesChanged": 12, "additions": 340, "deletions": 89 }
}
</script>
```

### Interactive features to always include

| Data shape | Interactive features |
|------------|---------------------|
| List/table (5+ rows) | Sort by columns, search, filter by category/status |
| Metrics/numbers | Color coding (green/yellow/red), thresholds, visual bars |
| Status items | Filter by status, group by category, dismiss/acknowledge buttons |
| Timeline/log entries | Newest-first sort, search, level filter (info/warn/error) |
| Config/settings | Editable fields, save button via `maestro.send('submit', ...)` |
| Approval items | Approve/reject buttons via `maestro.send('click', ...)`, comment field |

### Combining data + actions

Pages can be both data-driven AND interactive with `maestro.send()`:

```html
<script type="application/json" id="page-data">
{
    "pendingApprovals": [
        { "id": "pr-42", "title": "Add OAuth support", "author": "alice", "files": 8, "additions": 340 },
        { "id": "pr-43", "title": "Fix login bug", "author": "bob", "files": 2, "additions": 15 }
    ]
}
</script>

<script>
    const DATA = JSON.parse(document.getElementById('page-data').textContent);

    function render() {
        document.getElementById('app').innerHTML = DATA.pendingApprovals.map(pr => `
            <div class="card">
                <h3>${pr.title}</h3>
                <p>by ${pr.author} | ${pr.files} files | +${pr.additions}</p>
                <div class="actions">
                    <button class="approve" onclick="maestro.send('click', 'approve', ${JSON.stringify(pr)})">Approve</button>
                    <button class="reject" onclick="maestro.send('click', 'reject', { id: '${pr.id}' })">Reject</button>
                </div>
            </div>
        `).join('');
    }

    render();
</script>
```

## Your Canvas Directory

Every agent has a canvas directory where HTML files are stored:

```
~/.aimaestro/agents/<your-agent-id>/canvas/
├── dashboard.html          # Your pages go here
├── reports/
│   └── weekly.html         # Subdirectories supported
└── interactions/            # User actions land here (auto-created)
    └── 2026-05-18T15-30-00-000Z-uuid.json
```

Find your agent ID:
```bash
# From environment (set by AI Maestro)
echo $AIM_AGENT_ID

# Or find it in the registry
cat ~/.aimaestro/agents/registry.json | jq '.agents[] | select(.name == "your-agent-name") | .id'
```

## Creating Canvas Pages

Write self-contained HTML files to your canvas directory. The dashboard renders them in a sandboxed iframe with the Canvas tab.

```bash
cat > ~/.aimaestro/agents/$AIM_AGENT_ID/canvas/page.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Page Title</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: system-ui, sans-serif; background: #0f172a; color: #e2e8f0; padding: 24px; }
        /* ... your styles ... */
    </style>
</head>
<body>
    <div id="app"></div>

    <script type="application/json" id="page-data">
    { /* your data here */ }
    </script>

    <script>
        const DATA = JSON.parse(document.getElementById('page-data').textContent);
        // render logic
    </script>
</body>
</html>
HTMLEOF
```

### maestro.send() API

Use `maestro.send(action, element, data)` to send user interactions back to your agent. The `maestro` object is automatically injected by the dashboard; you don't need to define it.

```javascript
maestro.send(action, element, data)
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `action` | string | Yes | What happened (see Standard Actions below) |
| `element` | string | No | Which UI element was acted on (id, name, or label) |
| `data` | object | No | Arbitrary key-value payload |

### Standard Actions

| Action | Use case | Example |
|--------|----------|---------|
| `click` | Button press, link activation | `maestro.send('click', 'deploy-btn', { env: 'prod' })` |
| `submit` | Form submission | `maestro.send('submit', 'config-form', { name: 'api', timeout: 30 })` |
| `change` | Input value changed | `maestro.send('change', 'search-input', { value: 'query text' })` |
| `select` | Option selected | `maestro.send('select', 'priority', { value: 'high' })` |
| `toggle` | Boolean switch | `maestro.send('toggle', 'dark-mode', { enabled: true })` |
| `dismiss` | Modal/alert dismissed | `maestro.send('dismiss', 'alert-42', { acknowledged: true })` |
| `navigate` | Tab/page switch in canvas | `maestro.send('navigate', 'settings-tab', { tab: 'advanced' })` |
| `custom` | Anything else | `maestro.send('custom', 'drag-drop', { from: 'A', to: 'B' })` |

Custom actions beyond this list are fine. The `action` field is freeform.

## Canvas Rules

HTML must be **self-contained**:
- Inline all CSS (in `<style>` tags or inline styles)
- Inline all JavaScript (in `<script>` tags or inline handlers)
- Embed images as base64 data URIs or use emoji/Unicode
- No external stylesheets, scripts, or images (CDN links will be blocked by the sandbox)
- No relative asset paths

The iframe sandbox allows `allow-scripts` only:
- JavaScript works
- No form submission to external URLs (use `event.preventDefault()` + `maestro.send()`)
- No popups, no same-origin access, no top-level navigation
- No `alert()`, `confirm()`, or `prompt()` (use in-page UI instead)

## Managing Canvas Files

### Organize with subdirectories
```bash
mkdir -p ~/.aimaestro/agents/$AIM_AGENT_ID/canvas/reports
mkdir -p ~/.aimaestro/agents/$AIM_AGENT_ID/canvas/forms
mkdir -p ~/.aimaestro/agents/$AIM_AGENT_ID/canvas/dashboards
```

### List files (API)
```bash
curl -s http://localhost:23000/api/agents/$AIM_AGENT_ID/canvas
```
Returns:
```json
{
  "files": [
    { "name": "dashboard.html", "path": "dashboard.html", "size": 4200, "modifiedAt": "2026-05-18T15:00:00.000Z" },
    { "name": "weekly.html", "path": "reports/weekly.html", "size": 8100, "modifiedAt": "2026-05-18T14:00:00.000Z" }
  ]
}
```

### Read a file (API)
```bash
curl -s "http://localhost:23000/api/agents/$AIM_AGENT_ID/canvas?file=dashboard.html"
```

### Update a file
Overwrite it. The dashboard picks up changes when the user refreshes or re-selects the file.

### Delete a file
```bash
rm ~/.aimaestro/agents/$AIM_AGENT_ID/canvas/old-page.html
```

### Delete all interactions (clean slate)
```bash
rm -f ~/.aimaestro/agents/$AIM_AGENT_ID/canvas/interactions/*.json
```

## Receiving Interactions

When a user interacts with your canvas page, two things happen:

1. **JSON file stored** at `~/.aimaestro/agents/<id>/canvas/interactions/<timestamp>-<uuid>.json`
2. **Terminal notification** appears in your session: `[CANVAS] file.html: User action 'element' on file.html with data: {...}`

### Interaction file format

```json
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "timestamp": "2026-05-18T15:30:00.000Z",
  "canvasFile": "dashboard.html",
  "action": "submit",
  "element": "approve-button",
  "data": { "comments": "Looks good", "rating": 5 },
  "summary": "User submit 'approve-button' on dashboard.html with data: {\"comments\":\"Looks good\",\"rating\":5}"
}
```

### Reading interactions

```bash
# List all interaction files (newest first)
ls -1r ~/.aimaestro/agents/$AIM_AGENT_ID/canvas/interactions/

# Read the most recent interaction
ls -1r ~/.aimaestro/agents/$AIM_AGENT_ID/canvas/interactions/ | head -1 | \
  xargs -I{} cat ~/.aimaestro/agents/$AIM_AGENT_ID/canvas/interactions/{}

# Read all interactions via API
curl -s http://localhost:23000/api/agents/$AIM_AGENT_ID/canvas/interactions

# Read with limit
curl -s "http://localhost:23000/api/agents/$AIM_AGENT_ID/canvas/interactions?limit=10"
```

### Processing [CANVAS] notifications

When you see a `[CANVAS]` notification, you should act on it. The notification format is:

```
[CANVAS] <canvasFile>: User <action> '<element>' on <canvasFile> with data: {<json>}
```

**Your workflow:**
1. Parse the notification or read the latest interaction file for full details
2. Decide what to do based on action type + element + data
3. Execute the action (run commands, update files, call APIs, send AMP messages, etc.)
4. Optionally update the canvas page to reflect the new state

### Response patterns by action type

**click** -- Execute the operation the button represents:
```
[CANVAS] panel.html: User click 'run-tests' on panel.html with data: {"suite":"unit"}
-> Run the test suite, then update the canvas with results
```

**submit** -- Process the form data:
```
[CANVAS] config.html: User submit 'config-form' on config.html with data: {"endpoint":"https://api.example.com","timeout":30}
-> Save the configuration, confirm success on canvas
```

**select** -- Apply the selection:
```
[CANVAS] dashboard.html: User select 'time-range' on dashboard.html with data: {"value":"7d"}
-> Regenerate the dashboard with 7-day data, update canvas
```

**toggle** -- Enable or disable the feature:
```
[CANVAS] settings.html: User toggle 'auto-deploy' on settings.html with data: {"enabled":true}
-> Enable auto-deploy in your configuration
```

**dismiss** -- Acknowledge and clean up:
```
[CANVAS] alerts.html: User dismiss 'alert-memory' on alerts.html with data: {"acknowledged":true}
-> Mark alert as seen, no further action needed
```

## Security

- Never put credentials, tokens, or secrets in `data` payloads (stored as plaintext JSON)
- Canvas files are writable only by the agent, read-only to the user via the dashboard
- File paths must not contain `..` or be absolute (path traversal protection enforced by the API)
- The `data` field is stored as-is; sanitize if displaying user-provided data back in HTML

## Quick Reference

| Task | Command |
|------|---------|
| Create a page | `cat > ~/.aimaestro/agents/$AIM_AGENT_ID/canvas/page.html << 'HTMLEOF' ... HTMLEOF` |
| Create a subdirectory | `mkdir -p ~/.aimaestro/agents/$AIM_AGENT_ID/canvas/reports/` |
| List files (API) | `curl -s http://localhost:23000/api/agents/$AIM_AGENT_ID/canvas` |
| Read a file (API) | `curl -s "http://localhost:23000/api/agents/$AIM_AGENT_ID/canvas?file=page.html"` |
| Update a page | Overwrite the HTML file |
| Delete a page | `rm ~/.aimaestro/agents/$AIM_AGENT_ID/canvas/page.html` |
| Read interactions | `ls -1r ~/.aimaestro/agents/$AIM_AGENT_ID/canvas/interactions/` |
| Read interactions (API) | `curl -s http://localhost:23000/api/agents/$AIM_AGENT_ID/canvas/interactions` |
| Clear interactions | `rm -f ~/.aimaestro/agents/$AIM_AGENT_ID/canvas/interactions/*.json` |
| Fire action from HTML | `maestro.send('click', 'btn-name', { key: 'value' })` |

## Protocol Reference

Full AAP specification: https://agentactions.org
GitHub: https://github.com/agentmessaging/agent-actions
