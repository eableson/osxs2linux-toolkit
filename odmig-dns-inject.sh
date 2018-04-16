#!/bin/bash
# odmig-dns-inject.sh
###############################################################################
# DESCRIPTION
# script to inject DNS records from a file with the basic structure of:
# shortname\wtype\waddress and add the entry into a SAMBA4 DNS setup. The script
# should be run from one of the DCs that has the kerberos client tools installed
# along with the samba-tool. In order for the kerberos authentication to work
# properly, use the actual IP address or name of a server, *not* localhost or 
# 127.0.0.1
#
# Syntax
# odmig-dns-inject.sh [filename] [server] [domainsuffix]

###############################################################################
# AUTHOR
# erik@infrageeks.com
# http://infrageeks.com/

###############################################################################
# CHANGE LOG
# 2018-04-16 : EWA : Initial version


###############################################################################
# FUNCTIONS

# Usage information and verification
usage() {
cat <<EOT
usage: odmig-dns-inject.sh [filename] [server] [domainsuffix]
        eg. odmig-dns-inject.sh infrageeks.lan.txt 192.168.2.1 infrageeks.lan
EOT
}

chop() {
	echo ${1::-1}
}

# checks an IP to see if it is in a private network space according to RFC1918
isprivate() {
	# >&2 echo "  Checking IP:  ${1::-1}"
	regex="^(192.168|172|10)"
	if [[ ${1::-1} =~ $regex ]]
	then
		echo 1
	else
		echo 0
	fi
}

# takes an IP address and returns the prefix key to lookup the associated in.arpa zone
getreversekey() {
	ipaddress=${1::-1}
	regex192="192\.168\.[0-9]+"
	regex172="^172\.[0-9]+"
	if [[ $ipaddress =~ $regex192 ]] 
	then
		prefix=${BASH_REMATCH[0]}
	elif [[ $ipaddress =~ $regex172 ]]
	then
		prefix=${BASH_REMATCH[0]}
	elif [[ ${ipaddress:0:3} =~ "10." ]]
	then
		prefix="10"
	fi
	echo "$prefix"
}


###############################################################################
###############################################################################
# INIT - Main script
###############################################################################
###############################################################################

if [ $# -ne 3 ]; then
  usage
  exit 1
fi

#######################################
# Arguments
inputfile=$1
server=$2
domainsuffix=$3

>&2 echo "Input File: $inputfile"
>&2 echo "Server: $server"
>&2 echo "Domain: $domainsuffix"

#######################################
# import the raw zone file


#######################################
# Initialize the kerberos connection for the administrator account
# kinit administrator

#######################################
# basic device types and conditions
declare -A inarpa


###############################################################################
# Main processing


# Check for and create reverse lookup zones
>&2 echo "#######################################"
>&2 echo "Checking for reverse lookup domains in private address spaces"

while read -r line; do
	# >&2	echo "Checking: $line"
	if [[ $line =~ ';|dead\?' ]]
	then
		>&2 echo "Skipping line: $line"
	else
		linearray=($line)
		objectcount=${#linearray[@]}
		shortname=${linearray[0]}
		type=${linearray[1]}
		if [[ $type == 'A' ]]
		then
			ipaddress=${linearray[2]}
			# >&2 echo "  This is an A record"
			if [[ $(isprivate $ipaddress) == 1 ]]
			then
				# >&2 echo "  private address space - recording prefix"
				reversezone=""
				regex192="192\.168\.[0-9]+"
				regex172="^172\.[0-9]+"
				if [[ $ipaddress =~ $regex192 ]] 
				then
					# >&2 echo "  192.168.x subnet"
					prefix=${BASH_REMATCH[0]}
				    
				    # >&2 echo "  Prefix: $prefix"
				    IFS='.' read -r -a octets <<< "$prefix"
				    # >&2 echo "  Extracted IP octets: ${octets[@]}"
				    for ((i=${#octets[@]}-1; i>=0; i--)) ; do
				    	# >&2 echo "    appending: ${octets[$i]}."
				    	reversezone+="${octets[$i]}."
				    done
				    
				    reversezone+="in-addr.arpa"
				    # >&2 echo " calculated reversezone: $reversezone"
					inarpa["$prefix"]="$reversezone"
				elif [[ $ipaddress =~ $regex172 ]]
				then
					prefix=${BASH_REMATCH[0]}
				    IFS='.' read -r -a octets <<< "$prefix"
				    if [[ ${octets[1]} -ge 16 ]] && [[ ${octets[1]} -le 31 ]]
				    then
						# >&2 echo "  reserved 172.z.x.y subnet"
						inarpa["$prefix"]="${octets[1]}.172.in-addr.arpa"
					fi
				elif [[ ${ipaddress:0:3} =~ "10." ]]
				then
					prefix="10"
					# >&2 echo "  reserved 10.z.x.y subnet"
					inarpa["$prefix"]="10.in-addr.arpa"
				fi
			fi
		fi
	fi
done < $inputfile

zonelist=`samba-tool dns zonelist ubu-dc01 -k YES | grep in-addr.arpa `

#######################################
# Checking for the existence of the required reverse zones and creating them as
# required.

for i in "${!inarpa[@]}"
do
	>&2 echo "Checking for: ${inarpa[$i]}"
	if [[ $zonelist =~ ": ${inarpa[$i]}" ]]
	then
		>&2 echo "  ${inarpa[$i]} exists"
	else
		>&2 echo "  Creating ${inarpa[$i]}"
		cmd="samba-tool dns zonecreate $server ${inarpa[$i]} -k YES"
		echo $cmd
		eval $cmd
	fi
  # >&2 echo "prefix  : $i"
  # >&2 echo "zone    : ${inarpa[$i]}"
done

#######################################
# Checking for the existence of the zone that we will be putting entries into and 
# creating it as required. Generally, you should be using the built-in domain zone if
# you are doing a simple migration

>&2 echo "#######################################"
>&2 echo "Checking for the destination import domain: $domainsuffix"

zonelist=`samba-tool dns zonelist ubu-dc01 -k YES | grep pszZoneName | grep -v _ | grep ": $domainsuffix" | wc -l `

if [[ $zonelist == 0 ]]
then
	cmd="samba-tool dns zonecreate $server $domainsuffix -k YES"
	echo $cmd
	eval $cmd
else
	>&2 echo "The domain: $domainsuffix already exists"
fi


#######################################
# Main import 

>&2 echo "#######################################"
>&2 echo "Starting to create entries"

while read -r line; do
	# >&2	echo "Checking: $line"
	if [[ $line =~ ';|dead\?' ]]
	then
		>&2 echo "Skipping line: $line"
	else
		linearray=($line)
		objectcount=${#linearray[@]}
		shortname=${linearray[0]}
		type=${linearray[1]}
		if [[ $type == 'A' ]]
		then
			ipaddress=${linearray[2]}
			entryexists=`host $shortname.$domainsuffix $server | grep 'has address' | wc -l`
			if [[ $entryexists == 1 ]]
			then
				>&2 echo "  $shortname.$domainsuffix already exists"
			else
				>&2 echo "  Creating entry for $shortname.$domainsuffix"
				cmd="samba-tool dns add $server $domainsuffix $shortname A $ipaddress -k YES"
				echo $cmd
				eval $cmd
			fi

			if [[ $(isprivate $ipaddress) == 1 ]]
			then
				entryexists=`host $ipaddress $server | grep 'domain name pointer' | wc -l`
				if [[ $entryexists == 1 ]]
				then
					>&2 echo "  $shortname.$domainsuffix already has a reverse entry"
				else
					reversezone=$(getreversekey $ipaddress)
					IFS='.' read -r -a reversezonearray <<< "$reversezone"
					>&2 echo "reversezone: $reversezone"
					>&2 echo "reversezonearray:${reversezonearray[@]}"
					reversezonedepth=${#reversezonearray[@]}
					>&2 echo "reversezonedepth: $reversezonedepth"
					IFS='.' read -r -a octets <<< "$ipaddress"
					>&2 echo "octets: ${octets[@]}"
					ipsuffix=""
					for ((i=3; i>=$reversezonedepth; i--)); do
				    	ipsuffix+="${octets[$i]}."
				    done
				    >&2 echo "ipsuffix: $ipsuffix"
				    id=$(chop $ipsuffix)
				    >&2 echo "id: $id"
					# >&2 echo "Entry belongs in: ${inarpa[$reversezone]}"
					>&2 echo "  Creating reverse entry for $shortname.$domainsuffix ($ipaddress)"
					cmd="samba-tool dns add $server ${inarpa[$reversezone]} $id PTR $shortname.$domainsuffix -k YES"
					echo $cmd
					eval $cmd
				fi
			fi
		elif [[ $type == 'CNAME' ]]
		then
			a_record=${linearray[2]}
			entryexists=`host $shortname.$domainsuffix $server | grep 'has address' | wc -l`
			if [[ $entryexists == 1 ]]
			then
				>&2 echo "  $shortname.$domainsuffix already exists"
			else
				>&2 echo "  Creating CNAME entry for $shortname.$domainsuffix"
				cmd="samba-tool dns add $server $domainsuffix $shortname CNAME $a_record -k YES"
				echo $cmd
				eval $cmd
			fi
		elif [[ $type == 'MX' ]]
		then
			priority=${linearray[2]}
			mailserver=${linearray[3]}
			mxexists=`host -t MX $domainsuffix | grep "handled by" | grep $mailserver | wc -l `
			if [[ $mxexists -gt 0 ]]
			then
				>&2 echo "  $mailserver MX record already exists"
			else
				>&2 echo "  Creating MX entry for $shortname"
				cmd="samba-tool dns add $server $domainsuffix $shortname MX '$mailserver $priority' -k YES"
				echo $cmd
				eval $cmd
			fi

		fi
	fi
done < $inputfile



# 	if Skipping line: $linethen
# 		>&2 echo "Commented line: $line"
# 	else
#
#
# 		linearray=($line)
# 		objectcount=${#linearray[@]}
# 		IFS='.' read -r -a namearray <<< ${linearray[0]}
# 		name=${namearray[0]}
# 
# 		if [[ $objectcount -eq 5 ]]
# 		then ########## CNAME ##########
# 			 # I don't check if CNAME references are online, they just get copied in
# 			if [[ ${linearray[3]} == 'CNAME' ]]
# 			then
# 				cname=$(chop ${linearray[4]})
# 				cnamearray+=("$name ${linearray[3]} $cname")
# 			elif [[ ${linearray[3]} == 'NS' ]]
# 			then
# 				>&2 echo "Skipping NS Record: $line"
# 			else ########## OTHER RECORDS with 5 attributes ##########
# 				 # Check if they're pingable or not
# 				alive=""
# 				>&2 echo "Checking: $name"
# 				ping -c 2 ${linearray[4]} &> /dev/null; alive=$?
# 				if [[ $alive -eq 0 ]]
# 				then
# 					# Object is alive
# 					livearray+=("$name ${linearray[3]} ${linearray[4]}")
# 				else
# 					# No response or error
# 					deadarray+=("dead? $name ${linearray[3]} ${linearray[4]}")
# 				fi
# 			
# 				# echo $alive $name ${linearray[3]} ${linearray[4]}
# 			
# 			fi
# 
# 		fi
# 
# 		if [[ $objectcount -eq 6 ]] 
# 		then ########## Check for MX ##########
# 			if [[ ${linearray[3]} == 'MX' ]]
# 			then
# 				name=$(chop ${linearray[0]})
# 				server=$(chop ${linearray[5]})
# 				mxarray+=("$name ${linearray[3]} ${linearray[4]} $server")
# 			fi
# 		fi
# 
# 		# echo $line
# 	fi





