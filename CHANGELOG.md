# Changelog

## v0.3.1 — 2026-07-18

- **Fix (important):** `vigie update` resolved its own path by running `readlink -f /proc/self/exe` in a child process — where `self` is the child, so the atomic swap could target the wrong binary. Now resolves `argv[0]` via PATH lookup + `readlink -f`. The v0.3.0 release was pulled.

## v0.3.0 — 2026-07-18

First public release. Everything below shipped in one day, built and verified end-to-end by an agent.

### M3 — remote API + hosted
- HTTP stats API mirroring every stats verb: `GET /api/stats/<dim>` (overview, timeseries, goals + 9 breakdowns) with query-param filters
- `GET /api/snapshot?site=` — the HTML dashboard over HTTP
- `POST /api/sites?domain=` — remote site registration
- All gated by `VIGIE_ADMIN_TOKEN` (Bearer); ingest + snippet always open
- Hosted instance: https://vigie.intrane.fr

### M2 — goals, funnels, snapshots
- Goals: `--kind event|path`, `/path*` prefix matching, per-session conversion rates
- Ordered funnels: per-session step progression with drop-off percentages
- `vigie snapshot`: self-contained dark-mode HTML report (SVG charts, no external assets), `--publish` POSTs it to a [hart](https://github.com/javimosch/machin-hart) instance → live shareable URL

### M1 — the full query surface + agent-first CLI contract
- `stats timeseries` (hour/day buckets) + 9 breakdown dimensions (pages, referrers, countries, devices, browsers, events, utm-*)
- Dimension filters (`--path --country --device --browser --ref --utm-source`) on every query
- [cli-specs](https://cli-specs.intrane.fr/) compliance: `guide`, `help-json`, `feedback` (dual-write relay), `update` (sha256-verified, smoke-tested, atomic swap with `.bak` rollback), semantic exit codes 80–119
- `vigie prune` — retention

### M0 — the spike
- Cookieless ingest: visitor = `sha256(secret + day + site + ip + ua)[0:16]`, daily salt rotation, raw IP never stored
- Sessions (30-min inactivity window), bounce rate, referrer cleaning, UTM capture
- `<1 KB` JS snippet with SPA pushState tracking + `window.vigie(name, props)`
- Server-side events: `vigie track` — agents/backends as first-class tracked users
- Country from `CF-IPCountry`, device/browser from UA, SQLite (WAL) storage
