#!/bin/sh
set -eu

usage="usage: build-tests.sh <work-dir> <output-dir>"
work=${1:?$usage}
output=${2:?$usage}
here=$(cd "$(dirname "$0")" && pwd)
. "$here/versions.sh"
. "$here/../common.sh"

tests="$here/../tests"

mkdir -p "$work" "$output"
use_llvm_mingw "$work"
compiler="$LLVM_MINGW/bin/x86_64-w64-mingw32-clang"
"$compiler" -O2 -Wall "$tests/d3d11-triangle.c" -ld3d11 -ld3dcompiler_47 -ldxgi -luuid -o "$output/d3d11-triangle.exe"
"$compiler" -O2 -Wall "$tests/d3d11-present.c" -ld3d11 -ldxgi -lgdi32 -luser32 -luuid -o "$output/d3d11-present.exe"
"$compiler" -O2 -Wall "$tests/d3d11-shared-texture.c" -ld3d11 -ldxgi -luuid -o "$output/d3d11-shared-texture.exe"
build_test_for_both_architectures "$tests/propvariant-filetime.c" "$output"
