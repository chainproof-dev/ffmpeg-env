Build: debug
Commit: 5d85b7bfb2b024fd367ae3a938b4ac46a39e3a26

Usage:
  cd debug
  source ./RUN_ENV.sh
  ./bin/ffmpeg -version
  ./bin/ffprobe -version

Common tests:
  ./bin/ffprobe -v trace poc.oma
  ./bin/ffprobe -v trace matroska_nan.mkv
  ./bin/ffprobe -v error cmov_oom.mp4
  ./bin/videogen /tmp/out.yuv 65536 65536
