# Canvas data block examples by content type

From the canvas-actions skill. Each example is a complete embedded JSON data block (see "The pattern: Embedded JSON + JS rendering" in SKILL.md).

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

