#!/bin/bash

FULL_ARGS=$( echo "$@" | base64 -d | gunzip )
set -- $FULL_ARGS
FULL_ARGS=( "$@" )

# look for input file value
for i in "$@"
do
  if [ ${KILL+x} ]; then
  	echo "Download: ${FFMPEG_INPUT_FILE_PREFIX}$i"
    curl "${FFMPEG_INPUT_FILE_PREFIX}$i" -O
    unset KILL
  fi
  if [ "$i" == "-i" ]; then
    KILL=1
  fi
done

/ffmpegwrapper.sh "$@"