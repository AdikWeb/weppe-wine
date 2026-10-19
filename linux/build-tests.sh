#!/bin/sh
set -eu

usage="usage: build-tests.sh <work-dir> <output-dir>"
work=${1:?$usage}
output=${2:?$usage}
here=$(cd "$(dirname "$0")" && pwd)
. "$here/versions.sh"
. "$here/../common.sh"

mkdir -p "$work" "$output"
use_llvm_mingw "$work"
build_test_for_both_architectures "$here/../tests/propvariant-filetime.c" "$output"
