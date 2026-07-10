---
category: gotchas
tags: order cache invalidation redis
files:
  - app/models/order.rb
created: 2026-06-22
updated: 2026-06-22
---

Order#total is cached in Redis with a 5-minute TTL. If you modify line items
without calling Order#bust_cache!, the API serves stale totals until expiry.
