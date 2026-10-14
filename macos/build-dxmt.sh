#!/bin/sh
set -eu

usage="usage: build-dxmt.sh <work-dir> <wine-build-dir> <bundle-dir>"
work=${1:?$usage}
wine_build=${2:?$usage}
bundle=${3:?$usage}
here=$(cd "$(dirname "$0")" && pwd)
. "$here/versions.sh"
. "$here/common.sh"

patches="$here/../patches/dxmt"
release_dir="$work/dxmt-release"
source_dir="$work/dxmt"
empty_llvm="$work/no-llvm"
rebuilt_dlls="d3d11/d3d11.dll dxgi/dxgi.dll d3d10/d3d10core.dll"
architectures="i386:build-win32 x86_64:build-win64"

unpack_release() {
    archive="$work/dxmt-release.tar.gz"
    fetch "$DXMT_RELEASE_URL" "$DXMT_RELEASE_SHA256" "$archive"
    rm -rf "$release_dir"
    mkdir -p "$release_dir"
    tar -xzf "$archive" -C "$release_dir" --strip-components 1
    [ -f "$release_dir/x86_64-unix/winemetal.so" ] || fail "the DXMT release has no x86_64-unix/winemetal.so"
}

prepare_source() {
    rm -rf "$source_dir"
    clone_at "$DXMT_REPOSITORY" "$DXMT_TAG" "$DXMT_COMMIT" "$source_dir"
    for patch_file in "$patches"/*.patch; do
        echo "Applying $(basename "$patch_file")"
        git -C "$source_dir" apply "$patch_file" || fail "$(basename "$patch_file") does not apply to DXMT $DXMT_TAG"
    done
}

build_wine_import_libraries() {
    targets=""
    for arch in i386 x86_64; do
        targets="$targets libs/winecrt0/$arch-windows/libwinecrt0.a"
        targets="$targets dlls/ntdll/$arch-windows/libntdll.a dlls/dbghelp/$arch-windows/libdbghelp.a"
    done
    make -C "$wine_build" -j"$(sysctl -n hw.ncpu)" $targets > "$work/wine-import-libs.log" 2>&1 \
        || fail_with_log "Wine's import libraries did not build" "$work/wine-import-libs.log"
}

cross_file_with_llvm_mingw() {
    sed -e "s|= '\([a-z0-9_]*-w64-mingw32\)-gcc'|= '$LLVM_MINGW/bin/\1-clang'|" \
        -e "s|= '\([a-z0-9_]*-w64-mingw32\)-g++'|= '$LLVM_MINGW/bin/\1-clang++'|" \
        -e "s|= '\([a-z0-9_]*-w64-mingw32-[a-z]*\)'|= '$LLVM_MINGW/bin/\1'|" \
        "$source_dir/$1.txt" > "$work/$1.txt"
}

build_architecture() {
    name=$1
    build="$work/dxmt-$name"
    cross_file_with_llvm_mingw "$name"
    rm -rf "$build"
    echo "Configuring DXMT $DXMT_TAG ($name)"
    CC="$HOST_CLANG" CXX="$HOST_CLANGXX" meson setup --cross-file "$work/$name.txt" --buildtype release \
        -Dwine_build_path="$wine_build" -Dnative_llvm_path="$empty_llvm" \
        "$build" "$source_dir" > "$build.configure.log" 2>&1 \
        || fail_with_log "DXMT ($name) did not configure" "$build.configure.log"
    targets=""
    for dll in $rebuilt_dlls; do
        targets="$targets src/$dll"
    done
    echo "Building d3d11.dll, dxgi.dll and d3d10core.dll ($name)"
    ninja -C "$build" $targets > "$build.build.log" 2>&1 || fail_with_log "DXMT ($name) did not build" "$build.build.log"
}

install_into_bundle() {
    lib="$bundle/$BUNDLE_WINE_DIR/lib/wine"
    for entry in $architectures; do
        arch=${entry%%:*}
        name=${entry#*:}
        for dll in $rebuilt_dlls; do
            install_builtin_dll "$work/dxmt-$name/src/$dll" "$lib/$arch-windows/$(basename "$dll")"
        done
        cp "$release_dir/$arch-windows/winemetal.dll" "$lib/$arch-windows/winemetal.dll"
        mark_builtin "$lib/$arch-windows/winemetal.dll"
    done
    cp "$release_dir/x86_64-unix/winemetal.so" "$lib/x86_64-unix/winemetal.so"
}

mkdir -p "$work" "$empty_llvm/include" "$empty_llvm/lib"
use_llvm_mingw "$work"
unpack_release
prepare_source
build_wine_import_libraries
for entry in $architectures; do
    build_architecture "${entry#*:}"
done
install_into_bundle
echo "DXMT $DXMT_TAG with weppe-wine patches installed into $bundle"
