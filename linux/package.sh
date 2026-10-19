#!/bin/sh
set -eu

usage="usage: package.sh <wine-dir> <output-dir>"
wine=${1:?$usage}
output=${2:?$usage}
here=$(cd "$(dirname "$0")" && pwd)
. "$here/versions.sh"
. "$here/../common.sh"

repository_root="$here/.."
record_dir="$wine/$RECORD_DIR"

write_record() {
    rm -rf "$record_dir"
    mkdir -p "$record_dir/patches/wine"
    while read -r name; do
        cp "$repository_root/patches/wine/$name" "$record_dir/patches/wine/$name"
    done < "$repository_root/patches/wine/linux.series"
    cp "$repository_root/patches/wine/linux.series" "$record_dir/patches/wine/linux.series"
    cp "$repository_root/LICENSE" "$record_dir/LICENSE"
    {
        echo "weppe-wine $WINE_VERSION-$BUILD_REVISION"
        echo "base build: $BASE_BUILD_URL sha256:$BASE_BUILD_SHA256"
        echo "wine source: $WINE_SOURCE_URL sha256:$WINE_SOURCE_SHA256"
        echo "wine-staging: $STAGING_REPOSITORY $STAGING_TAG $STAGING_COMMIT (patchinstall.py --all)"
        echo "windows toolchain: $LLVM_MINGW_URL sha256:$LLVM_MINGW_SHA256"
        echo "patches:"
        list_patches "$repository_root/patches" wine/linux.series
    } > "$record_dir/build.txt"
}

write_archive() {
    mkdir -p "$output"
    archive="$output/$RELEASE_NAME.tar.xz"
    top_dir=$(basename "$wine")
    XZ_OPT=-T0 tar -cJf "$archive" -C "$(dirname "$wine")" --transform "s|^$top_dir|$RELEASE_NAME|" "$top_dir"
    (cd "$output" && shasum -a 256 "$RELEASE_NAME.tar.xz" > "$RELEASE_NAME.tar.xz.sha256")
    echo "$archive"
}

[ -x "$wine/bin/wine" ] || fail "$wine/bin/wine not found"
write_record
write_archive
