#!/bin/sh
# fixture daemon with a long-lived child (marker tree must be stopped as a whole)
sleep 300 &
wait
