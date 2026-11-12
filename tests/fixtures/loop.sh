#!/bin/sh
# fixture daemon: stays alive, logs one line on start
[ -n "$KM_FX_LOG" ] && echo "up $$" >>"$KM_FX_LOG"
while :; do sleep 1; done
