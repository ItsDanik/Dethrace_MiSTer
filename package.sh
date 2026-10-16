#!/bin/sh
# Assemble the MiSTer release in dist/Dethrace_<date>/ from the build outputs,
# in the layout of the hybrid ports (hybrid/README.md, "Naming and layout"):
#   _Other/dnk-<title>.mgl             a menu entry for each game (package/games.txt)
#   _Other/dnk/dnk-Dethrace_<date>.rbf    the core, not in the menu itself
#   games/dnk/Dethrace/                   the game
#   Scripts/danik_hybrid_ports.sh       the launcher, and its screen in
#   Scripts/.danik_hybrid_ports/        (copies of both with the game: the
#                                       newest one installed is the one used)
#   downloader_danik_hybrid_ports.ini   the database for update_all, which
#                                       keeps the ports up to date from then on
set -e
cd "$(dirname "$0")"
DATE=$(date +%Y%m%d)
OUT=dist/Dethrace_$DATE
G=$OUT/games/dnk/Dethrace
rm -rf "$OUT"
mkdir -p "$OUT/_Other/dnk" "$G" "$OUT/Scripts/.danik_hybrid_ports"

# the launcher and its screen
sh hybrid/launcher/ui/build.sh > /dev/null
cp hybrid/launcher/danik_hybrid_ports.sh "$OUT/Scripts/danik_hybrid_ports.sh"
cp hybrid/launcher/ui/danik_hybrid_ports_ui "$OUT/Scripts/.danik_hybrid_ports/danik_hybrid_ports_ui"
cp hybrid/launcher/danik_hybrid_ports.sh hybrid/launcher/ui/danik_hybrid_ports_ui "$G/"
cp hybrid/launcher/downloader_danik_hybrid_ports.ini "$OUT/"

# the core, and a menu entry for each game: package/games.txt, a line each,
# <id>|<title>. With several games each entry loads the core with the set
# name Dethrace_<id> (the game's settings and button mappings are its own);
# one game has no set name. The title is the entry's name in the menu,
# without what a file name cannot have.
cp core/output_files/Dethrace.rbf "$OUT/_Other/dnk/dnk-Dethrace_$DATE.rbf"
GAMES=$(grep -v '^#' package/games.txt | grep -c '|')
grep -v '^#' package/games.txt | grep '|' | while IFS='|' read -r id title; do
    set_name=Dethrace_$id
    [ ${#set_name} -lt 32 ] || { echo "the set name $set_name is too long (31 at most)" >&2; exit 1; }
    file=$(printf %s "$title" | tr -d ':*?"<>|/\\' | tr -s ' ')
    if [ "$GAMES" -gt 1 ]; then
        set_line="<setname same_dir=\"1\">$set_name</setname>"
    else
        set_line=
    fi
    printf '<mistergamedescription><rbf>_Other/dnk/dnk-Dethrace</rbf>%s</mistergamedescription>\n' "$set_line" \
        > "$OUT/_Other/dnk-$file.mgl"
done

# the game
cp -r package/games/Dethrace/. "$G/"
cp build/mister/dethrace "$G/Dethrace"
cp build/mister/mh_message "$G/mh_message"
hybrid/docker.sh arm-linux-gnueabihf-strip "$G/Dethrace" "$G/mh_message"
chmod +x "$G/Dethrace" "$G/mh_message" "$G"/*.sh "$G/danik_hybrid_ports_ui" \
    "$OUT/Scripts/danik_hybrid_ports.sh" "$OUT/Scripts/.danik_hybrid_ports/danik_hybrid_ports_ui"
cp dethrace/LICENSE "$G/LICENSE-dethrace.txt"
cp LICENSE "$G/LICENSE-gpl3.txt"
rm -f "dist/Dethrace_$DATE.zip"
(cd "$OUT" && python3 -m zipfile -c "../Dethrace_$DATE.zip" _Other games Scripts downloader_danik_hybrid_ports.ini)
find "$OUT" -type f | sort
ls -la "dist/Dethrace_$DATE.zip"
