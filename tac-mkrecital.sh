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

# =============================================================================
# Setup playlist-# dir
pldir=playlist; n=1
while [[ -d "$pldir-$n" ]] ; do n=$(($n+1)) ; done
pldir=$pldir-$n
mkdir -p "$pldir"

# =============================================================================
# Get Playlist Info
pljson=$pldir/playlist.json
(set -x ; youtube-dl --skip-download --flat-playlist -J $plurl > $pljson)

# =============================================================================
# Download Playlist Videos
(set -x ; youtube-dl --abort-on-error -f mp4 -o "$pldir/%(title)s.orig.%(ext)s" $plurl)

# =============================================================================
# Annotate Videos with Challenge # and Title
(cd $pldir; ls TAC* | while IFS= read f; do
  fname=$(basename "$f" .orig.mp4)
  annfile="$fname.annotated.mp4"
  tacnum=$(echo "$fname" | cut -f1 -d- | xargs)
  tacname=$(echo "$fname" | cut -f2 -d- | xargs)

  # Why < /dev/null? https://unix.stackexchange.com/a/36411
  #  prevents ffmpeg from reading from standard input which makes it not work in loops
  (set -x ; < /dev/null $ffmpeg -i "$f" -vf "drawtext=text='$tacnum
$tacname':$ffmpeg_drawops" -c:a copy "$annfile")
done)

# =============================================================================
# Create list of annotated videos to combine
pljoin=$pldir/pljoin.txt
rm -f $pljoin
(cd $pldir; ls TAC*annotated.mp4 | while IFS= read f; do 
  echo "file '$f'" >> $(basename $pljoin);
done)

# =============================================================================
# Combine videos
pltitle="$(jq -r '.title' $pljson)"
plvideo="$pldir/$pltitle.mp4"
(set -x ; $ffmpeg -safe 0 -f concat -i $pljoin -c copy "$plvideo")

# =============================================================================
# Create chapter lines for video description
pltitles=$pldir/pltitles.txt
pldurations=$pldir/pldurations.txt
pltimes=$pldir/pltimes.txt
plchapters=$pldir/$pltitle.chapters.txt
jq -r '.entries[].title' $pljson > $pltitles
jq -r '.entries[].duration' $pljson > $pldurations
t=0; while IFS= read dur; do 
  # YouTube chapter format: 0:12, 4:03, ... (use single digits < 10)
  echo $(date -u -r $t +"%M:%S" | sed "s/^0\([0-9]\)/\1/") >> $pltimes; 
  t=$(($t + $dur));
done < $pldurations
paste -d' - ' $pltimes $pltitles > $plchapters
rm $pltitles $pldurations $pltimes

# =============================================================================
# Report results
echo "====================================="
echo "Playlist: $(jq -r '.title' $pljson)"
echo "Video: $plvideo"
echo "Chapters:"
cat $plchapters
