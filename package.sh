#!/bin/sh
# Assemble the MiSTer release in dist/Dethrace_<date>/ from the build outputs
set -e
cd "$(dirname "$0")"
DATE=$(date +%Y%m%d)
OUT=dist/Dethrace_$DATE
rm -rf "$OUT"
mkdir -p "$OUT/_Other" "$OUT/games/Dethrace"
cp core/output_files/Dethrace.rbf "$OUT/_Other/Dethrace_$DATE.rbf"
cp -r package/games/Dethrace/. "$OUT/games/Dethrace/"
cp build/mister/dethrace "$OUT/games/Dethrace/Dethrace"
docker run --rm -u "$(id -u):$(id -g)" -v "$PWD":/src mister-dethrace-tc arm-linux-gnueabihf-strip "/src/$OUT/games/Dethrace/Dethrace"
chmod +x "$OUT/games/Dethrace/Dethrace" "$OUT/games/Dethrace/_handler.sh"
cp dethrace/LICENSE "$OUT/games/Dethrace/LICENSE-dethrace.txt"
rm -f "dist/Dethrace_$DATE.zip"
(cd "$OUT" && python3 -m zipfile -c "../Dethrace_$DATE.zip" _Other games)
find "$OUT" -type f | sort
ls -la "dist/Dethrace_$DATE.zip"
