# vigie

**Agent-first, cookieless web analytics in one static binary. There is no dashboard.**

vigie (French: the ship's lookout) is a clean-room, privacy-first alternative to Google Analytics / Plausible / Rybbit built for a world where the analytics consumer is an **agent, not a human staring at charts**. Every answer is JSON on stdout. When a human does need to *see* something, your agent renders a self-contained HTML snapshot and publishes it to [hart](https://github.com/javimosch/machin-hart) — a live, shareable URL, generated on demand, disposable.

Written in [MFL](https://github.com/javimosch/machin) (machin), compiles to a single native binary (~60 KB): HTTP ingest server, SQLite store, stats engine, and CLI in one program. No Node, no ClickHouse, no Docker required.

```sh
vigie site add example.com
vigie serve --port 8090 --db vigie.db
# add to your pages:
#   <script defer src="https://your-host/vigie.js" data-site="example.com"></script>
vigie stats overview --site example.com --since 7d
# {"ok":true,"data":{"pageviews":1234,"visitors":410,"sessions":520,"bounce_rate_pct":38,...}}
```

## Why another analytics tool

- **Agent-first.** Complies with the [agent-first CLI specs](https://cli-specs.intrane.fr/): `guide` (embedded manual), `help-json` (machine catalog), JSON-only stdout, semantic exit codes (80–119), `feedback`, sha256-verified atomic `update`.
- **Cookieless & consent-banner-free.** Visitors are `sha256(secret + day + site + ip + ua)[0:16]` — the salt rotates daily, the raw IP is never stored.
- **Agents are users too.** `vigie track --site s --name deploy --actor ci` records server-side events with no browser. Your cron job's activity is a first-class analytics stream.
- **The dashboard is an artifact.** `vigie snapshot --site s --publish` renders a dark-mode HTML report and POSTs it to a hart instance → live URL. No always-on frontend to build, secure, or pay for.
- **One file, one binary.** SQLite (WAL) storage, `vigie prune` for retention. No ClickHouse at the scale most of us actually operate.

## Features

- Pageviews, visitors, sessions (30-min window), bounce rate, session duration
- **Realtime** last-5-min feed (`stats live`) and a **living globe** — `vigie snapshot --globe --publish --live` publishes a self-contained rotating world map to hart that repaints itself from the live feed ([see it running](https://hart.intrane.fr/a/vigie/intrane-globe))
- **Session explorer** (`sessions list/show`): per-session rollups + the full ordered event trail
- **Retention cohorts** over identified users (`window.vigie.identify()` — the daily-rotating hash can't follow people across days, by design)
- **Web vitals** (LCP/FCP/CLS/INP/TTFB, auto-collected, p50/p75/p90) and **error tracking** (grouped JS errors + rejections)
- Custom events with JSON props (`window.vigie('signup', {plan:'free'})`)
- Breakdowns: pages, referrers, countries, devices, browsers, events, UTM source/medium/campaign
- Timeseries (hour/day buckets), dimension filters on every query
- Goals (event or path match, `/path*` prefixes) + conversion rates
- Ordered multi-step funnels with per-step drop-off
- Remote HTTP API (Bearer-token gated) mirroring every stats verb
- ~2 KB tracking snippet: SPA (pushState) tracking, custom events, identify, web vitals, error capture
- **Geo depth**: country via `CF-IPCountry` (free behind Cloudflare) — or full country/region/city/lat-lon via a local MMDB database read by a **pure-MFL MaxMind-DB reader** (`VIGIE_GEOIP_DB=/path/db.mmdb`). Works with [DB-IP City Lite](https://db-ip.com/db/download/ip-to-city-lite) (CC BY 4.0, no account — this product includes IP geolocation data created by DB-IP) or MaxMind GeoLite2. City dots with real coordinates light up the globe.
- Behind a proxy set `VIGIE_TRUST_PROXY=1` (required for correct visitor hashing + geo there)

## Hosted (vigie cloud)

Don't want to run it? **https://vigie.intrane.fr** is the hosted instance: your org gets a scoped API token, sites, and the same JSON verbs over HTTP — free for 10k events/month, then metered per-use through a [péage](https://peage.intrane.fr) wallet (€1 per extra 100k events, no subscription; over-quota ingest answers a machine-readable HTTP 402 your agent can act on). To get an org, ping [javi@intrane.fr](mailto:javi@intrane.fr) — onboarding is one CLI verb on our side. Self-hosting stays MIT and feature-complete; the cloud layer is just multi-tenancy + metering + ops.

## Install

Grab the latest release binary (Linux x86_64; needs `libssl3` + `libsqlite3`, present on any stock distro):

```sh
curl -fsSL https://github.com/javimosch/vigie/releases/latest/download/vigie -o vigie
chmod +x vigie && ./vigie guide
```

Or build from source: [machin](https://github.com/javimosch/machin) `>= 0.107`, then `./build.sh`.

## The 60-second tour

```sh
vigie guide                          # the embedded operator manual (JSON) — start here
vigie help-json                      # machine-readable command catalog
vigie stats timeseries --site s --bucket hour --since 24h
vigie stats referrers --site s --country FR --limit 5
vigie goal add --site s --name signup --kind event --match signup
vigie stats goals --site s
vigie funnel add --site s --name onboard --steps "/,signup,/welcome"
vigie funnel show --site s --name onboard
vigie snapshot --site s --since 30d --publish   # -> live hart URL
vigie track --site s --name deploy --actor ci   # server-side event
vigie prune --keep 90d                          # retention
vigie update                                    # sha256-verified self-update
```

Remote (hosted) instance — same verbs over HTTP:

```sh
curl -H "Authorization: Bearer $TOKEN" \
  "https://vigie.example.com/api/stats/overview?site=example.com&since=7d"
```

## Docs

- Site + changelog: https://javimosch.github.io/vigie/
- `vigie guide` — always version-exact, baked into the binary you're running.

## License

MIT. Clean-room implementation — concept-level inspiration from the open-source analytics space (Plausible, Rybbit), zero code contact.
