# video-concat.sh

Concatenate (mobile) video files in different formats to a uniform 16/9 mp4 format
that is small and simple enough to be played by TVs. Extra features:

- normalize audio volume
- short intro with filename between videos
- rotation of videos (portrait vs landscape) is respected

Usage:

```sh
OUTPUT=out.mp4 $0 in1.mp4 in2.mp4 ...
```
