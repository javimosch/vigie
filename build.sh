#!/bin/sh
# Build vigie from source. Requires machin >= 0.107 (https://github.com/javimosch/machin).
set -e
machin encode framework/machweb.src src/vigie.src > vigie.mfl
machin build vigie.mfl -o vigie
echo "built ./vigie ($(wc -c < vigie) bytes)"
./vigie version
