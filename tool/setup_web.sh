#!/usr/bin/env bash
# Run once after `flutter create --platforms=web .` has generated web/.
# Sets the page title/name and the TaskFlow icon.
set -e
cd "$(dirname "$0")/.."
[ -f web/index.html ] || { echo "web/ folder not found"; exit 1; }
sed -i -E 's#<title>[^<]*</title>#<title>TaskFlow</title>#' web/index.html
sed -i -E 's#(name="apple-mobile-web-app-title" content=")[^"]*#\1TaskFlow#' web/index.html
sed -i -E 's#("(short_)?name": *")[^"]*#\1TaskFlow#g' web/manifest.json
sed -i -E 's#("theme_color": *")[^"]*#\1\#1F6FEB#; s#("background_color": *")[^"]*#\1\#F6F8FC#' web/manifest.json
ICON=assets/launcher/mipmap-xxxhdpi/ic_launcher.png
cp "$ICON" web/favicon.png
for f in web/icons/*.png; do cp "$ICON" "$f"; done
echo "Web name and icon set."
