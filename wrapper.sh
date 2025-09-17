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
INDEX=0
declare -A processed_files
for i in "$@"
do
  if [ ${processed_files["$i"]+x} ]; then
    echo "[INITCONVERT${INDEX}] already processed clip, skipping .."
    continue  # Skip if already processed
  fi

  if [ ${KILL+x} ]; then
  	echo "Download: ${FFMPEG_INPUT_FILE_PREFIX}$i to $(pwd)"
    if [[ ! "$i" == *.mp3 ]]; then
      # mkfifo /tmp/$i.mp4
      curl -O --output-dir /tmp "${FFMPEG_INPUT_FILE_PREFIX}$i"
      echo "[INITCONVERT${INDEX}] command: ffmpeg -nostdin -progress /dev/stderr -framerate 1 -i /tmp/$i -filter_complex 'tpad=stop=-1:stop_mode=clone,fps=1,format=yuv420p' -f mjpeg -r 1 -t 5 /tmp/$i.mp4 -y 2> >(sed 's/^/[INITCONVERT] /') &"
      ffmpeg -nostdin -progress /dev/stderr -framerate 1 -i "/tmp/$i" -filter_complex "tpad=stop=-1:stop_mode=clone,fps=1,format=yuv420p" -c:v libx264 -r 1 -t 5 "/tmp/$i.mp4" -y 2> >(sed "s/^/[INITCONVERT${INDEX}] /") &
      processed_files["$i"]=1
    else
      curl -O "${FFMPEG_INPUT_FILE_PREFIX}$i"
    fi
    ((INDEX++))
    unset KILL
  fi
  if [ "$i" == "-i" ]; then
    KILL=1
  fi
done

wait
echo "[INITCONVERT] all clips pre-converted"

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
  # mkfifo /tmp/ffmpeg_ov${INDEX}
  PIPES+=(/tmp/ffmpeg_ov${INDEX}.mp4)
  filter_complex=$(echo "$element" | sed 's/\[[^]]*\]//g')
    echo "[filters${INDEX}] command: ffmpeg -init_hw_device cuda=primary:0 -filter_hw_device primary -nostdin -progress /dev/stderr -i '/tmp/${file_inputs[$((INDEX + 1))]}.mp4' -filter_complex 'fps=60,${filter_complex},format=yuv420p' -c:v libx264 -r 60 -t 5 /tmp/ffmpeg_ov${INDEX}.mp4 -y 2> >(sed 's/^/[filters${INDEX}] /')"
    ffmpeg -init_hw_device cuda=primary:0 -filter_hw_device primary -nostdin -progress /dev/stderr -i "/tmp/${file_inputs[$((INDEX + 1))]}.mp4" -filter_complex "fps=60,${filter_complex},format=yuv420p" -c:v libx264 -f mp4 -r 60 -t 5 /tmp/ffmpeg_ov${INDEX}.mp4 -y 2> >(sed "s/^/[filters${INDEX}] /") &
    # ffmpeg -i ~/d81cc681ba900b0c796a68994c0717d2ee3aa258f9bd9552ad50c3945995bcee.webp -filter_complex "${filter_complex},format=yuv420p" -f rawvideo -pix_fmt yuv420p -t 5 /tmp/wtf_ffmpeg_ov${INDEX} -y
    ((INDEX++))
done
echo
wait
echo "[filters] all clip-level effects applied"

FFMPEG_OVERLAYS=$(echo "[0:v][1:v]overlay${FFMPEG_PREMIX#*;\[0:v]\[ov1]overlay}" | sed -E 's/\[ov([0-9]+)\]/[\1:v]/g' | sed -E 's/\[out[0-9]+\]$/[out]/' | sed -E 's/\[glout[0-9]+\]$/[out]/')
PIPES=( "${PIPES[@]/#/-i }" )
# mkfifo /tmp/ffmpeg_base
FFMPEG_OVERLAYS_CMD="ffmpeg -init_hw_device cuda=primary:0 -filter_hw_device primary -nostdin -progress /dev/stderr ${PIPES[@]} -filter_complex '$FFMPEG_OVERLAYS' -map '[out]' -t 60 -c:v libx264 -f mp4 /tmp/ffmpeg_base.mp4 -r 60 -y"
echo "[overlays] command: $FFMPEG_OVERLAYS_CMD"
## BEGIN OVERLAY / GLTRANSITION DISTRIBUTIONS
#!/bin/bash

ffmpeg_cmd=${FFMPEG_OVERLAYS_CMD}
file_inputs=()
while [[ $ffmpeg_cmd =~ -i[[:space:]]+([^[:space:]]+) ]]; do
  file_inputs+=("${BASH_REMATCH[1]}")
  ffmpeg_cmd=${ffmpeg_cmd#*"-i ${BASH_REMATCH[1]}"}
done

gl_outputs=()
# Extract gltransition lines
echo ""
echo "GLTRANSITION lines:"
echo $(echo "$FFMPEG_OVERLAYS_CMD" | grep -oP '\[glprep[\d]+\]gltransition\=[A-Za-z\=\:0-9\.\,]+\[glout[\d]+\]')
prevSum="0.0"
echo "$FFMPEG_OVERLAYS_CMD" | grep -oP '\[glprep[\d]+\]gltransition\=[A-Za-z\=\:0-9\.\,]+\[glout[\d]+\]' | while read -r line; do
    # echo "$line"
    NESTED_FILTERS=$(echo $line | grep -oP 'transition\=[A-Za-z\=\:0-9\.\,]+')
    INDEX=$(echo $line | grep -oP '[0-9]+' | tail -n 1)
    echo "[OVERLAY${INDEX}] line: $line"
    NEW_FILTERS="[0:v]format=rgba[input0];[1:v]format=rgba[input1];[input0][input1]${NESTED_FILTERS}[out]"
    # Extract offset and duration using parameter expansion and grep/sed
    offset=$(echo "$line" | grep -oP 'offset=\K[0-9.]+')
    duration=$(echo "$line" | grep -oP 'duration=\K[0-9.]+')

    # Calculate sum (offset + duration)
    sum=$(echo "$offset + $duration" | bc)
    # offset=$(($prevSum - $sum))
    offset=$(awk -v prevSum="$prevSum" -v sum="$sum" 'BEGIN {print sum - prevSum}')
    prevSum=$sum
    echo "[OVERLAY${INDEX}] command: ffmpeg -i ${file_inputs[(($INDEX-1))]} -i ${file_inputs[$INDEX]} -ss ${sum} -filter_complex ${NEW_FILTERS} -map '[out]' -t 5 ${file_inputs[$INDEX]}.overlay.mp4"
    ffmpeg -i ${file_inputs[(($INDEX-1))]} -i ${file_inputs[$INDEX]} -ss ${sum} -filter_complex "${NEW_FILTERS}" -map '[out]' -t 5 ${file_inputs[$INDEX]}.overlay.mp4 2> >(sed "s/^/[OVERLAY${INDEX}] /")
    gl_outputs+=("${file_inputs[$INDEX]}.overlay.mp4")
done

CONCAT_INPUTS=()
CONCAT_VFINS=()

INDEX=0
for f in "${gl_outputs[@]}"; do
  CONCAT_INPUTS+=" -i ${f}.overlay.mp4"
  CONCAT_VFINS+="[${INDEX}:v]"
  ((INDEX++))
done

echo "[CONCAT] command: ffmpeg ${CONCAT_INPUTS} -filter_complex ${CONCAT_VFINS}concat=n=${INDEX}:v=1[out] -map '[out]' -codec libx264 /tmp/ffmpeg_base.mp4"
ffmpeg ${CONCAT_INPUTS} -filter_complex "${CONCAT_VFINS}concat=n=${INDEX}:v=1[out]" -map '[out]' -codec libx264 /tmp/ffmpeg_base.mp4 2> >(sed "s/^/[CONCAT] /")
## END OVERLAY / GLTRANSITION DISTRIBUTIONS

# wait
echo "[overlays] concatenation complete"

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
echo "[final] command: ffmpeg -init_hw_device cuda=primary:0 -filter_hw_device primary -nostdin -progress /dev/stderr -i /tmp/ffmpeg_base.mp4 $AUDIOS -filter_complex '$FFMPEG_POSTMIX' $EXTRA_MAPS ${TOTAL_DURATION} -c:v h264_nvenc -preset fast -r 60 out.mov -y 2> >(sed 's/^/[final] /')"
ffmpeg -init_hw_device cuda=primary:0 -filter_hw_device primary -nostdin -progress /dev/stderr -i /tmp/ffmpeg_base.mp4 $AUDIOS -filter_complex "$FFMPEG_POSTMIX" $EXTRA_MAPS ${TOTAL_DURATION} -c:v libx264 -preset veryfast -r 60 out.mov -y 2> >(sed "s/^/[final] /")
echo "[final] subtitle generation complete"
# fi

#DISPLAY=:100 /usr/local/bin/ffmpeg "$@"

curl -T out.mov $(curl "${FFMPEG_METADATA_ENDPOINT}" | jq -r '.output')
