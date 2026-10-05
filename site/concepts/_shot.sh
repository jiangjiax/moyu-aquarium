#!/bin/bash
# usage: _shot.sh <file.html> <w> <h> <out>
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --hide-scrollbars \
  --window-size=${2:-1400},${3:-1000} --virtual-time-budget=15000 \
  --screenshot=$4 "http://127.0.0.1:8080/concepts/$1" >/dev/null 2>&1
