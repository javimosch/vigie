#!/bin/sh
# Build vigie from source. Requires machin >= 0.107 (https://github.com/javimosch/machin).
set -e
machin encode framework/machweb.src src/core.src src/geoip.src src/app.src src/globe.src src/globe_data.src > vigie.mfl
machin build vigie.mfl -o vigie
echo "built ./vigie ($(wc -c < vigie) bytes)"
./vigie version
[ "$1" = "test" ] && ./tests/functional.sh ./vigie
