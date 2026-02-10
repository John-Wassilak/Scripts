#!/bin/bash

# by the time I'm done updating these, theres a new
# version, so only doing that periodically
EXCLUDE="--exclude chromium"

if [[ "$1" == "all" ]]; then
    EXCLUDE=""
fi

sudo bash -c "emerge --sync && \
              emerge --ask --update --deep --newuse $EXCLUDE @world && \
              emerge --depclean && \
              revdep-rebuild"

echo ""
echo "updating git repos"

cd -v /home/john/packages/dms
PRE_PULL=$(git rev-parse HEAD); git pull && [ "$PRE_PULL" != "$(git rev-parse HEAD)" ] && sudo make install

cd -v /home/john/packages/yt-dlp
git pull
