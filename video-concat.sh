#!/usr/bin/env bash
#
# Concatenate (mobile) video files in different formats to a uniform 16/9 mp4 format
# that is small and simple enough to be played by TVs. Extra features:
# - normalize audio volume
# - short intro with filename between videos
# - rotation of videos (portrait vs landscape) is respected

set -e

if [ "$#" -lt 1 ]; then
    echo "Usage: OUTPUT=out.mp4 $0 in1.mp4 in2.mp4 ..."
    exit 1
fi

: "${OUTPUT:=out.mp4}"
: "${INTRO_DURATION:=2}" # seconds
: "${FFMPEG_VIDEO_OPTIONS:=-c:v libx264 -preset veryfast -profile:v baseline -crf 28}"  # >3x encode speed, about 1/3 output size
: "${FFMPEG_AUDIO_OPTIONS:=-ar 44100 -ac 2}"
: "${RESOLUTION:=1920x1080}"
: "${FRAMERATE:=30}"
: "${FONTSIZE:=100}"

FRESOLUTION=${RESOLUTION/x/:}

intro=$(mktemp --suffix=.mp4)
inputs=()
filter=()
streams=()
i=0
echo "step [1/3] analyze audio"
for file in "$@"; do
    echo -ne "file $((i+1)) / $#\r"
    title=$(echo "$file" | sed 's/\..*$//' | tr '/' '\n' | fold -s -w40)

    has_audio=$(ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$file" | grep -q audio && echo yes || echo no)
    if [ "$has_audio" != yes ] ; then
        # if no audio, then likely some broken short snippet, so skip
        echo >2 skip $file
        continue
    fi

    inputs+=(-i "$intro")
    filter+=("[$((i*2)):v]drawtext=text='$title':fontcolor=white:fontsize=$FONTSIZE:x=(w-text_w)/2:y=(h-text_h)/2[vtitle$i];")

    inputs+=(-i "$file")
    filter+=("[$((i*2+1)):v]fps=$FRAMERATE,scale=$FRESOLUTION:force_original_aspect_ratio=decrease,pad=$FRESOLUTION:(ow-iw)/2:(oh-ih)/2,setsar=1[v$i];")

    loudnorm_json=$(ffmpeg -i "$file" -hide_banner -nostats -filter:a loudnorm=print_format=json -vn -sn -f null /dev/null 2>&1 | sed -n '/^{/,$p')
    input_i=$(echo "$loudnorm_json" | jq -r .input_i)
    input_tp=$(echo "$loudnorm_json" | jq -r .input_tp)
    input_lra=$(echo "$loudnorm_json" | jq -r .input_lra)
    input_thresh=$(echo "$loudnorm_json" | jq -r .input_thresh)
    target_offset=$(echo "$loudnorm_json" | jq -r .target_offset)
    af=loudnorm=i=-23.0:lra=7.0:tp=-2.0:offset=$target_offset:measured_i=$input_i:measured_lra=$input_lra:measured_tp=$input_tp:measured_thresh=$input_thresh:linear=true
    # skip normalization if partly invalid ("inf")
    if echo "$af" | grep -q inf ; then
        af=anull
    fi

    filter+=("[$((i*2+1)):a]$af[a$i];")
    streams+=("[vtitle$i][$((i*2)):a] [v$i][a$i]")
    i=$((i+1))
done
echo

echo "step [2/3] create intro"
ffmpeg -f lavfi -i "color=black:s=$RESOLUTION:r=$FRAMERATE:d=$INTRO_DURATION" -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100:d=$INTRO_DURATION" -shortest -c:v libx264 -c:a aac -y "$intro"

echo "step [3/3] encode video"
filter_complex="${filter[*]} ${streams[*]} concat=n=$((i*2)):v=1:a=1[v][a]"
filter_complex_script=$(mktemp)
echo "$filter_complex" > "$filter_complex_script"
cmd=(ffmpeg "${inputs[@]}" -filter_complex_script "$filter_complex_script" -map "[v]" -map "[a]" $FFMPEG_VIDEO_OPTIONS $FFMPEG_AUDIO_OPTIONS "$OUTPUT")
"${cmd[@]}"
rm -f "$intro"
rm -f "$filter_complex_script"
