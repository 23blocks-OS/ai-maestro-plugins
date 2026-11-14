# A2UI pages

An A2UI page is JSON that names components; the AI Maestro dashboard draws them with its own components, in its own theme. It uses [A2UI](https://a2ui.org) v1.0 and its basic catalog. Write it as `<name>.a2ui.json` in your canvas directory (a JSON list of messages), or `<name>.a2ui.jsonl` (one message per line).

## A complete page

```json
[
  {"version": "1.0", "createSurface": {"surfaceId": "approvals", "catalogId": "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"}},
  {"version": "1.0", "updateComponents": {"surfaceId": "approvals", "components": [
    {"id": "root", "component": "Column", "children": ["title", "list"]},
    {"id": "title", "component": "Text", "text": "Pending approvals"},
    {"id": "list", "component": "Column", "children": {"path": "/items", "componentId": "card"}},
    {"id": "card", "component": "Card", "child": "body"},
    {"id": "body", "component": "Column", "children": ["name", "detail", "buttons"]},
    {"id": "name", "component": "Text", "text": {"@path": "title"}},
    {"id": "detail", "component": "Text", "text": {"@path": "detail"}},
    {"id": "buttons", "component": "Row", "children": ["ok", "no"]},
    {"id": "ok", "component": "Button", "child": "ok_t", "variant": "primary", "action": {"event": {"name": "approve", "context": {"id": {"@path": "id"}}}}},
    {"id": "ok_t", "component": "Text", "text": "Approve"},
    {"id": "no", "component": "Button", "child": "no_t", "action": {"event": {"name": "reject", "context": {"id": {"@path": "id"}}}}},
    {"id": "no_t", "component": "Text", "text": "Reject"}
  ]}},
  {"version": "1.0", "updateDataModel": {"surfaceId": "approvals", "path": "/", "value": {"items": [
    {"id": "pr-412", "title": "Merge PR #412: billing retries", "detail": "Acme API, 3 files, tests pass"},
    {"id": "dep-77", "title": "Deploy globex-web to staging", "detail": "Version 2.4.1, requested by build-bot"}
  ]}}}
]
```

- Three messages: `createSurface`, `updateComponents` (a flat list; one component has the id `root`; others are referenced by id), and `updateDataModel` (the data).
- `{"@path": "/x"}` binds a value to the data. In a list template (`"children": {"path": "/items", "componentId": "card"}`) the template is repeated per item, and paths without a leading `/` are relative to that item.
- To update the page, rewrite the file; usually only the `updateDataModel` value changes.

## What you can use

Text (`variant` `caption` or `body`), Icon, Row, Column, List, Card, Tabs, Modal, Divider, Button, TextField, CheckBox, ChoicePicker, Slider, DateTimeInput, and the basic catalog functions except `openUrl`.

Not available: Image, Video, AudioPlayer and `openUrl`. A page that uses them, or has more than 2000 components or 500 messages, is not drawn; the Canvas tab shows the problem and where it is, so you can fix the file.

## What comes back

A button's `action.event` reaches you like `maestro.send()`: the same `[CANVAS]` notification and the same interaction file. `name` becomes `action`, the button's id becomes `element`, and the resolved `context` becomes `data`. Above, Approve on the second card gives action `approve`, element `ok`, data `{"id": "dep-77"}`.
