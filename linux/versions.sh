WINE_VERSION=11.19
BUILD_REVISION=3

WINE_SOURCE_URL=https://dl.winehq.org/wine/source/11.x/wine-11.19.tar.xz
WINE_SOURCE_SHA256=4820066eda68e553d330239ffc628164a348d1c623e49d058e011c5a7cda95f1

STAGING_REPOSITORY=https://github.com/wine-staging/wine-staging.git
STAGING_TAG=v11.19
STAGING_COMMIT=766285c4fc8fcf92e9d7c76f5f8a5f5d65d3fb5f

BASE_BUILD_URL=https://github.com/Kron4ek/Wine-Builds/releases/download/11.19/wine-11.19-staging-amd64-wow64.tar.xz
BASE_BUILD_SHA256=c89f69cf22f6664e3791210fa3b40c6e9e6d2e27a9aaa466f5a26d9c56664a09

RELEASE_NAME="weppe-wine-$WINE_VERSION-$BUILD_REVISION-amd64-wow64"
RECORD_DIR=weppe-wine

LLVM_MINGW_URL=https://github.com/mstorsjo/llvm-mingw/releases/download/20251216/llvm-mingw-20251216-ucrt-ubuntu-22.04-x86_64.tar.xz
LLVM_MINGW_SHA256=db561734a05eb4a0695d5e901aadd6c1cda74bba4c9e102b677f81c6fd59849a
