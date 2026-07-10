---
category: architecture
tags: api contracts versioning
files:
  - lib/api/client.rb
created: 2026-06-10
updated: 2026-06-10
---

All API endpoints are versioned via Accept header, not URL path.
The guest app pins to a specific version. Breaking changes require a new version.
