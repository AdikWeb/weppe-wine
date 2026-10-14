#!/bin/sh
set -eu

release_url=https://github.com/AdikWeb/weppe-wine/releases/download/test-11.18-1
build_archive=weppe-wine-11.18-1-osx64.tar.xz
tests_archive=weppe-wine-tests.tar.gz
steam_setup_url=https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe
work="$HOME/weppe-wine-test"
report="$HOME/Desktop/weppe-wine-report"
present_test_seconds=12
login_wait_seconds=900
stall_seconds=180
max_steam_starts=3
login_settle_seconds=30
poll_seconds=10

say() {
    printf '\n==> %s\n' "$1"
}

ensure_rosetta() {
    if ! /usr/bin/arch -x86_64 /usr/bin/true 2> /dev/null; then
        say "Устанавливаю Rosetta (может спросить пароль)"
        /usr/sbin/softwareupdate --install-rosetta --agree-to-license
    fi
}

download() {
    say "Скачиваю сборку Wine (около 230 МБ)"
    mkdir -p "$work"
    cd "$work"
    for file in "$build_archive" "$tests_archive"; do
        curl -fL --progress-bar -o "$file" "$release_url/$file"
        curl -fsSL -o "$file.sha256" "$release_url/$file.sha256"
        shasum -a 256 -c "$file.sha256"
    done
}

unpack() {
    say "Распаковываю"
    rm -rf "$work/wine" "$work/tests" "$work/prefix"
    mkdir -p "$work/wine" "$work/tests"
    tar -xJf "$work/$build_archive" -C "$work/wine" --strip-components 1
    tar -xzf "$work/$tests_archive" -C "$work/tests"
    xattr -dr com.apple.quarantine "$work" 2> /dev/null || true
    WINE="$work/wine/Contents/Resources/wine/bin/wine"
    WINESERVER="$work/wine/Contents/Resources/wine/bin/wineserver"
    WINEPREFIX="$work/prefix"
    WINEDEBUG=fixme-all
    export WINE WINEPREFIX WINEDEBUG
}

create_prefix() {
    say "Создаю префикс Wine (первый запуск занимает минуту)"
    "$WINE" wineboot -u > "$report/wineboot.log" 2>&1
    "$WINESERVER" -w
}

run_present_test() {
    say "Тест отрисовки: на ${present_test_seconds} с появится окно с жёлтым и пурпурным квадратами"
    "$WINE" "$work/tests/d3d11-present.exe" > "$report/d3d11-present.log" 2>&1 &
    test_pid=$!
    sleep "$present_test_seconds"
    screencapture -x "$report/present.png" || true
    wait "$test_pid" || true
    "$WINE" "$work/tests/d3d11-triangle.exe" > "$report/d3d11-triangle.log" 2>&1 || true
    "$WINE" "$work/tests/d3d11-shared-texture.exe" > "$report/d3d11-shared-texture.log" 2>&1 || true
}

steam_dir() {
    printf '%s' "$WINEPREFIX/drive_c/Program Files (x86)/Steam"
}

start_steam() {
    steam_starts=$((steam_starts + 1))
    say "Запускаю Steam (попытка $steam_starts из $max_steam_starts)"
    "$WINE" "$(steam_dir)/steam.exe" >> "$report/steam.log" 2>&1 &
    last_change=$(date +%s)
}

steam_reached_login() {
    grep -qs "WaitingForCredentials" "$(steam_dir)/logs/steamui_login.txt"
}

run_steam() {
    say "Ставлю Steam"
    curl -fsSL -o "$work/SteamSetup.exe" "$steam_setup_url"
    "$WINE" "$work/SteamSetup.exe" /S > "$report/steam-setup.log" 2>&1
    steam_starts=0
    start=$(date +%s)
    last_marker=""
    start_steam
    say "Steam обновляется и открывает окно входа, это несколько минут"
    while ! steam_reached_login; do
        sleep "$poll_seconds"
        now=$(date +%s)
        marker=$(ls -lT "$(steam_dir)/logs" 2> /dev/null | cksum)
        if [ "$marker" != "$last_marker" ]; then
            last_marker=$marker
            last_change=$now
        elif [ $((now - last_change)) -ge "$stall_seconds" ] && [ "$steam_starts" -lt "$max_steam_starts" ]; then
            say "Steam завис на обновлении (известный баг Wine), перезапускаю"
            "$WINESERVER" -k || true
            "$WINESERVER" -w || true
            start_steam
        fi
        [ $((now - start)) -lt "$login_wait_seconds" ] || { say "Steam не дошёл до окна входа"; return; }
    done
    sleep "$login_settle_seconds"
    screencapture -x "$report/steam.png" || true
}

collect_report() {
    cp -R "$(steam_dir)/logs" "$report/steam-logs" 2> /dev/null || true
    "$WINESERVER" -k 2> /dev/null || true
    rm -f "$report.zip"
    ditto -c -k --keepParent "$report" "$report.zip"
}

rm -rf "$report"
mkdir -p "$report"
ensure_rosetta
download
unpack
create_prefix
run_present_test
run_steam
collect_report
say "Готово. Пришли файл $report.zip и скажи, окно входа Steam было нарисовано или чёрное."
say "Удалить всё: rm -rf \"$work\" \"$report\" \"$report.zip\""
