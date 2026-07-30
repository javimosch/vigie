#!/bin/sh
# Build the RELEASE artifact — which is a different binary from ./build.sh.
#
# build.sh links against whatever the build host has: libssl, libcrypto,
# libsqlite3 and glibc. Every vigie release up to v0.3.x shipped that binary
# under a README promising "one static binary" — it required glibc 2.34+, so it
# would not have started on Debian 11, Ubuntu 20.04, RHEL 8, Alpine, or a slim
# container. The claim was false for the whole life of the project and nobody
# could have reported it, because the failure happens before the tool runs.
#
# Found by the estate-wide install audit (stranger.sh), after the same bug
# turned up in grange.
set -e
cd "$(dirname "$0")"
machin encode framework/machweb.src src/core.src src/geoip.src src/app.src src/globe.src src/globe_data.src > vigie.mfl
machin build vigie.mfl -o vigie-linux-x86_64 --static
file vigie-linux-x86_64 | grep -q "statically linked" || { echo "release binary is NOT static — refusing"; exit 1; }
ldd  vigie-linux-x86_64 2>&1 | grep -q "not a dynamic executable" || { echo "release binary has dynamic deps — refusing"; exit 1; }
./vigie-linux-x86_64 version >/dev/null || { echo "release binary does not run — refusing"; exit 1; }
echo "release ok: $(wc -c < vigie-linux-x86_64) bytes, static, $(./vigie-linux-x86_64 version 2>&1 | head -1)"
