#!/bin/sh
set -eu

usage="usage: build-wine.sh <work-dir> <wine-dir>"
work=${1:?$usage}
wine=${2:?$usage}
here=$(cd "$(dirname "$0")" && pwd)
. "$here/versions.sh"
. "$here/../common.sh"

series="$here/../patches/wine/linux.series"
source_dir="$work/wine-$WINE_VERSION"
staging_dir="$work/wine-staging"
build_dir="$work/wine-build"
base_dir="$work/base"
pe_dlls="propsys"
architectures="i386 x86_64"

unpack_base_build() {
    archive="$work/base.tar.xz"
    fetch "$BASE_BUILD_URL" "$BASE_BUILD_SHA256" "$archive"
    rm -rf "$base_dir"
    mkdir -p "$base_dir"
    tar -xJf "$archive" -C "$base_dir" --strip-components 1
    [ -x "$base_dir/bin/wine" ] || fail "the base build has no bin/wine"
}

configure_build() {
    rm -rf "$build_dir"
    mkdir -p "$build_dir"
    echo "Configuring Wine $WINE_VERSION (i386, x86_64)"
    (cd "$build_dir" && "$source_dir/configure" \
        --enable-archs=i386,x86_64 \
        --with-mingw="$LLVM_MINGW/bin/clang" \
        --disable-tests \
        --without-x --without-wayland --without-opengl --without-vulkan \
        --without-freetype --without-fontconfig --without-gstreamer --without-sdl --without-gnutls \
        --without-cups --without-sane --without-gphoto --without-ffmpeg --without-krb5 --without-netapi \
        --without-pcap --without-usb --without-capi --without-v4l2 --without-alsa --without-pulse \
        --without-oss --without-udev --without-dbus --without-unwind \
        > "$work/configure.log" 2>&1) || fail_with_log "configure failed" "$work/configure.log"
}

build() {
    targets=""
    for name in $pe_dlls; do
        for arch in $architectures; do
            targets="$targets dlls/$name/$arch-windows/$name.dll"
        done
    done
    echo "Building$targets"
    make -C "$build_dir" -j"$(nproc)" $targets > "$work/make.log" 2>&1 \
        || fail_with_log "the build failed" "$work/make.log"
}

graft() {
    rm -rf "$wine"
    mkdir -p "$(dirname "$wine")"
    cp -a "$base_dir" "$wine"
    for name in $pe_dlls; do
        for arch in $architectures; do
            install_builtin_dll "$build_dir/dlls/$name/$arch-windows/$name.dll" "$wine/lib/wine/$arch-windows/$name.dll"
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
echo "Wine $WINE_VERSION with weppe-wine patches: $wine"
