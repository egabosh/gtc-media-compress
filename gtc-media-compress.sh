#!/bin/bash

. /etc/bash/gaboshlib.include

g_nice

[ -z "$@" ] && g_yesno '!!! WARNING !!!

This program searches for media files (videos, audio and images) and converts them with the aim of saving them in a much more space-saving way.
The quality may or may not be noticeably worse.
The following things are done:

Videos
======
- Resolution is scaled to a maximum of either HD 720p or DVD 480p. Lower resolutions are not scaled.
- Maximum bit rate of 3600k based on the resolution or bit rate of the original video.
- Video codec HEVC (h265).
- Audio codec in videos AC3@384k (for 5.1 or more) and HeAACv2@48k (stereo) for less than 5.1. and HeAAC@24k is used for mono audio tracks.
- MP4 is used as the container format for video files.
- Subtitles are deleted if not necessary (forced). Necessary subtitles are inserted into the picture.

Audios
======
- MP4 is used as the container format for audio files.
- The codec used is HeAAC or HeAACv2 (for stereo).
- Multiple audio tracks (e.g. different languages in videos are deleted). Only one audio track or German if available is retained.
- More channels than two (e.g. 5.1) are reduced to stereo.
- Tags (including embedded images, ...), if present, are removed except for title, artist, album, date, track number and genre. 
- Special characters are replaced from remaining tags and a transliteration into Latin characters is added for Cyrillic tags.

Pictures
========
- JPEG is used as the image format. All non-JPEG images are converted to JPEG.
- Images are compressed by 85%.
- Images are downscaled to a maximum of 1080p.
- Images are “normalized” (colour equalization) to even improve the quality if necessary.
- A comment is added to the metadata (EXIF) to mark edited images so that they are not edited again.

Non-bash-compliant characters such as |, (,... are removed from file names.
The quality should be checked in advance with copies, e.g. in a test folder.

During processing, the CPU and possibly also the GPU are heavily used, which leads to increased power consumption and heat development.
Please do not run laptops on battery power, for example, and make sure that fans are not blocked or ventilation slots are not covered. 
Keep an eye on the electricity bill during longer periods of use.
The priority of the process is set to the lowest level so that “normal” work on the device should still be possible.

Do you really want to continue?
'

[ -z $DISPLAY ] || vidres=$(zenity --width=300 --height=300 --list --title="video resolution" --text="What is the maximum video resolution to be scaled to?" --column="Resolution" "HD 720p" "DVD 480p")
if [ -z "$vidres" ]
then 
 vidres="HD 720p"
fi

if [ -z "$@" ]
then
 mediapath=$(g_select-path "Specify search path for media files")
else
 mediapath="$@"
 [ -d "$mediapath" ] || [ -e "$mediapath" ] || g_echo_error_exit "$mediapath is neither a path nor a file"!
fi

[ -f /etc/gtc/share/rename-subs/nospecial ] && gtc-rename -r /etc/gtc/share/rename-subs/nospecial -p "$mediapath"
[ -f /root/rename-subs/nospecial ] && gtc-rename -r /root/rename-subs/nospecial -p "$mediapath"

g_echo "Searching for Images in $mediapath"
g_find_image "$mediapath" | while read image
do
 g_compress_image "$image"
done

g_echo "Searching for Audios in $mediapath"
g_find_audio "$mediapath" | while read audio
do
 g_compress_audio "$audio"
done

g_echo "Searching for Videos in $mediapath"
find /tmp -name "*.g_progressing" -type f -user $(whoami) -delete >/dev/null 2>&1
cputhreads=$(cat /proc/cpuinfo | grep processor | wc -l)
ffmpegparallel=$(echo "$cputhreads/3" | bc -l | xargs printf %.0f)
if [ $ffmpegparallel -gt 1 ]
then
 g_trap_exit="$g_trap_exit ; tmux kill-session -t g_ffmpegparallel >/dev/null 2>&1"
 trap "$g_trap_exit" EXIT
 echo $vidres | grep -q "480p" && dvdres="echo \$\$ >\"\$g_tmp\"/VID-SD"
 g_find_video "$mediapath" >~/.g_tmpvidlist
 vidnum=$(cat ~/.g_tmpvidlist | wc -l)
 [ $ffmpegparallel -gt $vidnum ] && ffmpegparallel=$vidnum
 g_echo "Doing $ffmpegparallel parallel encodings"
 seq $ffmpegparallel | while read num
 do
  if [ $num -eq 1 ]
  then
   if echo $vidres | grep -q "480p"
   then
    echo -n 'tmux new -s g_ffmpegparallel ". /etc/bash/gaboshlib.include; echo \$\$ >"\$g_tmp"/VID-SD; cat ~/.g_tmpvidlist | sort -R | while read video; do g_compress_video \"\$video\"; done" ' >$g_tmp/g_vidcmd
    echo -n '\; split-window -d ". /etc/bash/gaboshlib.include; echo \$\$ >"\$g_tmp"/VID-SD; cat ~/.g_tmpvidlist | sort -R | while read video; do g_compress_video \"\$video\"; done" \; select-layout even-vertical ' >>$g_tmp/g_vidcmd
   else
    echo -n 'tmux new -s g_ffmpegparallel ". /etc/bash/gaboshlib.include; cat ~/.g_tmpvidlist | sort -R | while read video; do g_compress_video \"\$video\"; done" ' >$g_tmp/g_vidcmd
   fi
  else
   if echo $vidres | grep -q "480p"
   then
    echo -n "\; split-window -d \" sleep $num ; " >>$g_tmp/g_vidcmd
    echo -n '. /etc/bash/gaboshlib.include; echo \$\$ >"\$g_tmp"/VID-SD; cat ~/.g_tmpvidlist | sort -R | while read video; do g_compress_video \"\$video\"; done" \; select-layout even-vertical ' >>$g_tmp/g_vidcmd
   else
    echo -n "\; split-window -d \" sleep $num ; " >>$g_tmp/g_vidcmd
    echo -n '. /etc/bash/gaboshlib.include; cat ~/.g_tmpvidlist | sort -R | while read video; do g_compress_video \"\$video\"; done" \; select-layout even-vertical ' >>$g_tmp/g_vidcmd
   fi
  fi
 done
 tmux kill-session -t g_ffmpegparallel >/dev/null 2>&1
 rm -f /tmp/*.g_progressing
 if [ -f $g_tmp/g_vidcmd ] 
 then
  cat $g_tmp/g_vidcmd
  . $g_tmp/g_vidcmd
 fi
 rm ~/.g_tmpvidlist
else
 echo $vidres | grep -q "480p" && echo $$ >"$g_tmp"/VID-SD
 g_find_video "$mediapath" | while read video
 do
  g_compress_video "$video"
 done
fi

