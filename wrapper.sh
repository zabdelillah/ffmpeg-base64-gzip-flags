#!/bin/bash

# FULL_ARGS=$( echo "$@" | base64 -d | gunzip )
BASE_FULL_ARGS=$(curl "${FFMPEG_METADATA_ENDPOINT}" | jq -r '.flags' | base64 -d | gunzip)
set -- $BASE_FULL_ARGS
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
    if [[ ! "$i" == *.mp3 ]]; then
      mkfifo /tmp/$i.mp4
      curl -O --output-dir /tmp "${FFMPEG_INPUT_FILE_PREFIX}$i"
      echo "[INITCONVERT] command: ffmpeg -nostdin -progress /dev/stderr -framerate 1 -i /tmp/$i -filter_complex 'tpad=stop=-1:stop_mode=clone,fps=1,fps=60,format=yuv420p' -f h264 -r 60 -t 5 /tmp/$i.mp4 -y 2> >(sed 's/^/[INITCONVERT] /') &"
      ffmpeg -nostdin -progress /dev/stderr -framerate 1 -i "/tmp/$i" -filter_complex "tpad=stop=-1:stop_mode=clone,fps=1,fps=60,format=yuv420p" -f h264 -r 60 -t 5 "/tmp/$i.mp4" -y 2> >(sed 's/^/[INITCONVERT] /') &
    else
      curl -O "${FFMPEG_INPUT_FILE_PREFIX}$i"
    fi
    unset KILL
  fi
  if [ "$i" == "-i" ]; then
    KILL=1
  fi
done

# wait

# for clip in *.mp4;
# do
#   base="${clip%.mp4}"
#   mv -v $clip $base
# done

# ls -lah

# Xvfb :100 -screen 0 1280x1024x16 &

FFMPEG_STRING=$(echo "$BASE_FULL_ARGS" | grep -oP '(?<=-filter_complex )\[[^\]]+\][^ ]*')
FFMPEG_AUDIOS="${FFMPEG_STRING%\[aout];*}[aout]"
FFMPEG_CLIPS="${FFMPEG_STRING##*\[aout];}" 
FFMPEG_PREMIX="${FFMPEG_CLIPS%;*}"
FFMPEG_POSTMIX=$(echo "${FFMPEG_CLIPS##*;}" | sed -E 's/\[out*\]//' | sed -E 's/\[out[0-9]+\]//' | sed -E 's/\[glout[0-9]+\]//')
TOTAL_DURATION=$(echo "$BASE_FULL_ARGS" | grep -oP -- "-t [0-9\.]+")

ffmpeg_cmd=${BASE_FULL_ARGS}
file_inputs=()
while [[ $ffmpeg_cmd =~ -i[[:space:]]+([^[:space:]]+) ]]; do
  file_inputs+=("${BASH_REMATCH[1]}")
  # Remove the first matched "-i input" part to search for the next
  ffmpeg_cmd=${ffmpeg_cmd#*"-i ${BASH_REMATCH[1]}"}
done

if [[ -z "$FFMPEG_STRING" ]]; then
  echo $BASE_FULL_ARGS
  echo "Unable to extract ffmpeg string. Exiting.."
  exit 1
fi

if [[ -z "$FFMPEG_CLIPS" ]]; then
  echo $FFMPEG_STRING
  echo "Unable to extract clips. Exiting.."
  exit 1
fi


if [[ -z "$FFMPEG_PREMIX" ]]; then
  echo $FFMPEG_CLIPS
  echo "Unable to extract premix. Exiting.."
  exit 1
fi

FFMPEG_SOURCE_EFFECTS="${FFMPEG_PREMIX%;\[0:v]\[ov1]overlay*}"
if [[ -z "$FFMPEG_SOURCE_EFFECTS" ]]; then
  FFMPEG_SOURCE_EFFECTS="${FFMPEG_PREMIX%;\[1:v]*}"
fi
if [[ -z "$FFMPEG_SOURCE_EFFECTS" ]]; then
  echo $FFMPEG_PREMIX
  echo "Unable to extract source effects. Exiting.."
  exit 1
fi

# FFMPEG_SOURCE_EFFECTS="${FFMPEG_PREMIX%;\[0\:v]\[ov1]}"
FFMPEG_SOURCE_EFFECTS="${FFMPEG_PREMIX%;\[0:v]\[ov1]overlay*}"

IFS=';' read -ra FFMPEG_CLIP_SEGMENTS <<< "$FFMPEG_SOURCE_EFFECTS"
# BEFORE="${FFMPEG_STRING%\[out[\d]+]}"
INDEX=0
PIPES=()
for element in "${FFMPEG_CLIP_SEGMENTS[@]}"
do
  mkfifo /tmp/ffmpeg_ov${INDEX}
  PIPES+=(/tmp/ffmpeg_ov${INDEX})
  filter_complex=$(echo "$element" | sed 's/\[[^]]*\]//g')
    echo "[filters${INDEX}] command: ffmpeg -init_hw_device cuda=primary:0 -filter_hw_device primary -nostdin -progress /dev/stderr -f h264 -framerate 60 -i '/tmp/${file_inputs[$((INDEX + 1))]}.mp4' -filter_complex '${filter_complex},format=yuv420p' -f rawvideo -pix_fmt yuv420p -r 60 /tmp/ffmpeg_ov${INDEX} -y 2> >(sed 's/^/[filters${INDEX}] /')"
    ffmpeg -init_hw_device cuda=primary:0 -filter_hw_device primary -nostdin -progress /dev/stderr -f h264 -framerate 60 -i "/tmp/${file_inputs[$((INDEX + 1))]}.mp4" -filter_complex "${filter_complex},format=yuv420p" -f rawvideo -pix_fmt yuv420p -r 60 /tmp/ffmpeg_ov${INDEX} -y 2> >(sed "s/^/[filters${INDEX}] /") &
    # ffmpeg -i ~/d81cc681ba900b0c796a68994c0717d2ee3aa258f9bd9552ad50c3945995bcee.webp -filter_complex "${filter_complex},format=yuv420p" -f rawvideo -pix_fmt yuv420p -t 5 /tmp/wtf_ffmpeg_ov${INDEX} -y
    ((INDEX++))
done
echo

FFMPEG_OVERLAYS=$(echo "[0:v][1:v]overlay${FFMPEG_PREMIX#*;\[0:v]\[ov1]overlay}" | sed -E 's/\[ov([0-9]+)\]/[\1:v]/g' | sed -E 's/\[out[0-9]+\]$/[out]/' | sed -E 's/\[glout[0-9]+\]$/[out]/')
PIPES=( "${PIPES[@]/#/-video_size 1080x1910 -f rawvideo -pix_fmt yuv420p -framerate 60 -i }" )
mkfifo /tmp/ffmpeg_base
echo "[overlays] command: ffmpeg -init_hw_device cuda=primary:0 -filter_hw_device primary -nostdin -progress /dev/stderr -f lavfi -i color=c=black:s=1080x1910:r=60:d=30 ${PIPES[@]} -filter_complex '$FFMPEG_OVERLAYS' -map '[out]' -t 60 -f rawvideo -pix_fmt yuv420p /tmp/ffmpeg_base -r 60 -y 2> >(sed 's/^/[overlays] /'') &"
ffmpeg -init_hw_device cuda=primary:0 -filter_hw_device primary -nostdin -progress /dev/stderr -f lavfi -i color=c=black:s=1080x1910:r=60:d=30 ${PIPES[@]} -filter_complex "$FFMPEG_OVERLAYS" -map "[out]" -t 60 -f rawvideo -pix_fmt yuv420p /tmp/ffmpeg_base -r 60 -y 2> >(sed "s/^/[overlays] /") &
EXTRA_MAPS=""
AUDIOS=""
if [[ "$FFMPEG_STRING" == *"aout"* ]]; then
  EXTRA_MAPS=" -map [out] -map [aout]"
  AUDIO_FILTERS=($(grep -oP '\[\d+:a\]' <<< "$FFMPEG_AUDIOS"))
  for AIN in "${AUDIO_FILTERS[@]}"; do
    INPUT_INDEX=${AIN#[}
      INPUT_INDEX=${INPUT_INDEX%:*}
      NEW_INDEX=$((INPUT_INDEX - INDEX))
      NEW_AIN="[$NEW_INDEX:a]"
      NEW_AIN_OUT="[a${NEW_INDEX}]"

      SED_ORIGINAL_INPUT=$(printf '%s\n' "$AIN" | sed -e 's/[]\/$*.^[]/\\&/g')
      SED_NEW_INPUT=$(printf '%s\n' "$NEW_AIN" | sed -e 's/[&/\]/\\&/g')
      SED_ORIGINAL_OUTPUT=$(printf '%s\n' "[a${INPUT_INDEX}]" | sed -e 's/[]\/$*.^[]/\\&/g')
      SED_NEW_OUTPUT=$(printf '%s\n' "$NEW_AIN_OUT" | sed -e 's/[&/\]/\\&/g')
      FFMPEG_AUDIOS=$(sed "s/$SED_ORIGINAL_INPUT/$SED_NEW_INPUT/g" <<< "$FFMPEG_AUDIOS")
      FFMPEG_AUDIOS=$(sed "s/$SED_ORIGINAL_OUTPUT/$SED_NEW_OUTPUT/g" <<< "$FFMPEG_AUDIOS")
      AUDIOS+=" -i ${file_inputs[$(( INPUT_INDEX ))]}"
  done

  FFMPEG_POSTMIX+="[out];${FFMPEG_AUDIOS}"
fi
echo "[final] command: ffmpeg -init_hw_device cuda=primary:0 -filter_hw_device primary -nostdin -progress /dev/stderr -video_size 1080x1910 -f rawvideo -pix_fmt yuv420p -framerate 60 -i /tmp/ffmpeg_base $AUDIOS -filter_complex '$FFMPEG_POSTMIX' $EXTRA_MAPS ${TOTAL_DURATION} -c:v h264_nvenc -preset fast -r 60 out.mov -y 2> >(sed 's/^/[final] /')"
ffmpeg -init_hw_device cuda=primary:0 -filter_hw_device primary -nostdin -progress /dev/stderr -video_size 1080x1910 -f rawvideo -pix_fmt yuv420p -framerate 60 -i /tmp/ffmpeg_base $AUDIOS -filter_complex "$FFMPEG_POSTMIX" $EXTRA_MAPS ${TOTAL_DURATION} -c:v libx264 -preset veryfast -r 60 out.mov -y 2> >(sed "s/^/[final] /")
# fi

#DISPLAY=:100 /usr/local/bin/ffmpeg "$@"

curl -T out.mov $(curl "${FFMPEG_METADATA_ENDPOINT}" | jq -r '.output')
