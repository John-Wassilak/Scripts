INPUT="alsa_output.usb-C-Media_Electronics_Inc._ThinkPad_OneLink_Plus_Dock_Audio-00.analog-stereo.monitor"

ffmpeg -f pulse -i $INPUT -c:a libmp3lame -b:a 192k output.mp3
