HOST_CLANG=/usr/bin/clang
HOST_CLANGXX=/usr/bin/clang++
BUILTIN_MARKER="Wine builtin DLL"
BUILTIN_MARKER_OFFSET=64
PE_HEADER_POINTER_OFFSET=60
LOG_TAIL_LINES=80

fail() {
    echo "error: $1" >&2
    exit 1
}

fail_with_log() {
    tail -n "$LOG_TAIL_LINES" "$2" >&2
    fail "$1; full log: $2"
}

fetch() {
    url=$1 sha256=$2 file=$3
    if [ ! -f "$file" ]; then
        echo "Downloading $url"
        curl -sSfL --retry 3 -o "$file.part" "$url"
        mv "$file.part" "$file"
    fi
    echo "$sha256  $file" | shasum -a 256 -c - > /dev/null || fail "$file does not match its SHA-256"
}

clone_at() {
    repository=$1 tag=$2 commit=$3 dir=$4
    git clone -q --depth 1 --branch "$tag" --recurse-submodules --shallow-submodules "$repository" "$dir"
    [ "$(git -C "$dir" rev-parse HEAD)" = "$commit" ] || fail "$repository $tag is not commit $commit"
}

use_llvm_mingw() {
    toolchain="$1/llvm-mingw"
    if [ ! -x "$toolchain/bin/x86_64-w64-mingw32-clang" ]; then
        fetch "$LLVM_MINGW_URL" "$LLVM_MINGW_SHA256" "$1/llvm-mingw.tar.xz"
        rm -rf "$toolchain"
        mkdir -p "$toolchain"
        tar -xJf "$1/llvm-mingw.tar.xz" -C "$toolchain" --strip-components 1
    fi
    LLVM_MINGW="$toolchain"
}

replace_file() {
    [ -f "$2" ] || fail "$2 is not in the base build"
    cp "$1" "$2"
}

mark_builtin() {
    header=$(od -An -t u4 -j "$PE_HEADER_POINTER_OFFSET" -N 4 "$1" | tr -d ' ')
    [ "$header" -ge $((BUILTIN_MARKER_OFFSET + ${#BUILTIN_MARKER} + 1)) ] || fail "$1 has no room for the builtin marker"
    printf '%s\0' "$BUILTIN_MARKER" | dd of="$1" bs=1 seek="$BUILTIN_MARKER_OFFSET" conv=notrunc 2> /dev/null
}

install_builtin_dll() {
    built=$1 destination=$2
    [ -f "$destination" ] || fail "$destination is not in the base build"
    "$LLVM_MINGW/bin/llvm-strip" -o "$destination" "$built"
    mark_builtin "$destination"
}
