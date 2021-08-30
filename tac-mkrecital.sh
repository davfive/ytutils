#!/usr/bin/env bash -e
# My TAC Challenge Recordings YT Playlist Combiners
#
# I study guitar with Tony's Acoustic Challenge (TAC) which can
# be found at https://tonypolecastro.com. Part of the lessons 
# involve a weekdayly challenge, which when I'm comfortable with it,
# I upload a my recording of the to my YT playlist for that month.
#
# This script takes the recordings from that playlist, annotates them
# with the challenge number and challenge name. I have a consistent
# naming convention for my recording titles so I can use them for the
# annotation information I put in the video. The title format is
#   TAC <challenge#> - <challenge-name> @<my-bpm>
#   TAC 202108W1D2 - Challenge Name @60
#
# The output of this program will go into a subdirectory named playlist-#
# that has the following files:
#   • <playlist-name>.mp4      # The full concatenated video
#   • <playlist-name>.desc.txt # The description to use for the video
#                              # including timestamped chapter index
#   • *.mp4                    # All of the videos in the playlist
#
# Prerequisites:
#   brew install youtube-dl ffmpeg jq
# Usage:
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
(set -x ; youtube-dl --abort-on-error -f mp4 -o "$pldir/%(title)s.%(ext)s" $plurl)

# Video files
pltitle="$(jq -r '.title' $pljson | xargs)"
plvideo="$pltitle.mp4"          # Final video
plcurrvid="$pltitle.curr.mp4"   # Current video (with previous concats)
plnextvid="$pltitle.next.mp4"   # Nextvideo to concatenate with
plcatfiles="plcatfiles.txt"     # File to concatenate

pldesc="$pltitle.desc.txt"
cat <<EOCAT > "$pldir/$pldesc"
A monthly TAC Daily Challenge "Recital" from my recordings in the playlist '$pltitle' at $plurl.
$plurl

Tony's Acoustic Challenge (TAC) can be found at https://tonypolecastro.com.

This video and the chapters markers below were generated using youtube-dl and ffmpeg. The script can be found at https://github.com/davfive/ytutils/blob/main/tac-mkrecital.sh.
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
echo "Upload This: $pldir/$plvideo"
echo "Description: $pldir/$pldesc"
(set -x; cat "$pldir/$pldesc")