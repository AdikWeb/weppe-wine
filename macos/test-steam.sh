#!/bin/sh
set -eu

usage="usage: test-steam.sh <results-dir>"
results=${1:?$usage}
here=$(cd "$(dirname "$0")" && pwd)
. "$here/common.sh"
: "${WINE:?WINE must name the wine binary}" "${WINEPREFIX:?WINEPREFIX must be set}"

steam_setup_url=https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe
steam_dir="$WINEPREFIX/drive_c/Program Files (x86)/Steam"
login_title="Sign in to Steam"
deadline_seconds=900
poll_seconds=15
dark_permille_limit=500
shot_tool="$results/window-shot"
shot_report="$results/window-shot.txt"

mkdir -p "$results"
swiftc -O "$here/../tools/window-shot.swift" -o "$shot_tool"
curl -sSfL --retry 3 -o "$results/SteamSetup.exe" "$steam_setup_url"
echo "Installing Steam"
"$WINE" "$results/SteamSetup.exe" /S
[ -f "$steam_dir/steam.exe" ] || fail "Steam did not install into $steam_dir"

echo "Starting Steam"
"$WINE" "$steam_dir/steam.exe" > "$results/steam.log" 2>&1 &
start=$(date +%s)
while :; do
    sleep "$poll_seconds"
    elapsed=$(($(date +%s) - start))
    if "$shot_tool" "$login_title" "$results/steam-login.png" > "$shot_report" 2>&1; then
        dark=$(awk '$1 == "dark" { print $3 }' "$shot_report")
        if [ "$dark" -lt "$dark_permille_limit" ]; then
            cat "$shot_report"
            echo "Steam's sign-in window is drawn after ${elapsed}s"
            exit 0
        fi
        echo "Steam's sign-in window is dark ($dark permille) after ${elapsed}s"
    else
        echo "no sign-in window after ${elapsed}s; bootstrap: $(tail -n 1 "$steam_dir/logs/bootstrap_log.txt" 2> /dev/null || true)"
    fi
    if [ "$elapsed" -ge "$deadline_seconds" ]; then
        cat "$shot_report"
        screencapture -x "$results/screen.png"
        fail "Steam's sign-in window was not drawn within ${deadline_seconds}s"
    fi
done
