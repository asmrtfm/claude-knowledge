---
category: architecture
tags: order lifecycle state-machine checkout
files:
  - app/models/order.rb
  - app/services/checkout_service.rb
created: 2026-06-15
updated: 2026-06-28
---

Orders follow a strict state machine: pending -> confirmed -> preparing -> ready -> picked_up.
Skipping states causes webhook failures downstream.
