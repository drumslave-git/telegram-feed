#!/usr/bin/env bash
# Makes the media of the fake account's "Media lab" channel and puts it on the emulator:
# a video of 3:20, one of 40 seconds, a round video, two songs and two voice messages,
# for trying the players by hand. The files are test patterns and tones from ffmpeg (run
# in Docker) and are not part of the app; the channel appears in the fake build once they
# are in its media directory, and goes with the app's data.
#
#   tool/lab_media.sh                 make the files (build/lab) and push them
#   ADB_DEVICE=emulator-5556 ...      the emulator to push to when several are running
#
# Start the app once before pushing (the media directory is made on first launch), and
# restart it afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."
out=build/lab
mkdir -p "$out"
if [ ! -f "$out/lab_long.mp4" ]; then
  root=$(cd "$out" && (pwd -W 2>/dev/null || pwd))
  MSYS_NO_PATHCONV=1 docker run --rm -v "$root:/out" --entrypoint sh linuxserver/ffmpeg:latest -c '
    set -e
    cd /out
    ff="ffmpeg -hide_banner -loglevel error -y"
    $ff -f lavfi -i "testsrc2=size=640x360:rate=24:duration=200" -f lavfi -i "sine=frequency=440:duration=200" -c:v libx264 -preset veryfast -crf 34 -g 48 -pix_fmt yuv420p -c:a aac -b:a 32k -movflags +faststart -shortest lab_long.mp4
    $ff -f lavfi -i "testsrc=size=640x360:rate=24:duration=40" -f lavfi -i "sine=frequency=660:duration=40" -c:v libx264 -preset veryfast -crf 32 -g 48 -pix_fmt yuv420p -c:a aac -b:a 32k -movflags +faststart -shortest lab_mid.mp4
    $ff -f lavfi -i "testsrc2=size=384x384:rate=24:duration=20" -f lavfi -i "sine=frequency=550:duration=20" -c:v libx264 -preset veryfast -crf 32 -pix_fmt yuv420p -c:a aac -b:a 32k -movflags +faststart -shortest lab_round.mp4
    $ff -f lavfi -i "sine=frequency=300:duration=6" -c:a libopus -b:a 16k lab_voice1.ogg
    $ff -f lavfi -i "sine=frequency=500:duration=6" -c:a libopus -b:a 16k lab_voice2.ogg
    $ff -f lavfi -i "sine=frequency=392:duration=20" -c:a libmp3lame -b:a 48k lab_song1.mp3
    $ff -f lavfi -i "sine=frequency=523:duration=20" -c:a libmp3lame -b:a 48k lab_song2.mp3
  '
fi
adb=(adb ${ADB_DEVICE:+-s "$ADB_DEVICE"})
app=dev.telegramfeed.telegram_feed
for f in "$out"/lab_*; do
  name=$(basename "$f")
  MSYS_NO_PATHCONV=1 "${adb[@]}" push "$f" "/data/local/tmp/$name" > /dev/null
  MSYS_NO_PATHCONV=1 "${adb[@]}" shell "run-as $app cp /data/local/tmp/$name files/fake/$name"
  MSYS_NO_PATHCONV=1 "${adb[@]}" shell "rm /data/local/tmp/$name"
done
MSYS_NO_PATHCONV=1 "${adb[@]}" shell "run-as $app ls -la files/fake"
