#!/bin/sh
# fixture daemon that ignores TERM (stop must escalate to KILL)
trap '' TERM
while :; do sleep 1; done
