#!/bin/sh

transmission="/usr/bin/transmission-remote"
user=""
pass=""

OLDIFS=$IFS
IFS="
"
for torrent in $($transmission -n $user:$pass -l | grep 100%); do
	id=$(echo $torrent | sed "s/^ *//g" | sed "s/ *100%.*//g")
	finished=$(date -d $($transmission -n $user:$pass -t $id -i | grep 'Date finished' | sed -n -e 's/^.*Date finished: *//p') +%s)
	now=$(date +%s)
	if [ $(( $now - $finished )) -gt 2592000 ]; then
		$transmission -n $user:$pass -t $id --remove-and-delete
	fi
done
IFS=$OLDIFS
