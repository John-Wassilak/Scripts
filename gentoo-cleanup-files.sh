#!/bin/bash

# cleanup the trash
# distfiles bit might be redundant.

sudo bash -c "eclean distfiles && \
              eclean packages && \
              rm -rf /var/tmp/portage/* &&
              rm -rf /var/cache/distfiles/*"
