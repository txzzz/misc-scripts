#!/bin/bash

# Creates rewrite configuration for nginx or Apache from a CSV file containing
# a column for FROM addresses and a column for TO addresses. This script can
# also check (curl) the URLs to check if the redirects are correct.

# https://github.com/txzzz

unset -v webserver
unset -v hostname
unset -v outfile
skipssl=false
verbose=false
mode="generate"
delimiter=","
statuscode=301
num_correct=0
num_incorrect=0
num_missing=0

while getopts "tschvn:d:f:w:" opt; do
	case $opt in
		w)
			if [[ ! ($OPTARG == "nginx" || $OPTARG == "apache" ) ]]; then
				echo "Only nginx and apache are available!"
				exit 1
			fi
			webserver=$OPTARG
			;;
		t)
			statuscode=302
			;;
		s)
			skipssl=true
			;;
		c)
			mode="check"
			;;
		n)
			if [[ $outfile != "" ]]; then
				echo "Can't be combined with -f"
				exit 1
			fi
			hostname=$OPTARG
			;;
		f)
			if [[ $hostname != "" ]]; then
				echo "Can't be combined with -n"
				exit 1
			fi
			outfile=$OPTARG
			;;
		d)
			delimiter=$OPTARG
			;;
		v)
			verbose=true
			;;
		h)
			echo "Usage: ./redirects.sh <mode> [OPTIONS] <CSV file>"
			echo
			echo "Takes a CSV file and either generates a configuration file with rewrites (with -w <webserver>) or checks if URLs redirect correctly (with -c)"
			echo "There's two columns expected from the CSV file, first is URLs redirected from and the second is URLs that is redirected to"
			echo
			echo "Modes:"
			echo "  -w <webserver>  Which webserver to create configuration files for, available options are nginx and apache"
			echo "  -c              Checks the the URLs in the CSV file if they redirect correctly"
			echo
			echo "Options:"
			echo "  -n <hostname>   Hostname, will be used to generate outfile, <hostname>-rewrites.conf"
			echo "  -f <outfile>    Outfile, used as specified."
			echo "  -t              Temporary redirects, uses 302 instead of 301"
			echo "  -d <delimiter>  Delimiter used in the CSV file, ',' is used by default"
			echo "  -s              Don't automatically add https:// when missing. Also skips rewrites of http:// to https://"
			echo "  -v              Verbose output"
			echo "  -h              Shows this help text"
			exit
	esac
done

nginx_status=$([[ $statuscode == 301 ]] && echo "permanent" || echo "redirect")

if [[ $webserver == "" && $mode != "check" ]]; then
	echo "Please specify a webserver!"
	exit 1
fi

if [[ $hostname != "" ]]; then
	outfile="${hostname}-rewrites.conf"
fi

if [[ $outfile != "" && -e $outfile ]]; then
	echo "$outfile already exist"
	exit 1
fi

infile="${@: -1}"
if [[ ! -e $infile ]]; then
	echo "Please specify a CSV file"
	exit 1
fi

function has_query_params() {
	url=$1
	if ! [[ $url =~ \?[^=]+(=[^&]+)?(&[^=]+(=[^&]+)?)*$ ]]; then
		return 1
	fi
}

function is_file() {
	url=$1
	if ! [[ $url =~ /[^/]+\.[^/]{2,8}$ ]]; then
		return 1
	fi
}

function get_query() {
	url=$1
	echo "$url" | cut -d '?' -f2-
}

function rewrite_nginx() {
	from=$1
	to=$2
	if has_query_params "$from"; then
		echo "if (\$request_uri = \"${from}\") {"
		echo "  return ${statuscode} ${to};"
		echo "}"
	else
		echo "rewrite ^${from}$ ${to} ${nginx_status};"
	fi
}

function rewrite_apache() {
	from=$1
	from_escaped="$(echo "$from" | awk -F '?' '{print $1}' | sed -E 's/(\?|\.)/\\\1/g')"
	from_query="$(get_query "$from")"
	to=$2
	if has_query_params "$from"; then
		if ! has_query_params "$to"; then
			query="?"
		fi
		echo "RewriteCond %{QUERY_STRING} ^${from_query}$"
		echo "RewriteRule ^${from_escaped}$ ${to}${query} [R=${statuscode},L]"
	else
		echo "RedirectMatch ${statuscode} ^${from}$ ${to}"
	fi
}

function add_https() {
	if [[ $skipssl == true ]]; then
		return
	fi
	local url
	read url
	url=$(echo "$url" | sed -E 's|^http://|https://|')
	if [[ "${url:0:8}" != "https://" ]]; then
		url="https://${url}"
	fi
	echo "$url"
}

function generate_rewrites() {
	for line in $(cat "$infile"); do
		from=$(echo "$line" | awk -F $delimiter '{print $1}' | xargs | tr -d '\r' | sed -E 's|^https?://[^/]+||')
		if ! has_query_params "$from" && ! is_file "$from"; then
			if [[ "${from:0-1}" == "/" ]]; then
				from="${from}?"
			else
				from="${from}/?"
			fi
		fi
		to=$(echo "$line" | awk -F $delimiter '{print $2}' | xargs | tr -d '\r' | add_https)
		case $webserver in
			nginx)
				output="$(rewrite_nginx "$from" "$to")"
				;;
			apache)
				output="$(rewrite_apache "$from" "$to")"
				;;
		esac
		if [[ $outfile != "" ]]; then
			echo "$output" >> $outfile
		else
			echo "$output"
		fi
	done
}

function check_rewrites() {
	for line in $(cat "$infile"); do
		from=$(echo "$line" | awk -F $delimiter '{print $1}' | add_https | xargs | tr -d '\r')
		to=$(echo "$line" | awk -F $delimiter '{print $2}' | add_https | xargs | tr -d '\r')
		location=$(curl -Is "$from" | grep -i 'Location' | awk '{print $2}' | xargs | tr -d '\r')
		if [[ $to != $location && $location != "" ]]; then
			num_incorrect=$((num_incorrect+1))
			echo "Incorrect: ${from}"
		fi
		if [[ $location == "" ]]; then
			num_missing=$((num_missing+1))
			echo "Missing: ${from}"
		fi
		if [[ $to == $location ]]; then
			num_correct=$((num_correct+1))
			if [[ $verbose == true ]]; then
				echo "Correct: ${from}"
			fi
		fi
	done
	echo
	echo "Correct: ${num_correct}"
	echo "Incorrect: ${num_incorrect}"
	echo "Missing: ${num_missing}"
}

case $mode in
	generate)
		generate_rewrites
		;;
	check)
		check_rewrites
		;;
esac
