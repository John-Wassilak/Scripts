#!/bin/bash

sudo bash -c 'emerge --sync && \
              emerge --ask --update --deep --newuse --exclude chromium @world && \
              emerge --depclean && \
              revdep-rebuild'
