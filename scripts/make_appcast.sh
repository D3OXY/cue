#!/bin/sh
# Emits appcast.xml for one release to stdout.
# usage: make_appcast.sh <version> '<sparkle signature attrs from sign_update>'
set -eu
VERSION="$1"
SIG_ATTRS="$2"

cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Cue</title>
    <link>https://github.com/D3OXY/cue</link>
    <item>
      <title>${VERSION}</title>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <pubDate>$(date -R)</pubDate>
      <enclosure
        url="https://github.com/D3OXY/cue/releases/download/v${VERSION}/Cue-${VERSION}.zip"
        ${SIG_ATTRS}
        type="application/octet-stream"/>
    </item>
  </channel>
</rss>
EOF
