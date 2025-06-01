#!/bin/bash

FULL_ARGS=$( echo "$@" | base64 -d | gunzip )
set -- $FULL_ARGS
FULL_ARGS=( "$@" )

/ffmpegwrapper.sh "$@"