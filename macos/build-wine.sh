#!/bin/sh
set -eu

usage="usage: build-wine.sh <work-dir> <bundle-dir>"
work=${1:?$usage}
bundle=${2:?$usage}
here=$(cd "$(dirname "$0")" && pwd)
. "$here/versions.sh"
. "$here/../common.sh"

series="$here/../patches/wine/macos.series"
source_dir="$work/wine-$WINE_VERSION"
staging_dir="$work/wine-staging"
build_dir="$work/wine-build"
base_dir="$work/base"
pe_dlls="bcrypt d3dx9_* mfreadwrite propsys xactengine* xaudio2_*"

unpack_base_build() {
    archive="$work/base.tar.xz"
    fetch "$BASE_BUILD_URL" "$BASE_BUILD_SHA256" "$archive"
    rm -rf "$base_dir"
    mkdir -p "$base_dir"
    tar -xJf "$archive" -C "$base_dir"
    [ -x "$base_dir/$BASE_BUNDLE/$BUNDLE_WINE_DIR/bin/wine" ] || fail "the base build has no $BASE_BUNDLE/$BUNDLE_WINE_DIR/bin/wine"
}

configure_build() {
    rm -rf "$build_dir"
    mkdir -p "$build_dir"
    echo "Configuring Wine $WINE_VERSION (i386, x86_64)"
    export MACOSX_DEPLOYMENT_TARGET
    (cd "$build_dir" && "$source_dir/configure" \
        CC="$HOST_CLANG -arch x86_64" OBJC="$HOST_CLANG -arch x86_64" \
        --host=x86_64-apple-darwin --enable-archs=i386,x86_64 \
        --with-mingw="$LLVM_MINGW/bin/clang" \
        --disable-tests --disable-winebth_sys \
        --without-x --without-wayland --without-opengl \
        --without-freetype --without-gstreamer --without-sdl --without-gnutls --without-cups \
        --without-sane --without-gphoto --without-ffmpeg --without-krb5 --without-netapi \
        --without-pcap --without-usb --without-inotify --without-capi --without-v4l2 \
        > "$work/configure.log" 2>&1) || fail_with_log "configure failed" "$work/configure.log"
}

pe_dll_names() {
    (cd "$source_dir/dlls" && for pattern in $pe_dlls; do ls -d $pattern; done)
}

build() {
    targets="dlls/winemac.drv/winemac.so"
    for name in $(pe_dll_names); do
        targets="$targets dlls/$name/i386-windows/$name.dll dlls/$name/x86_64-windows/$name.dll"
    done
    echo "Building winemac.so and $(pe_dll_names | wc -l | tr -d ' ') Windows DLLs for both architectures"
    make -C "$build_dir" -j"$(sysctl -n hw.ncpu)" $targets > "$work/make.log" 2>&1 \
        || fail_with_log "the build failed" "$work/make.log"
    nm -gU "$build_dir/dlls/winemac.drv/winemac.so" | grep -q " _macdrv_functions$" \
        || fail "winemac.so does not export macdrv_functions"
    nm -gU "$build_dir/dlls/winemac.drv/winemac.so" | grep -q " _macdrv_remote_metal_layers$" \
        || fail "winemac.so does not export macdrv_remote_metal_layers"
}

graft() {
    rm -rf "$bundle"
    mkdir -p "$(dirname "$bundle")"
    cp -R "$base_dir/$BASE_BUNDLE" "$bundle"
    lib="$bundle/$BUNDLE_WINE_DIR/lib/wine"
    replace_file "$build_dir/dlls/winemac.drv/winemac.so" "$lib/x86_64-unix/winemac.so"
    for name in $(pe_dll_names); do
        for arch in i386 x86_64; do
            install_builtin_dll "$build_dir/dlls/$name/$arch-windows/$name.dll" "$lib/$arch-windows/$name.dll"
        done
    done
}

mkdir -p "$work"
use_llvm_mingw "$work"
unpack_base_build
prepare_wine_source "$work" "$source_dir" "$staging_dir" "$series"
configure_build
build
graft
echo "Wine $WINE_VERSION with weppe-wine patches: $bundle"
