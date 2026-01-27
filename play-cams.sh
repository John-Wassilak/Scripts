#!/bin/bash

# note, assumes you saved nvr admin pass in secret-tool
#       assumes nvr ip is mapped to the hostname 'nvr'
#       _sub in the url is 'fluent' (lowest quality)
#       _ext in the url is 'balanced' (mid quality)
#       _main in the url is 'clear' (high quality"

NVR_PASS=$(secret-tool lookup play-cams pass)

response=$(curl 'http://nvr/cgi-bin/api.cgi?cmd=Login&token=null' \
		-X POST \
		-H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0' \
		-H 'Accept: */*' \
		-H 'Accept-Language: en-US,en;q=0.5' \
		-H 'Accept-Encoding: gzip, deflate' \
		-H 'Content-Type: application/json' \
		-H 'X-Requested-With: XMLHttpRequest' \
		-H 'Origin: http://nvr' \
		-H 'DNT: 1' \
		-H 'Sec-GPC: 1' \
		-H 'Connection: keep-alive' \
		-H 'Referer: http://nvr/' \
		-H 'Priority: u=0' \
		--data-raw "[{\"cmd\":\"Login\",\"action\":0,\"param\":{\"User\":{\"userName\":\"admin\",\"password\":\"$NVR_PASS\"}}}]")

token_name=$(echo "$response" | jq -r '.[0].value.Token.name')

for i in {0..6}; do
    nohup mpv --mute=yes "http://nvr/flv?app=bcs&stream=channel${i}_sub.bcs&token=$token_name" > /dev/null 2>&1 &
done
