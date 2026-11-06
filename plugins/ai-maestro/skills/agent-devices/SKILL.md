---
name: agent-devices
description: Use an assigned agent home or accessory to check health, take a photo, view its camera, record microphone audio, or play audio when the user asks to interact with physical devices.
---

Use the ai-maestro-device MCP tools available in this session.

Call device_list to find the user's named device and its currently verified capabilities. Use device_health for availability, device_snapshot for a single photograph, device_camera_live for a bounded live view, device_microphone for a bounded recording, and device_speaker for prepared PCM audio. Images and recordings arrive as tool results. Base observations on that returned media.

Each endpoint belongs to one agent. Work through the configured device name. If access is revoked or permission is missing, report it and direct the operator to the device screen. Stop after the denial. Ownership transfer and media consent happen through operator controls.

A live-camera session updates the device's picture-in-picture panel while the tool is running. Its result is the latest frame. The microphone result is a WAV recording. Choose the shortest duration that serves the user's request. A stored snapshot or recording describes its capture time.

If these MCP tools are absent, the operator needs to configure the device controller and install its MCP server into this agent's working directory. Follow the device repository's agent-tools guide for setup. The skill itself provides no connection or credentials.

Setup guide: https://github.com/23blocks-OS/ai-maestro-device-protocol/blob/main/docs/agent-tools.md
