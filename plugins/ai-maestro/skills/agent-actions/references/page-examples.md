# Canvas page examples

Complete, working examples to adapt. SKILL.md has the rules; this file shows them applied.

## Contents

- A sortable, filterable report (test results)
- Approval cards that send actions back
- Responding to each action type
- More data block shapes (API response, file listing, metrics, diff)

## A sortable, filterable report (test results)

Data in one JSON block; controls change a small `state` object and call `renderRows()`, which rebuilds only the table from `DATA` and `state`. Values are escaped before going into `innerHTML`.

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Test Results</title>
    <style>
        body { font-family: system-ui, sans-serif; background: #0f172a; color: #e2e8f0; padding: 24px; }
        .summary { display: flex; gap: 16px; margin: 16px 0; }
        table { width: 100%; border-collapse: collapse; }
        th { cursor: pointer; text-align: left; }
        .badge.failed { color: #f87171; } .badge.passed { color: #4ade80; }
    </style>
</head>
<body>
    <h1>Test Results</h1>
    <p id="generated"></p>
    <div class="summary" id="summary"></div>
    <div class="controls">
        <input id="search" type="text" placeholder="Search tests..." />
        <select id="filter">
            <option value="all">All</option>
            <option value="passed">Passed</option>
            <option value="failed">Failed</option>
            <option value="skipped">Skipped</option>
        </select>
    </div>
    <table>
        <thead><tr>
            <th data-key="name">Test</th><th data-key="suite">Suite</th>
            <th data-key="status">Status</th><th data-key="duration">Duration</th>
        </tr></thead>
        <tbody id="rows"></tbody>
    </table>

    <script type="application/json" id="page-data">
    {
        "generatedAt": "2026-05-18T15:30:00Z",
        "summary": { "total": 142, "passed": 135, "failed": 5, "skipped": 2 },
        "tests": [
            { "name": "auth.login", "status": "passed", "duration": 230, "suite": "auth" },
            { "name": "api.users.create", "status": "failed", "duration": 1200, "suite": "api", "error": "Timeout exceeded" },
            { "name": "api.users.list", "status": "passed", "duration": 89, "suite": "api" }
        ]
    }
    </script>

    <script>
        const DATA = JSON.parse(document.getElementById('page-data').textContent);
        const state = { filter: 'all', search: '', sortBy: 'name', sortDir: 1 };
        const esc = v => String(v).replace(/[&<>"']/g, c => `&#${c.charCodeAt(0)};`);

        document.getElementById('generated').textContent =
            'Generated ' + new Date(DATA.generatedAt).toLocaleString();
        document.getElementById('summary').innerHTML = Object.entries(DATA.summary)
            .map(([k, v]) => `<div class="stat">${v} <span>${esc(k)}</span></div>`).join('');

        // Controls live outside the re-rendered area, so typing in the search box keeps focus.
        document.getElementById('search').oninput = e => { state.search = e.target.value.toLowerCase(); renderRows(); };
        document.getElementById('filter').onchange = e => { state.filter = e.target.value; renderRows(); };
        document.querySelectorAll('th[data-key]').forEach(th => th.onclick = () => {
            state.sortDir = state.sortBy === th.dataset.key ? -state.sortDir : 1;
            state.sortBy = th.dataset.key;
            renderRows();
        });

        function renderRows() {
            const tests = DATA.tests
                .filter(t => state.filter === 'all' || t.status === state.filter)
                .filter(t => t.name.toLowerCase().includes(state.search))
                .sort((a, b) => (a[state.sortBy] > b[state.sortBy] ? 1 : -1) * state.sortDir);
            document.getElementById('rows').innerHTML = tests.length
                ? tests.map(t => `<tr><td>${esc(t.name)}</td><td>${esc(t.suite)}</td>
                    <td><span class="badge ${esc(t.status)}">${esc(t.status)}</span></td>
                    <td>${t.duration}ms</td></tr>`).join('')
                : '<tr><td colspan="4">No tests match your filters.</td></tr>';
        }

        renderRows();
    </script>
</body>
</html>
```

## Approval cards that send actions back

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
                    <button class="approve" onclick="decide('approve', '${pr.id}')">Approve</button>
                    <button class="reject" onclick="decide('reject', '${pr.id}')">Reject</button>
                </div>
            </div>
        `).join('');
    }

    // Look the item up by id rather than inlining JSON into the onclick attribute:
    // JSON's double quotes would end the attribute and break the button.
    function decide(element, id) {
        const pr = DATA.pendingApprovals.find(p => p.id === id);
        maestro.send('click', element, pr);
    }

    render();
</script>
```

## Responding to each action type

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

## More data block shapes

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

