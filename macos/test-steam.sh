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
deadline_seconds=1500
poll_seconds=15
stall_seconds=180
max_starts=3
dark_permille_limit=500
dark_seconds_limit=300
shot_tool="$results/window-shot"
shot_report="$results/window-shot.txt"
wineserver="$(dirname "$WINE")/wineserver"

starts=0
last_progress=""
last_progress_time=0
first_dark_time=0

start_steam() {
    starts=$((starts + 1))
    echo "Starting Steam (attempt $starts)"
    "$WINE" "$steam_dir/steam.exe" >> "$results/steam.log" 2>&1 &
    last_progress_time=$(date +%s)
}

restart_steam() {
    echo "Steam made no progress for ${stall_seconds}s; restarting it"
    screencapture -x "$results/stall-$starts.png"
    "$wineserver" -k || true
    "$wineserver" -w || true
    start_steam
}

progress_marker() {
    ls -lT "$steam_dir/logs" 2> /dev/null | cksum
}

mkdir -p "$results"
swiftc -O "$here/../tools/window-shot.swift" -o "$shot_tool"
curl -sSfL --retry 3 -o "$results/SteamSetup.exe" "$steam_setup_url"
echo "Installing Steam"
"$WINE" "$results/SteamSetup.exe" /S
[ -f "$steam_dir/steam.exe" ] || fail "Steam did not install into $steam_dir"

start=$(date +%s)
start_steam
while :; do
    sleep "$poll_seconds"
    now=$(date +%s)
    elapsed=$((now - start))
    if "$shot_tool" "$login_title" "$results/steam-login.png" > "$shot_report" 2>&1; then
        dark=$(awk '$1 == "dark" { print $3 }' "$shot_report")
        if [ "$dark" -lt "$dark_permille_limit" ]; then
            cat "$shot_report"
            echo "Steam's sign-in window is drawn after ${elapsed}s"
            exit 0
        fi
        echo "Steam's sign-in window is dark ($dark permille) after ${elapsed}s"
        last_progress_time=$now
        [ "$first_dark_time" -gt 0 ] || first_dark_time=$now
        if [ $((now - first_dark_time)) -ge "$dark_seconds_limit" ]; then
            cat "$shot_report"
            fail "Steam's sign-in window stayed dark for ${dark_seconds_limit}s"
        fi
    else
        echo "no sign-in window after ${elapsed}s; bootstrap: $(tail -n 1 "$steam_dir/logs/bootstrap_log.txt" 2> /dev/null || true)"
        progress=$(progress_marker)
        if [ "$progress" != "$last_progress" ]; then
            last_progress=$progress
            last_progress_time=$now
        elif [ $((now - last_progress_time)) -ge "$stall_seconds" ] && [ "$starts" -lt "$max_starts" ]; then
            restart_steam
        fi
    fi
    if [ "$elapsed" -ge "$deadline_seconds" ]; then
        cat "$shot_report"
        screencapture -x "$results/screen.png"
        fail "Steam's sign-in window was not drawn within ${deadline_seconds}s"
    fi
done
