#!/bin/sh
set -eu

usage="usage: unpack-build.sh <dist-dir> <runner-dir>"
dist=${1:?$usage}
runner=${2:?$usage}
here=$(cd "$(dirname "$0")" && pwd)
. "$here/versions.sh"
. "$here/../common.sh"

rm -rf "$runner"
mkdir -p "$runner"
tar -xJf "$dist/$RELEASE_NAME.tar.xz" -C "$runner" --strip-components 1
winemac="$runner/$BUNDLE_WINE_DIR/lib/wine/x86_64-unix/winemac.so"
for symbol in macdrv_functions macdrv_remote_metal_layers; do
    nm -gU "$winemac" | grep -q " _$symbol$" || fail "winemac.so does not export $symbol"
done
cat "$runner/Contents/Resources/weppe-wine/build.txt"
