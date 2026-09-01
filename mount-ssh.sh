#!/bin/bash

sshfs pi-router:/mnt/crypt/ /mnt/pi-router
sshfs server:/home/john/ /mnt/server
sshfs jumpbox:/root/ /mnt/jumpbox
autossh -M 0 -N -f -D 9051 jumpbox
