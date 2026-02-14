#!/bin/bash

sshfs pi-router:/mnt/crypt/ /mnt/pi-router
autossh -M 0 -N -f -D 9051 jumpbox
