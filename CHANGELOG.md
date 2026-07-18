# Changelog

## v0.7.0 — 2026-07-18

Geo depth, unparked.

- **Pure-MFL MaxMind-DB (.mmdb) reader** — metadata parse, 24/28/32-bit search tree, IPv6 tree with IPv4 descent, full data-section decoder (pointers, maps, arrays, doubles via `f64_from_bits`). ~300 lines, zero dependencies.
- **Country / region / city / lat,lon** captured at ingest when `VIGIE_GEOIP_DB` points at an MMDB file. Recommended: [DB-IP City Lite](https://db-ip.com/db/download/ip-to-city-lite) (CC BY 4.0 — includes IP geolocation data created by DB-IP); GeoLite2-City works too. `CF-IPCountry` remains the no-database fallback for country.
- New dims: `stats regions`, `stats cities`.
- **City dots on the globe**: the live feed now carries `cities`/`cities_24h` with real coordinates; both globes plot city-level markers (sized by visitors, pulsing when active) instead of country centroids when geo depth is available.
- **Fix (important): `VIGIE_TRUST_PROXY=1`** — behind Traefik/Cloudflare, client_ip previously fell back to the proxy's address, so all proxied visitors shared one IP in the visitor hash (distinguished only by user-agent). Set it on any proxied deployment.

## v0.6.0 — 2026-07-18

More rybbit alignment (geo depth still parked):

- **User journeys:** `vigie stats journeys` — per-session path transitions (edges) + top 3-step sequences, counted once per session. Rybbit's sankey, as JSON an agent can reason over.
- **Channels:** `vigie stats channels` — direct / organic / social / paid / campaign / referral classification derived from referrer + UTM at query time.
- **Browser versions:** captured from the UA (`bv` column) — `vigie stats browser-versions` ("chrome 126").
- **User profiles:** `vigie users list` (identified uids: first/last seen, sessions, pageviews) + `users show --uid` (per-user session history); `GET /api/users`.

## v0.5.0 — 2026-07-18

Closing the capture + visual gap vs rybbit (geo depth parked deliberately).

- **New captures:** OS + major version (UA-derived: Windows 10/11, macOS, iOS, Android N, ChromeOS, Linux), screen size, language — three new breakdown dims: `stats os|screens|languages` (snippet now sends `scr` + `lang`, ~2.2 KB)
- **Choropleth globe:** the land dot-grid is country-tagged (1.5°, 6,918 dots — 1.8× denser), so countries tint green by 24h visitor share; plus an atmosphere glow. Still zero external assets.

## v0.4.3 — 2026-07-18

- `vigie globe --site X` — one-verb retrieval of the ready-to-open war-room URL (site key resolved from the db, base from `--base`/`VIGIE_BASE_URL`)

## v0.4.2 — 2026-07-18

- **The war-room:** `GET /globe?site=&key=` — vigie serves the live globe itself; the page polls its own `/api/stats/live` every 5s (same-origin, no hart-CSP constraints). Sub-10s latency from a visitor landing to the pulse.
- **Per-site read keys:** the previously-unused `sites.site_key` is now a scoped, revocable READ credential — valid for `/api/stats/live` and `/globe` on its one site only (aggregate counts; never sessions/paths beyond top-5). `vigie site key --site d` shows it, `site rotate-key` revokes. The hart artifact stays the shareable 60s version; `/globe` is the one you watch.

## v0.4.1 — 2026-07-18

- Globe: **drag to pan** (pointer events, touch included) — grabbing the planet stops the auto-rotation; double-click resumes the spin
- `vigie snapshot --publish` gains `--title` to override the artifact title

## v0.4.0 — 2026-07-18

Rybbit core-feature alignment, the agent-first way.

- **Realtime:** `vigie stats live` + `GET /api/stats/live` — last-5-min actives, pages, countries, latest hits (`&raw=1` returns the bare object for refresh loops)
- **Real geo:** vigie.intrane.fr now rides the Cloudflare proxy → `CF-IPCountry` populates on every ingest (self-host: any proxy that sets the header)
- **The globe:** `vigie snapshot --globe` — a self-contained rotating dot-matrix world map (canvas, embedded landmask + centroids, zero external assets). `--publish --live` makes it a **living hart artifact**: hart pulls the live feed on a cadence and the globe repaints while you watch. Live: hart.intrane.fr/a/vigie/intrane-globe
- **Session explorer:** `vigie sessions list` (entry/exit, duration, pageviews/events/errors, geo, device) + `sessions show --sid` (the full ordered event trail); `GET /api/sessions`
- **Retention cohorts:** `vigie stats retention` — weekly cohorts over **identified** users (`window.vigie.identify('id')` / `vigie track --uid`), because the daily-rotating visitor hash cannot follow a person across days (privacy by design, documented honestly)
- **Web vitals:** the snippet auto-collects LCP/FCP/CLS/INP/TTFB (PerformanceObserver, sent on pagehide) → `vigie stats vitals` with p50/p75/p90
- **Error tracking:** auto-captured JS errors + unhandled rejections (max 5/page) → `vigie stats errors` grouped by message with counts, sessions hit, last seen, sample source
- Snippet is now ~2.1 KB (was 0.6 KB) and served with `Cache-Control`; ingest validates event kinds (400 on unknown)

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
