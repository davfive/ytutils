#!/usr/bin/env bash -e
# This script takes a youtube playlist and merges it into one video file
# It add the filename to the top right (TAC YYYYMMW#D# - <Challenge Name> @BPM)
# brew install youtube-dl
# brew install ffmpeg
# brew install jq
USAGE="$0 https://www.youtube.com/playlist?list=..."
if [ $# -ne 1 ]; then echo "Error: No playlist specified"; echo $USAGE; exit 1; fi
plurl=$1

ffmpeg="ffmpeg -hide_banner -loglevel error"
ffmpeg_drawops="x=w-tw-10:y=10:fontsize=24:fontcolor=white:line_spacing=10:box=1:boxborderw=10:boxcolor=black@0.4"
ffduration="ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 -sexagesimal"

# Setup playlist-# dir
pldir=playlist; n=1
while [[ -d "$pldir-$n" ]] ; do n=$(($n+1)) ; done
pldir=$pldir-5 #$n
mkdir -p "$pldir"

# Get Playlist Info
echo; echo "## Getting playlist info ..."
pljson=$pldir/playlist.json
(set -x ; youtube-dl --skip-download --flat-playlist -J $plurl > $pljson)

# Download Playlist Videos
echo; echo "## Downloading playlist videos ..."
#(set -x ; youtube-dl --abort-on-error -f mp4 -o "$pldir/%(title)s.%(ext)s" $plurl)

# Video files
pltitle="$(jq -r '.title' $pljson)"
plvideo="$pltitle.mp4"          # Final video
plcurrvid="$pltitle.curr.mp4"   # Current video (with previous concats)
plnextvid="$pltitle.next.mp4"   # Nextvideo to concatenate with
plcatfiles="plcatfiles.txt"     # File to concatenate

pldesc="$pltitle.desc.txt"
cat <<EOCAT > "$pldir/$pldesc"
A monthly TAC Daily Challenge "Recital" from my recordings
From Playlist: $pltitle
$plurl

Challenges:
EOCAT

# Foreach video, annotate, concatenate, and mark start of chapter
plchapstart=00:00
(cd $pldir; ls TAC*.mp4 | while IFS= read f; do
  echo; echo "## Adding '$f' ..."

  # Filename format: TAC YYYYMMW#D# - <challenge-name> @<#bpm>.mp4
  fname=$(basename "$f" .mp4)
  tacnum=$(echo "$fname" | cut -f1 -d- | xargs)
  tacname=$(echo "$fname" | cut -f2 -d- | xargs)

  # Create Annotated Video to concatenate next
  #   Why < /dev/null? https://unix.stackexchange.com/a/36411
  #   prevents ffmpeg from reading from standard input which makes it not work in loops
  (set -x; < /dev/null $ffmpeg -i "$f" -vf "drawtext=text='$tacnum
$tacname':$ffmpeg_drawops" -c:a copy "$plnextvid")

  # Concatenate to end of video (and rotate video files)
  [[ -f "$plcurrvid" ]] && echo "file '$plcurrvid'" >> $plcatfiles
  [[ -f "$plnextvid" ]] && echo "file '$plnextvid'" >> $plcatfiles
  (set -x; < /dev/null $ffmpeg -safe 0 -f concat -i "$plcatfiles" -c copy "$plvideo")
  rm -f "$plcurrvid" "$plnextvid" "$plcatfiles"
  mv "$plvideo" "$plcurrvid" # setup for next loop

  # Track chapter starts (previous end is this round's start, then setup for next loop)
  echo "$plchapstart $fname" >> "$pldesc"
  plchapstart=$($ffduration "$plcurrvid" | cut -d. -f1 | cut -d: -f2-) # 0:00:00.000000 to 00:00
done)

mv "$pldir/$plcurrvid" "$pldir/$plvideo" # store final video
echo
(set -x; cat "$pldir/$pldesc")
