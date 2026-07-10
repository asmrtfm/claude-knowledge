---
category: architecture
tags: actioncable websocket real-time channels
files:
  - app/channels/order_channel.rb
created: 2026-06-20
updated: 2026-06-20
---

Order channel broadcasts on every state transition. The guest app subscribes
by order ID and expects a specific JSON shape. Changing the broadcast payload
requires a coordinated iOS update.
