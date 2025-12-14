#!/bin/bash
# 
# Simulate multiple threads downloading by forking many process
# Copyright 2016 Wanghong Lin 
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
# 	http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# 
# 
# Changelog
# v0.1        initial version
# v0.1.1      add output option
# v0.2        support both curl and wget, fix concat bug, show percentage and speed

slices=20
downloader=""

case $OSTYPE in
    *linux*) slices=$(grep -c processor /proc/cpuinfo) ;;
    *darwin*) slices=$(sysctl hw.ncpu | cut -d' ' -f2) ;;
    *cygwin*) slices=$NUMBER_OF_PROCESSORS ;;
    *) slices=20 ;;
esac

url=
output=

__ScriptVersion="v0.2"

#===  FUNCTION  ================================================================
#         NAME:  usage
#  DESCRIPTION:  Display usage information.
#===============================================================================
function usage ()
{
    echo "Usage :  $0 [options] url

    Options:
    -h|help       Display this message
    -v|version    Display script version
    -s|slice      How many slices the download task will split, default is $slices
    -o|output     Specify the output file name, use the guessing file name from url as output file name if not specify this option
    -d|downloader Specify downloader to use (curl or wget), auto-detect if not specified"

}    # ----------  end of function usage  ----------

#-----------------------------------------------------------------------
#  Handle command line arguments
#-----------------------------------------------------------------------

while getopts ":hvs:o:d:" opt
do
    case $opt in
	h|help     )  usage; exit 0   ;;
	v|version  )  echo "Multi tasks downloader for curl/wget, version $__ScriptVersion"; exit 0   ;;
	s|slice    )  slices=$OPTARG ;;
	o|output   )  output=$OPTARG ;;
	d|downloader ) downloader=$OPTARG ;;
	* )  echo -e "\n  Option does not exist : $OPTARG\n"
	    usage; exit 1   ;;
    esac    # --- end of case ---
done
shift $(($OPTIND-1))

url=${@: -1}

if ! [[ $url =~ ^https?://.*$ ]];then
    printf "\e[31mInvalid URL $url\e[0m\n"
    usage
    exit 1
fi

# Auto-detect downloader if not specified
if [ x$downloader = x ];then
    if command -v curl &> /dev/null; then
        downloader="curl"
    elif command -v wget &> /dev/null; then
        downloader="wget"
    else
        printf "\e[31mNeither curl nor wget found. Please install one of them.\e[0m\n"
        exit 1
    fi
fi

# Validate downloader choice
if [ "$downloader" != "curl" ] && [ "$downloader" != "wget" ];then
    printf "\e[31mInvalid downloader: $downloader. Must be 'curl' or 'wget'.\e[0m\n"
    exit 1
fi

if ! command -v $downloader &> /dev/null; then
    printf "\e[31m$downloader is not installed.\e[0m\n"
    exit 1
fi

url_no_query=${url%%\?*}
file_to_save=${url_no_query##*/}

[ x$output != x ] && file_to_save=$output

echo "Download $url to $file_to_save with $slices tasks using $downloader."

# Get content length based on downloader
if [ "$downloader" = "curl" ];then
    size_in_byte=$(curl -I "$url" 2>/dev/null | sed -n 's/\([Cc]ontent-[Ll]ength:\)\(.*\)/\2/p' | tr -d [[:space:]])
else
    size_in_byte=$(wget --spider --server-response "$url" 2>&1 | sed -n 's/.*[Cc]ontent-[Ll]ength: *\([0-9]*\).*/\1/p' | tail -1)
fi

if ! [[ $size_in_byte =~ ^[0-9]+$ ]];then
    printf "\e[31mCould not get content length, make sure your resource have content length response.\e[0m\n"
    exit 1
fi

size_per_slice=$(($size_in_byte/$slices))
let size_per_slice=${size_per_slice}+1  # avoid rounding issue

total_slice=${slices}
finished_slice=0
is_finished=0
function callback()
{
	finished_slice=$((finished_slice+1))
	if [ $finished_slice -eq $total_slice ];then
		# Concatenate all parts in order
		for s in $(seq 1 $total_slice)
		do
			if [ -f $$.$s ];then
				cat $$.$s >> "${file_to_save}"
				rm $$.$s
			fi
		done
		is_finished=1
	fi
}

function run()
{
	if [ "$downloader" = "curl" ];then
		curl -r $2-$3 "$url" -o $1 2>/dev/null && kill -n 10 $$ &
	else
		# wget uses different syntax for range requests
		if [ -z "$3" ];then
			wget --header="Range: bytes=$2-" "$url" -O $1 2>/dev/null && kill -n 10 $$ &
		else
			wget --header="Range: bytes=$2-$3" "$url" -O $1 2>/dev/null && kill -n 10 $$ &
		fi
	fi
}

trap callback 10

start_time=$(date +%s)
for s in $(seq $total_slice)
do
	begin=$((($s-1)*${size_per_slice}))
	if [ $begin -ne 0 ];then
		begin=$((begin+=1))
	fi
	end=$(($s*$size_per_slice))
	if [ $end -gt $size_in_byte ];then
		end=
	fi
	run $$.$s $begin $end
done

prev_kb=0
until [ $is_finished -eq 1 ]
do
	if [ -f $$.1 ];then
		total_kb=$(BLOCKSIZE=1024 du -k $$.* 2>/dev/null | awk '{t+=$1}END{printf "%d", t}')
		duration=$((`date +%s`-$start_time))
		
		# Calculate percentage (cap at 100%)
		downloaded_bytes=$((total_kb * 1024))
		percentage=$((downloaded_bytes * 100 / size_in_byte))
		[ $percentage -gt 100 ] && percentage=100
		
		# Calculate current speed (instantaneous)
		current_speed=$((total_kb - prev_kb))
		prev_kb=$total_kb
		
		# Calculate average speed
		if [ $duration -gt 0 ];then
			avg_speed=$(($total_kb/$duration))
			printf "\rProgress: %3d%% | Speed: %4d KiB/s | Avg: %4d KiB/s" $percentage $current_speed $avg_speed
		fi
	fi
	sleep 1
done

echo
