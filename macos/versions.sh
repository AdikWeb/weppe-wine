WINE_VERSION=11.18
BUILD_REVISION=1

WINE_SOURCE_URL=https://dl.winehq.org/wine/source/11.x/wine-11.18.tar.xz
WINE_SOURCE_SHA256=c6282f6d4daecf11f3ab9f9a2b6c598f67be7e28c363ba2cae8a3c44b611e7a4

STAGING_REPOSITORY=https://github.com/wine-staging/wine-staging.git
STAGING_TAG=v11.18
STAGING_COMMIT=627ccf4f350f41c6cea57fda05f52e57ba9fab1f

BASE_BUILD_URL=https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.18/wine-staging-11.18-osx64.tar.xz
BASE_BUILD_SHA256=b63704b91af269bc026a87f12bd297c4a50caaf570c322e600b6621ef918f127
BASE_BUNDLE="Wine Staging.app"
BUNDLE_WINE_DIR=Contents/Resources/wine

DXMT_REPOSITORY=https://github.com/3Shain/dxmt.git
DXMT_TAG=v0.80
DXMT_COMMIT=589adb780354b461645b29999cefaf533594ee99
DXMT_RELEASE_URL=https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz
DXMT_RELEASE_SHA256=8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d

RELEASE_NAME="weppe-wine-$WINE_VERSION-$BUILD_REVISION-osx64"
MACOSX_DEPLOYMENT_TARGET=10.15

LLVM_MINGW_URL=https://github.com/mstorsjo/llvm-mingw/releases/download/20251216/llvm-mingw-20251216-ucrt-macos-universal.tar.xz
LLVM_MINGW_SHA256=38bb5e48ec3e0ce95fb901f4efff0bd6ffa966d1b32539a6510af816a959d160
