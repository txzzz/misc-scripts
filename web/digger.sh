#!/bin/bash

if [[ $1 == '-h' || $1 == '--help' ]]; then
	echo "Usage: ./digger.sh <comma or space separated list of hostnames>"
	echo "Does a DNS lookup on each hostname in the list and displays reverse DNS if the IP has it."
	exit
fi

domains=$(echo $@ | tr ',' ' ' | xargs)

for domain in $domains; do
	domain=$(echo $domain | sed -E 's+^https?://++' | cut -d '/' -f1)
        echo "$ dig +short ${domain}"
        ips="$(dig +short $domain | tr '\n' ' ' | tr -d '\r')"
        for ip in $ips; do
                if [[ $ip == "" ]]; then
                        echo "No A record!"
                        continue
                fi
                if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                        reverse=$(dig +short -x $ip)
                        echo "${ip} ${reverse}"
                fi
        done
done
