# Scripts
Personal scripts that I use daily.

I nuked my home folder the other day and it's been painful to recover...

Turning over a new leaf and automating everything + triple backing up.

## Usage
- I typically clone to ~/scripts and add to path.
- If I want .desktop entries for easy execution I'll deploy with the included `install.sh`

## Streams
Some of the things in here are multi-media related. I have a directory of .strm files
which play on thinks like kodi. Then there are some wrapper scripts for when I do so
on my laptop

## Notes

### OS Stuff
- [firewall.sh](firewall.sh) : basic stateful firewall
- [mount-crypt.sh](mount-crypt.sh) : decrypt/mount encrypted partition
- [mount-ssh.sh](mount-ssh.sh) : mount remote drives via ssh
- [gentoo-cleanup-files.sh](gentoo-cleanup-files.sh) : clean gentoo cache
- [gentoo-update.sh](gentoo-update.sh) : gentoo update commands

### Multimedia
- [play-cams.sh](play-cams.sh) : logs into my reolink nvr and plays all feeds via mpv
- [play-stream.sh](play-stream.sh) : wrapper script for .strm files. I tend to use this for videos mainly designed for in-browser playing. But I like using mpv...
- [standardize-video-720p.sh](standardize-video-720p.sh) : complicated ffmpeg filter to basically do what the title says.
- [mpv/auto-refresh.lua](mpv/auto-refresh.lua) : mpv extension to allow me to loop media(typically gifs) but then periodically refresh from the source.
- [mpv/periodic-end-jump.lua](mpv/periodic-end-jump.lua) : mpv extension to periodically fast-forward to the end (streams like camera feeds)

### Weather...
- [nws-forecast.sh](nws-forecast.sh) : Pulls a detailed forecast plot image from the National Weather Service
- [nws-radar.sh](nws-radar.sh) : Displays a radar loop from the National Weather Service. Updating every 5mins.

