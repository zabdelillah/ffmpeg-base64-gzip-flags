#!/bin/bash

# FULL_ARGS=$( echo "$@" | base64 -d | gunzip )
FULL_ARGS=$(curl "${FFMPEG_METADATA_ENDPOINT}" | jq -r '.flags' | base64 -d | gunzip)
set -- $FULL_ARGS
FULL_ARGS=( "$@" )

echo "User: $(id)"

for font in ${FONT_URLS//,/ }
do
  echo "Download: $font to $(pwd)"
  curl $font -O
done

# look for input file value
for i in "$@"
do
  if [ ${KILL+x} ]; then
  	echo "Download: ${FFMPEG_INPUT_FILE_PREFIX}$i to $(pwd)"
    curl "${FFMPEG_INPUT_FILE_PREFIX}$i" -O
    unset KILL
  fi
  if [ "$i" == "-i" ]; then
    KILL=1
  fi
done

ls -lah

Xvfb :100 -screen 0 1280x1024x16 &
DISPLAY=:100 /usr/local/bin/ffmpeg "$@"

curl -T out.mov $(curl "${FFMPEG_METADATA_ENDPOINT}" | jq -r '.output')
