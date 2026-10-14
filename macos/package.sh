#!/bin/sh
set -eu

usage="usage: package.sh <bundle-dir> <output-dir>"
bundle=${1:?$usage}
output=${2:?$usage}
here=$(cd "$(dirname "$0")" && pwd)
. "$here/versions.sh"
. "$here/common.sh"

repository_root="$here/.."
record_dir="$bundle/Contents/Resources/weppe-wine"

write_record() {
    rm -rf "$record_dir"
    mkdir -p "$record_dir"
    cp -R "$repository_root/patches" "$record_dir/patches"
    cp "$repository_root/LICENSE" "$record_dir/LICENSE"
    {
        echo "weppe-wine $WINE_VERSION-$BUILD_REVISION"
        echo "base build: $BASE_BUILD_URL sha256:$BASE_BUILD_SHA256"
        echo "wine source: $WINE_SOURCE_URL sha256:$WINE_SOURCE_SHA256"
        echo "wine-staging: $STAGING_REPOSITORY $STAGING_TAG $STAGING_COMMIT (patchinstall.py --all)"
        echo "dxmt: $DXMT_REPOSITORY $DXMT_TAG $DXMT_COMMIT"
        echo "dxmt release: $DXMT_RELEASE_URL sha256:$DXMT_RELEASE_SHA256"
        echo "windows toolchain: $LLVM_MINGW_URL sha256:$LLVM_MINGW_SHA256"
        echo "patches:"
        for component in wine dxmt; do
            while read -r name; do
                patch_file="$repository_root/patches/$component/$name"
                echo "  $component/$name sha256:$(shasum -a 256 "$patch_file" | cut -d ' ' -f 1)"
            done < "$repository_root/patches/$component/series"
        done
    } > "$record_dir/build.txt"
}

write_archive() {
    mkdir -p "$output"
    archive="$output/$RELEASE_NAME.tar.xz"
    tar --options xz:threads=0 -cJf "$archive" -C "$(dirname "$bundle")" "$(basename "$bundle")"
    (cd "$output" && shasum -a 256 "$RELEASE_NAME.tar.xz" > "$RELEASE_NAME.tar.xz.sha256")
    echo "$archive"
}

[ -x "$bundle/$BUNDLE_WINE_DIR/bin/wine" ] || fail "$bundle/$BUNDLE_WINE_DIR/bin/wine not found"
write_record
write_archive
