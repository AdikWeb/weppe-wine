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
[ -x "$runner/bin/wine" ] || fail "the build has no bin/wine"
cat "$runner/$RECORD_DIR/build.txt"
