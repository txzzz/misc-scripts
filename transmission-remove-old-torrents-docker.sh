#!/bin/bash

user=""
pass=""
container="transmission"
days=30
transmission="/usr/bin/transmission-remote"

torrents="$(docker exec -t $container $transmission -n $user:$pass -l | grep '100%')"

OLDIFS=$IFS
IFS="
"
for torrent in $torrents; do
	id=$(echo $torrent | sed "s/^ *//g" | sed "s/ *100%.*//g")
	finished=$(date -d $(docker exec -t $container $transmission -n $user:$pass -t $id -i | grep 'Date finished' | sed -n -e 's/^.*Date finished: *//p') +%s)
	if (( ($(date +%s) - $finished) > ($days * 86400) )); then
		docker exec -t $container $transmission -n $user:$pass -t $id --remove-and-delete
	fi
done
IFS=$OLDIFS
