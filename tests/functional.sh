#!/bin/bash

# A project's own test suite is not a user. It runs the binary many times in a
# fresh environment, which to usage telemetry is indistinguishable from many new
# machines — poche's suite alone put 363 fabricated events into the collector.
# cli-telemetry-spec §2.2.1: harnesses that run binaries must set this.
export DO_NOT_TRACK=1

# vigie functional test suite — boots the real binary, hits real endpoints/verbs.
# Usage: tests/functional.sh [./vigie]   Exit 0 = all pass.
set -u
BIN=${1:-./vigie}
PORT=48871
DB=$(mktemp -u /tmp/vigie-test-XXXX.db)
PASS=0; FAIL=0; FAILED=()

t() { # t <name> <expected-substr-or-code> <actual>
  local name=$1 want=$2 got=$3
  if [[ "$got" == *"$want"* ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); FAILED+=("$name | want: $want | got: ${got:0:160}"); fi
}
J() { /usr/bin/python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)" 2>/dev/null || echo JSONFAIL; }

cleanup() { pkill -x "$(basename $BIN)" 2>/dev/null; rm -f "$DB" "$DB"-*; }
trap cleanup EXIT

# ---- CLI surface (no server) ----
t "version"      '"version"'            "$($BIN version)"
t "guide-json"   'vigie.guide'          "$($BIN guide)"
t "help-json"    '"commands"'           "$($BIN help-json)"
t "no-args exit" "80"                   "$($BIN >/dev/null 2>&1; echo $?)"
t "site add"     '"added":true'         "$($BIN site add t.test --db $DB)"
t "site dup exit" "91"                  "$($BIN site add t.test --db $DB >/dev/null 2>&1; echo $?)"
t "site list"    't.test'               "$($BIN site list --db $DB)"
t "site key"     'site_key'             "$($BIN site key --site t.test --db $DB)"
KEY=$($BIN site key --site t.test --db $DB | J "['data'][0]['site_key']")
t "rotate-key"   '"rotated":true'       "$($BIN site rotate-key --site t.test --db $DB)"
KEY2=$($BIN site key --site t.test --db $DB | J "['data'][0]['site_key']")
t "key changed"  "yes"                  "$([[ "$KEY" != "$KEY2" ]] && echo yes)"
t "track"        '"tracked"'            "$($BIN track --site t.test --name deploy --actor ci --db $DB)"
t "track missing site exit" "80"        "$($BIN track --name x --db $DB >/dev/null 2>&1; echo $?)"
t "goal add"     '"added":true'         "$($BIN goal add --site t.test --name g1 --kind event --match deploy --db $DB)"
t "goal bad kind exit" "80"             "$($BIN goal add --site t.test --name g2 --kind nope --match x --db $DB >/dev/null 2>&1; echo $?)"
t "goal list"    'g1'                   "$($BIN goal list --site t.test --db $DB)"
t "funnel add"   '"added":true'         "$($BIN funnel add --site t.test --name f1 --steps '/,/x' --db $DB)"
t "funnel 1step exit" "80"              "$($BIN funnel add --site t.test --name f2 --steps '/' --db $DB >/dev/null 2>&1; echo $?)"
t "funnel show"  '"step"'               "$($BIN funnel show --site t.test --name f1 --db $DB)"
t "funnel show missing exit" "90"       "$($BIN funnel show --site t.test --name nope --db $DB >/dev/null 2>&1; echo $?)"
t "feedback off" '"relayed":false'      "$(FEEDBACK_RELAY=off $BIN feedback test-msg 2>/dev/null)"
t "globe url"    '/globe?site=t.test'   "$($BIN globe --site t.test --db $DB --base https://h.x)"
t "report url"   '/report?site=t.test'  "$($BIN report --site t.test --db $DB --base https://h.x)"
t "prune"        'events_remaining'     "$($BIN prune --keep 90d --db $DB)"
t "snapshot file" '"file"'              "$($BIN snapshot --site t.test --db $DB --out /tmp/vigie-test-snap.html)"
t "snapshot globe" 'VIGIE_EMBED'        "$(grep -o VIGIE_EMBED /tmp/vigie-test-snap-g.html 2>/dev/null; $BIN snapshot --site t.test --globe --db $DB --out /tmp/vigie-test-snap-g.html >/dev/null; grep -o VIGIE_EMBED /tmp/vigie-test-snap-g.html | head -1)"

# ---- HTTP surface ----
VIGIE_DB=$DB VIGIE_ADMIN_TOKEN=tok VIGIE_TRUST_PROXY=1 $BIN serve --port $PORT >/tmp/vigie-test-serve.log 2>&1 &
sleep 1
B=http://127.0.0.1:$PORT
UA1="Mozilla/5.0 (Windows NT 10.0) Chrome/126.0.0.0 Safari/537"
UA2="Mozilla/5.0 (iPhone; iPhone OS 17) Mobile Safari/604 Version/17"
ev() { curl -s -o /dev/null -w '%{http_code}' -X POST $B/api/event -H "User-Agent: $2" -H "X-Forwarded-For: $3" -d "$1"; }

t "GET /"          'vigie'      "$(curl -s $B/)"
t "GET / is 200"   "200"        "$(curl -s -o /dev/null -w '%{http_code}' $B/)"
t "llms.txt"       '# vigie'    "$(curl -s $B/llms.txt)"
t "vigie.js"       'sendBeacon' "$(curl -s $B/vigie.js)"
t "vigie.js cache" 'max-age'    "$(curl -sI $B/vigie.js | grep -i cache-control)"
t "health"         '"status":"ok"' "$(curl -s $B/_health)"
t "404 route"      "404"        "$(curl -s -o /dev/null -w '%{http_code}' $B/nope)"
t "event pageview" "200"        "$(ev '{"site":"t.test","t":"pageview","name":"","path":"/","ref":"https://news.ycombinator.com/","q":"?utm_source=hn","props":"","uid":"u1","v":"","scr":"1920x1080","lang":"fr-FR"}' "$UA1" 1.2.3.4)"
t "event custom"   "200"        "$(ev '{"site":"t.test","t":"event","name":"signup","path":"/","ref":"","q":"","props":"{\"plan\":\"pro\"}","uid":"u1","v":"","scr":"","lang":""}' "$UA1" 1.2.3.4)"
t "event vital"    "200"        "$(ev '{"site":"t.test","t":"vital","name":"LCP","path":"/","ref":"","q":"","props":"","uid":"","v":"1200","scr":"","lang":""}' "$UA1" 1.2.3.4)"
t "event error"    "200"        "$(ev '{"site":"t.test","t":"error","name":"TypeError: boom","path":"/","ref":"","q":"","props":"{\"src\":\"a.js:1\"}","uid":"","v":"","scr":"","lang":""}' "$UA2" 5.6.7.8)"
t "event 2nd visitor" "200"     "$(ev '{"site":"t.test","t":"pageview","name":"","path":"/b","ref":"","q":"","props":"","uid":"","v":"","scr":"390x844","lang":"en-US"}' "$UA2" 5.6.7.8)"
t "event bad kind" "400"        "$(ev '{"site":"t.test","t":"bogus","name":"","path":"/","ref":"","q":"","props":"","uid":"","v":"","scr":"","lang":""}' "$UA1" 1.2.3.4)"
t "event unknown site" "404"    "$(ev '{"site":"nope.test","t":"pageview","name":"","path":"/","ref":"","q":"","props":"","uid":"","v":"","scr":"","lang":""}' "$UA1" 1.2.3.4)"
t "event missing site" "400"    "$(ev '{"t":"pageview","site":"","name":"","path":"/","ref":"","q":"","props":"","uid":"","v":"","scr":"","lang":""}' "$UA1" 1.2.3.4)"

A="-H Authorization:\ Bearer\ tok"
t "stats noauth 403" "403"      "$(curl -s -o /dev/null -w '%{http_code}' "$B/api/stats/overview?site=t.test")"
for d in overview timeseries live goals retention vitals errors journeys channels heatmap event-props pages entry-pages exit-pages referrers countries regions cities devices browsers browser-versions os screens languages events utm-sources utm-mediums utm-campaigns; do
  t "dim $d" '"ok":true' "$(curl -s -H "Authorization: Bearer tok" "$B/api/stats/$d?site=t.test&since=1h")"
done
t "dim unknown 400" "400"       "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer tok" "$B/api/stats/bogus?site=t.test")"
t "stats missing site 400" "400" "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer tok" "$B/api/stats/overview")"
t "overview counts" '"pageviews":2' "$(curl -s -H "Authorization: Bearer tok" "$B/api/stats/overview?site=t.test&since=1h")"
t "filter device"  'chrome'     "$(curl -s -H "Authorization: Bearer tok" "$B/api/stats/browsers?site=t.test&since=1h&device=desktop")"
t "live raw"       '"site":"t.test"' "$(curl -s -H "Authorization: Bearer tok" "$B/api/stats/live?site=t.test&raw=1")"
t "live site-key"  '"active_visitors"' "$(curl -s "$B/api/stats/live?site=t.test&raw=1&key=$KEY2")"
t "site-key scope 403" "403"    "$(curl -s -o /dev/null -w '%{http_code}' "$B/api/stats/overview?site=t.test&key=$KEY2")"
t "sessions list"  '"sid"'      "$(curl -s -H "Authorization: Bearer tok" "$B/api/sessions?site=t.test&since=1h")"
SID=$(curl -s -H "Authorization: Bearer tok" "$B/api/sessions?site=t.test&since=1h" | J "['data'][0]['sid']")
t "session show"   '"kind"'     "$(curl -s -H "Authorization: Bearer tok" "$B/api/sessions?site=t.test&sid=$SID")"
t "users"          'u1'         "$(curl -s -H "Authorization: Bearer tok" "$B/api/users?site=t.test&since=1h")"
t "user show"      '"sid"'      "$(curl -s -H "Authorization: Bearer tok" "$B/api/users?site=t.test&uid=u1")"
t "snapshot http"  'pageviews per day' "$(curl -s -H "Authorization: Bearer tok" "$B/api/snapshot?site=t.test&since=1h")"
t "globe noauth"   "403"        "$(curl -s -o /dev/null -w '%{http_code}' "$B/globe?site=t.test")"
t "globe key"      "200"        "$(curl -s -o /dev/null -w '%{http_code}' "$B/globe?site=t.test&key=$KEY2")"
t "report key"     'Traffic heatmap' "$(curl -s "$B/report?site=t.test&key=$KEY2&since=1h")"
t "report since"   'last 24h'   "$(curl -s "$B/report?site=t.test&key=$KEY2&since=24h" | grep -o 'last 24h' | head -1)"
t "report wrong key" "403"      "$(curl -s -o /dev/null -w '%{http_code}' "$B/report?site=t.test&key=wrong")"
t "cli stats after http" '"pageviews":2' "$($BIN stats overview --site t.test --since 1h --db $DB)"
t "cli sessions"   '"entry"'    "$($BIN sessions list --site t.test --since 1h --db $DB)"
t "cli users show missing exit" "90" "$($BIN users show --site t.test --uid ghost --db $DB >/dev/null 2>&1; echo $?)"

# ---- bot detection + visitor/pageview definition ----
# Regression for a real anomaly found live: visitors could exceed pageviews
# because "visitors" counted ANY event kind (a vitals-only beacon with no
# pageview attached still minted a vid), and nothing excluded bot traffic
# from any headline number.
BOTUA="Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
OV_BEFORE="$(curl -s -H "Authorization: Bearer tok" "$B/api/stats/overview?site=t.test&since=1h")"
PV_BEFORE=$(echo "$OV_BEFORE" | J "['data']['pageviews']")
VIS_BEFORE=$(echo "$OV_BEFORE" | J "['data']['visitors']")
t "event bot pageview" "200" "$(ev '{"site":"t.test","t":"pageview","name":"","path":"/","ref":"","q":"","props":"","uid":"","v":"","scr":"","lang":""}' "$BOTUA" 9.9.9.1)"
OV_AFTER="$(curl -s -H "Authorization: Bearer tok" "$B/api/stats/overview?site=t.test&since=1h")"
t "bot pageview excluded from overview" "$PV_BEFORE" "$(echo "$OV_AFTER" | J "['data']['pageviews']")"
t "bot counted in bots_excluded" "yes" "$([[ $(echo "$OV_AFTER" | J "['data']['bots_excluded']") -ge 1 ]] && echo yes)"
t "browsers dim still shows bot (audit)" '"value":"bot"' "$(curl -s -H "Authorization: Bearer tok" "$B/api/stats/browsers?site=t.test&since=1h")"
t "countries dim excludes bot" "0" "$(curl -s -H "Authorization: Bearer tok" "$B/api/stats/countries?site=t.test&since=1h" | grep -c '"value":"bot"')"
t "event vitals-only new visitor" "200" "$(ev '{"site":"t.test","t":"vital","name":"LCP","path":"/","ref":"","q":"","props":"","uid":"","v":"1000","scr":"","lang":""}' "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15) Chrome/126.0.0.0 Safari/537" 9.9.9.2)"
OV_AFTER2="$(curl -s -H "Authorization: Bearer tok" "$B/api/stats/overview?site=t.test&since=1h")"
t "vitals-only beacon does not mint a visitor" "$VIS_BEFORE" "$(echo "$OV_AFTER2" | J "['data']['visitors']")"

# ---- adversarial ----
t "malformed json body" "200 400" "200 400 $(curl -s -o /dev/null -w '%{http_code}' -X POST $B/api/event -d '{{{not-json')"
t "empty body"      "40"  "$(curl -s -o /dev/null -w '%{http_code}' -X POST $B/api/event -d '')"
t "sqli site param" '"ok":true' "$(curl -s -H "Authorization: Bearer tok" "$B/api/stats/overview?site=x%27%20OR%20%271%27%3D%271&since=1h")"
t "sqli still alive" '"status":"ok"' "$(curl -s $B/_health)"
t "huge props survives" "200" "$(curl -s -o /dev/null -w '%{http_code}' -X POST $B/api/event -H "User-Agent: $UA1" -d "{\"site\":\"t.test\",\"t\":\"event\",\"name\":\"big\",\"path\":\"/\",\"ref\":\"\",\"q\":\"\",\"props\":\"$(printf 'x%.0s' {1..4000})\",\"uid\":\"\",\"v\":\"\",\"scr\":\"\",\"lang\":\"\"}")"
t "xss path escaped in report" "no-script" "$(curl -s -X POST $B/api/event -H "User-Agent: $UA1" -d '{"site":"t.test","t":"pageview","name":"","path":"/<script>alert(1)</script>","ref":"","q":"","props":"","uid":"","v":"","scr":"","lang":""}' >/dev/null; curl -s "$B/report?site=t.test&key=$KEY2&since=1h" | grep -c '<script>alert(1)</script>' | sed 's/^0$/no-script/')"

# ---- stored XSS in the server-rendered report (regression) ----
# Ingest is open, so any dimension value is attacker-controlled, and /report is opened by the
# OWNER with their read key in the URL. jesc() used to be mistaken for an HTML escape here.
curl -s -X POST $B/api/event -H "User-Agent: $UA1" -d '{"site":"t.test","t":"pageview","name":"","path":"/attr\" onmouseover=\"alert(1)","ref":"","q":"","props":"","uid":"","v":"","scr":"","lang":""}' >/dev/null
curl -s -X POST $B/api/event -H "User-Agent: $UA1" -d '{"site":"t.test","t":"pageview","name":"","path":"/img><img src=x onerror=alert(2)>","ref":"","q":"","props":"","uid":"","v":"","scr":"","lang":""}' >/dev/null
curl -s -X POST $B/api/event -H "User-Agent: $UA1" -d '{"site":"t.test","t":"event","name":"<b>goalname</b>","path":"/g","ref":"","q":"","props":"","uid":"","v":"","scr":"","lang":""}' >/dev/null
REP="$(curl -s "$B/report?site=t.test&key=$KEY2&since=1h")"
t "xss: no raw img tag"       "0" "$(printf '%s' "$REP" | grep -c '<img src=x')"
t "xss: no raw attr break"    "0" "$(printf '%s' "$REP" | grep -c 'onmouseover=\"alert')"
t "xss: no raw event-name tag" "0" "$(printf '%s' "$REP" | grep -c '<b>goalname</b>')"
t "xss: value IS shown escaped" "&lt;img src=x" "$REP"

# ---- data-path override (one site, many single-page domains) ----
t "snippet exposes data-path" "data-path" "$(curl -s $B/vigie.js)"
t "snippet falls back to pathname" "po||location.pathname" "$(curl -s $B/vigie.js)"
curl -s -X POST $B/api/event -H "User-Agent: $UA1" -d '{"site":"t.test","t":"pageview","name":"","path":"/app-two","ref":"","q":"","props":"","uid":"","v":"","scr":"","lang":""}' >/dev/null
t "explicit path is recorded" "/app-two" "$(curl -s -H "Authorization: Bearer tok" "$B/api/stats/pages?site=t.test&since=1h")"

# ---- agent-first CLI spec compliance (cli-specs.intrane.fr) ----

# 1. an unknown verb must FAIL CLOSED. It used to exit 0 with no output at all, so a typo was
#    indistinguishable from success — the worst possible outcome for a caller that is a program.
$BIN totally-made-up >/tmp/vg_o 2>/tmp/vg_e; t "unknown verb exits 80" "80" "$?"
t "unknown verb is silent on stdout" "" "$(cat /tmp/vg_o)"
t "unknown verb explains itself" "unknown command" "$(cat /tmp/vg_e)"
$BIN site bogus-sub --db $DB >/tmp/vg_o 2>/tmp/vg_e; t "unknown SUBcommand exits 80" "80" "$?"
t "unknown subcommand named" "unknown subcommand: site" "$(cat /tmp/vg_e)"
$BIN site list --db $DB >/dev/null 2>&1; t "valid subcommand still exits 0" "0" "$?"

# 2. typed error objects: an agent must be able to branch on TYPE and know whether to retry,
#    rather than pattern-matching prose.
E="$($BIN stats overview --db $DB 2>&1 >/dev/null)"
t "error has code"        '"code":80'          "$E"
t "error has type"        '"type":"input"'     "$E"
t "error has recoverable" '"recoverable":true' "$E"
t "error has suggestions" '"suggestions":['    "$E"
# a DIFFERENT code range must yield a different type — proving type is derived from the code
# rather than hardcoded to "input".
E90="$($BIN site key --site definitely-not-a-site --db $DB 2>&1 >/dev/null)"
t "resource error typed"      '"type":"resource"' "$E90"
t "resource error code"       '"code":90'         "$E90"
$BIN site key --site definitely-not-a-site --db $DB >/dev/null 2>&1; t "resource error exits 90" "90" "$?"

# 3. the manual is reachable over HTTP, not only from the binary
t "GET /guide 200"     '"schema":"vigie.guide/v1"' "$(curl -s $B/guide)"
t "GET /help-json 200" '"schema":"vigie.help/v1"'  "$(curl -s $B/help-json)"
t "llms.txt points at a path that resolves" "GET /guide" "$(curl -s $B/llms.txt)"

# 4+5. the app owns its feedback, and the id is an idempotency key: posting the same content
#      twice must yield the SAME id and exactly ONE row.
F1="$(curl -s -X POST $B/feedback -H 'content-type: application/json' -d '{"app":"vigie","kind":"idea","message":"idem-check","context":"","reporter":"t"}')"
F2="$(curl -s -X POST $B/feedback -H 'content-type: application/json' -d '{"app":"vigie","kind":"idea","message":"idem-check","context":"","reporter":"t"}')"
t "feedback stored locally" '"stored":true' "$F1"
t "same content -> same id" "$(printf '%s' "$F1" | grep -o '"id":"[a-f0-9]*"')" "$F2"
t "feedback missing message 400" "400" "$(curl -s -o /dev/null -w '%{http_code}' -X POST $B/feedback -H 'content-type: application/json' -d '{}')"

echo
echo "PASS=$PASS FAIL=$FAIL"
if [[ $FAIL -gt 0 ]]; then printf 'FAILED: %s\n' "${FAILED[@]}"; exit 1; fi
