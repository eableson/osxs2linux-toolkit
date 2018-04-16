#!/bin/bash
# odmig-dns-extract.sh
###############################################################################
# DESCRIPTION
# script to extract DNS records from an OS X Server configuration, do some
# basic sanity checks and create simplified files for input into a SAMBA4
# AD environment
#
# Syntax
# odmig-dns-extract.sh [domain] [server]

###############################################################################
# AUTHOR
# erik@infrageeks.com
# http://infrageeks.com/

###############################################################################
# CHANGE LOG
# 2018-04-13 : EWA : Initial version


###############################################################################
# FUNCTIONS

# Usage information and verification
usage() {
cat <<EOT
usage: odmig-dns-extract.sh [domain] [server]
        eg. odmig-dns-extract.sh infrageeks.lan 192.168.2.1
EOT
}

chop() {
	echo ${1::-1}
}


###############################################################################
###############################################################################
# INIT - Main script
###############################################################################
###############################################################################

if [ $# -ne 2 ]; then
  usage
  exit 1
fi

#######################################
# Arguments
domain=$1
dnsserver=$2

>&2 echo "Domain: $domain"
>&2 echo "Server: $dnsserver"

#######################################
# import the raw zone file
rawdomain=`dig AXFR $domain @$dnsserver`


#######################################
# basic device types and conditions
livearray=()
deadarray=()
cnamearray=()
mxarray=()

###############################################################################
# Main processing

while read -r line; do
	# echo "Checking: $line"
	if [[ $line =~ ';' ]]
	then
		>&2 echo "Commented line: $line"
	else
		linearray=($line)
		objectcount=${#linearray[@]}
		IFS='.' read -r -a namearray <<< ${linearray[0]}
		name=${namearray[0]}

		if [[ $objectcount -eq 5 ]]
		then ########## CNAME ##########
			 # I don't check if CNAME references are online, they just get copied in
			if [[ ${linearray[3]} == 'CNAME' ]]
			then
				cname=$(chop ${linearray[4]})
				cnamearray+=("$name ${linearray[3]} $cname")
			elif [[ ${linearray[3]} == 'NS' ]]
			then
				>&2 echo "Skipping NS Record: $line"
			else ########## OTHER RECORDS with 5 attributes ##########
				 # Check if they're pingable or not
				alive=""
				>&2 echo "Checking: $name"
				ping -c 2 ${linearray[4]} &> /dev/null; alive=$?
				if [[ $alive -eq 0 ]]
				then
					# Object is alive
					livearray+=("$name ${linearray[3]} ${linearray[4]}")
				else
					# No response or error
					deadarray+=("dead? $name ${linearray[3]} ${linearray[4]}")
				fi
			
				# echo $alive $name ${linearray[3]} ${linearray[4]}
			
			fi

		fi

		if [[ $objectcount -eq 6 ]] 
		then ########## Check for MX ##########
			if [[ ${linearray[3]} == 'MX' ]]
			then
				name=$(chop ${linearray[0]})
				server=$(chop ${linearray[5]})
				mxarray+=("$name ${linearray[3]} ${linearray[4]} $server")
			fi
		fi

		# echo $line
	fi

done <<< "$rawdomain"

###############################################################################
# Write everything to STDOUT (best bet is pipe to a file)

for line in "${deadarray[@]}"
do
  echo $line
done

for line in "${cnamearray[@]}"
do
  echo $line
done

for line in "${livearray[@]}"
do
  echo $line
done

for line in "${mxarray[@]}"
do
  echo $line
done


# lines=($rawdomain)

# echo $lines[0]


