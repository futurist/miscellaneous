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
# v0.2.1      add -t|tool option, add fallback to single-threaded download on errors
# v0.2.2      add support for passing extra args to curl/wget via -x option or env vars
# v0.3        remove -d flag, fix stuck at 100%, add temp. prefix, cleanup old temp files

slices=20
downloader=""
stall_timeout=30  # seconds without progress before fallback to single-threaded
extra_args=""  # additional arguments to pass to curl/wget

case $OSTYPE in
    *linux*) slices=$(grep -c processor /proc/cpuinfo) ;;
    *darwin*) slices=$(sysctl hw.ncpu | cut -d' ' -f2) ;;
    *cygwin*) slices=$NUMBER_OF_PROCESSORS ;;
    *) slices=20 ;;
esac

url=
output=

__ScriptVersion="v0.3"

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
    -t|tool       Specify download tool to use (curl or wget), auto-detect if not specified
    -x|extra-args Extra arguments to pass to curl/wget (e.g., '--connect-timeout 10')
                  Note: Arguments are word-split, so quote properly if needed
    
    Environment Variables:
    CURL_OPTS     Extra options to pass to curl (when curl is used)
    WGET_OPTS     Extra options to pass to wget (when wget is used)
    
    Examples:
    ./mcurl.sh -x '--connect-timeout 10 --max-time 30' URL
    CURL_OPTS='--connect-timeout 5' ./mcurl.sh URL
    ./mcurl.sh -t wget -x '--timeout=10 --tries=3' URL"

}    # ----------  end of function usage  ----------

#-----------------------------------------------------------------------
#  Handle command line arguments
#-----------------------------------------------------------------------

while getopts ":hvs:o:t:x:" opt
do
    case $opt in
	h|help     )  usage; exit 0   ;;
	v|version  )  echo "Multi tasks downloader for curl/wget, version $__ScriptVersion"; exit 0   ;;
	s|slice    )  slices=$OPTARG ;;
	o|output   )  output=$OPTARG ;;
	t|tool     ) downloader=$OPTARG ;;
	x|extra-args ) extra_args=$OPTARG ;;
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

# Merge extra arguments from environment variables and command line
if [ "$downloader" = "curl" ];then
    tool_extra_opts="${CURL_OPTS:-}"
else
    tool_extra_opts="${WGET_OPTS:-}"
fi

# Command-line extra args take precedence and are added to env vars
if [ -n "$extra_args" ];then
    if [ -n "$tool_extra_opts" ];then
        tool_extra_opts="$tool_extra_opts $extra_args"
    else
        tool_extra_opts="$extra_args"
    fi
fi

# Note: tool_extra_opts is intentionally used unquoted in command executions
# to allow word splitting for multiple arguments (e.g., "--timeout 5" becomes two args)

url_no_query=${url%%\?*}
file_to_save=${url_no_query##*/}

[ x$output != x ] && file_to_save=$output

# Cleanup any existing temp files from previous runs
# First check if the process that created them is still running
temp_prefix="temp.$$"
shopt -s nullglob
for temp_file in temp.*.*; do
    if [ -f "$temp_file" ]; then
        # Extract PID from filename (format: temp.PID.slice)
        old_pid=$(echo "$temp_file" | cut -d. -f2)
        if [ -n "$old_pid" ] && ! kill -0 "$old_pid" 2>/dev/null; then
            # Process doesn't exist, safe to clean up
            rm -f "temp.$old_pid."* 2>/dev/null
        fi
    fi
done
shopt -u nullglob

# Clean up our own temp files from any previous failed runs
rm -f "temp.$$."* 2>/dev/null

echo "Download $url to $file_to_save with $slices tasks using $downloader."
[ -n "$tool_extra_opts" ] && echo "Extra options: $tool_extra_opts"

# Function to perform single-threaded download fallback
function fallback_download()
{
	if [ "$downloader" = "curl" ];then
		curl $tool_extra_opts "$url" -o "${file_to_save}"
	else
		wget $tool_extra_opts "$url" -O "${file_to_save}"
	fi
	exit $?
}

# Get content length based on downloader
if [ "$downloader" = "curl" ];then
    size_in_byte=$(curl $tool_extra_opts -I "$url" 2>/dev/null | sed -n 's/\([Cc]ontent-[Ll]ength:\)\(.*\)/\2/p' | tr -d [[:space:]])
else
    size_in_byte=$(wget $tool_extra_opts --spider --server-response "$url" 2>&1 | sed -n 's/.*[Cc]ontent-[Ll]ength: *\([0-9]*\).*/\1/p' | tail -1)
fi

# Fallback to single-threaded download if content length is not available
if ! [[ $size_in_byte =~ ^[0-9]+$ ]];then
    printf "\e[33mCould not get content length, falling back to single-threaded download.\e[0m\n"
    fallback_download
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
			if [ -f "temp.$$.$s" ];then
				cat "temp.$$.$s" >> "${file_to_save}"
				rm "temp.$$.$s"
			fi
		done
		is_finished=1
	fi
}

function run()
{
	if [ "$downloader" = "curl" ];then
		curl $tool_extra_opts -r "$2-$3" "$url" -o "$1" 2>/dev/null && kill -n 10 $$ &
	else
		# wget uses different syntax for range requests
		if [ -z "$3" ];then
			wget $tool_extra_opts --header="Range: bytes=$2-" "$url" -O "$1" 2>/dev/null && kill -n 10 $$ &
		else
			wget $tool_extra_opts --header="Range: bytes=$2-$3" "$url" -O "$1" 2>/dev/null && kill -n 10 $$ &
		fi
	fi
}

trap callback 10

start_time=$(date +%s)
for s in $(seq $total_slice)
do
	begin=$((($s-1)*${size_per_slice}))
	if [ $begin -ne 0 ];then
		begin=$((begin+1))
	fi
	end=$(($s*$size_per_slice))
	if [ $end -gt $size_in_byte ];then
		end=
	fi
	run "temp.$$.$s" $begin $end
done

prev_kb=0
stall_count=0
until [ $is_finished -eq 1 ]
do
	if [ -f "temp.$$.1" ];then
		total_kb=$(BLOCKSIZE=1024 du -k temp.$$.*  2>/dev/null | awk '{t+=$1}END{printf "%d", t}')
		duration=$((`date +%s`-$start_time))
		
		# Calculate percentage (cap at 100%)
		downloaded_bytes=$((total_kb * 1024))
		percentage=$((downloaded_bytes * 100 / size_in_byte))
		[ $percentage -gt 100 ] && percentage=100
		
		# Calculate current speed (instantaneous)
		current_speed=$((total_kb - prev_kb))
		
		# Check if download has stalled
		if [ $current_speed -eq 0 ] && [ $percentage -lt 100 ];then
			stall_count=$((stall_count+1))
			if [ $stall_count -ge $stall_timeout ];then
				echo
				printf "\e[33mDownload stalled, falling back to single-threaded download.\e[0m\n"
				# Clean up partial files
				rm -f temp.$$.*
				fallback_download
			fi
		else
			stall_count=0
		fi
		
		prev_kb=$total_kb
		
		# Calculate average speed
		if [ $duration -gt 0 ];then
			avg_speed=$(($total_kb/$duration))
			printf "\rProgress: %3d%% | Speed: %4d KiB/s | Avg: %4d KiB/s" $percentage $current_speed $avg_speed
		fi
		
		# If we've reached 100% and callback hasn't triggered yet, give it a moment
		# Then break to avoid getting stuck
		if [ $percentage -eq 100 ] && [ $is_finished -eq 0 ];then
			sleep 2
			if [ $is_finished -eq 0 ];then
				# Callback might have missed, trigger concatenation manually
				callback
			fi
		fi
	fi
	sleep 1
done

echo
