#!/bin/bash

sudo cryptsetup luksOpen /dev/nvme0n1p3 cryptroot
sudo mount /dev/mapper/cryptroot /mnt/crypt
sudo firewall.sh
