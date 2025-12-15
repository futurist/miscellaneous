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
# v0.4        add chunk-based downloading with dynamic worker pool and batch concatenation

slices=20
downloader=""
stall_timeout=30  # seconds without progress before fallback to single-threaded
extra_args=""  # additional arguments to pass to curl/wget
chunk_size=$((1024 * 1024))  # default 1MB chunk size
batch_size=16  # concatenate chunks in batches of 16

case $OSTYPE in
    *linux*) slices=$(grep -c processor /proc/cpuinfo) ;;
    *darwin*) slices=$(sysctl hw.ncpu | cut -d' ' -f2) ;;
    *cygwin*) slices=$NUMBER_OF_PROCESSORS ;;
    *) slices=20 ;;
esac

url=
output=

__ScriptVersion="v0.4"

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
    -s|slice      How many worker threads to use, default is $slices
    -c|chunk      Chunk size in bytes (supports K, M suffixes), default is 1M
    -o|output     Specify the output file name, use the guessing file name from url as output file name if not specify this option
    -t|tool       Specify download tool to use (curl or wget), auto-detect if not specified
    -x|extra-args Extra arguments to pass to curl/wget (e.g., '--connect-timeout 10')
                  Note: Arguments are word-split, so quote properly if needed
    
    Environment Variables:
    CURL_OPTS     Extra options to pass to curl (when curl is used)
    WGET_OPTS     Extra options to pass to wget (when wget is used)
    
    Examples:
    ./mcurl.sh -c 2M -s 4 URL
    ./mcurl.sh -x '--connect-timeout 10 --max-time 30' URL
    CURL_OPTS='--connect-timeout 5' ./mcurl.sh URL
    ./mcurl.sh -t wget -x '--timeout=10 --tries=3' URL"

}    # ----------  end of function usage  ----------

#-----------------------------------------------------------------------
#  Handle command line arguments
#-----------------------------------------------------------------------

while getopts ":hvs:o:t:x:c:" opt
do
    case $opt in
	h|help     )  usage; exit 0   ;;
	v|version  )  echo "Multi tasks downloader for curl/wget, version $__ScriptVersion"; exit 0   ;;
	s|slice    )  slices=$OPTARG ;;
	c|chunk    )  
	    # Parse chunk size with K/M suffixes
	    chunk_arg=$OPTARG
	    if [[ $chunk_arg =~ ^([0-9]+)([KMkm])?$ ]];then
	        num=${BASH_REMATCH[1]}
	        suffix=${BASH_REMATCH[2]}
	        case ${suffix^^} in
	            K) chunk_size=$((num * 1024)) ;;
	            M) chunk_size=$((num * 1024 * 1024)) ;;
	            *) chunk_size=$num ;;
	        esac
	    else
	        echo "Invalid chunk size: $chunk_arg"
	        usage; exit 1
	    fi
	    ;;
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
shopt -s nullglob
for temp_file in temp.*.*; do
    if [ -f "$temp_file" ]; then
        # Extract PID from filename (format: temp.PID.slice)
        old_pid=$(echo "$temp_file" | cut -d. -f2)
        # Validate that extracted PID is numeric before checking process
        if [[ "$old_pid" =~ ^[0-9]+$ ]] && ! kill -0 "$old_pid" 2>/dev/null; then
            # Process doesn't exist, safe to clean up
            rm -f "temp.$old_pid."* 2>/dev/null
        fi
    fi
done
shopt -u nullglob

# Clean up our own temp files from any previous failed runs
rm -f "temp.$$."* 2>/dev/null

echo "Download $url to $file_to_save with $slices workers using $downloader."
echo "Chunk size: $((chunk_size / 1024))K, Batch size: $batch_size chunks"
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

# Calculate total chunks needed
total_chunks=$(( (size_in_byte + chunk_size - 1) / chunk_size ))
echo "Total chunks: $total_chunks"

# Initialize work queue and state tracking
next_chunk=0
completed_chunks=0
concatenated_up_to=0  # Track which chunks have been written to main file
is_finished=0

# Lock file for coordinating chunk assignment
chunk_lock="temp.$$.lock"
touch "$chunk_lock"

# Function to get next chunk to download
function get_next_chunk()
{
	# Simple file-based locking
	(
		flock -x 200
		if [ $next_chunk -lt $total_chunks ];then
			chunk=$next_chunk
			next_chunk=$((next_chunk + 1))
			echo $chunk
		else
			echo "-1"
		fi
	) 200>"$chunk_lock"
}

# Function to download a single chunk
function download_chunk()
{
	local chunk_num=$1
	local start_byte=$((chunk_num * chunk_size))
	local end_byte=$((start_byte + chunk_size - 1))
	
	# Last chunk might be smaller
	if [ $end_byte -ge $size_in_byte ];then
		end_byte=$((size_in_byte - 1))
	fi
	
	local temp_file="temp.$$.chunk.$chunk_num"
	
	if [ "$downloader" = "curl" ];then
		curl $tool_extra_opts -r "$start_byte-$end_byte" "$url" -o "$temp_file" 2>/dev/null
	else
		wget $tool_extra_opts --header="Range: bytes=$start_byte-$end_byte" "$url" -O "$temp_file" 2>/dev/null
	fi
	
	return $?
}

# Function to concatenate ready chunks in batches
function concat_ready_chunks()
{
	local batch_start=$concatenated_up_to
	local batch_end=$((batch_start + batch_size - 1))
	[ $batch_end -ge $total_chunks ] && batch_end=$((total_chunks - 1))
	
	# Check if we have a complete batch ready
	local all_ready=1
	for (( i=batch_start; i<=batch_end; i++ )); do
		if [ ! -f "temp.$$.chunk.$i" ];then
			all_ready=0
			break
		fi
	done
	
	# If batch is ready, concatenate it
	if [ $all_ready -eq 1 ];then
		for (( i=batch_start; i<=batch_end; i++ )); do
			cat "temp.$$.chunk.$i" >> "${file_to_save}"
			rm "temp.$$.chunk.$i"
		done
		concatenated_up_to=$((batch_end + 1))
		return 0
	fi
	return 1
}

# Worker function
function worker()
{
	while true; do
		chunk=$(get_next_chunk)
		if [ "$chunk" = "-1" ];then
			break
		fi
		
		download_chunk $chunk
		
		# Mark chunk as completed
		(
			flock -x 200
			completed_chunks=$((completed_chunks + 1))
			
			# Try to concatenate ready chunks without blocking
			concat_ready_chunks
			
		) 200>"$chunk_lock"
	done
}

# Start worker processes
start_time=$(date +%s)
for (( i=0; i<slices; i++ )); do
	worker &
done

# Monitor progress
prev_kb=0
stall_count=0
while [ $concatenated_up_to -lt $total_chunks ] || [ $(jobs -r | wc -l) -gt 0 ]; do
	# Get current progress
	total_kb=$(BLOCKSIZE=1024 du -k temp.$$.chunk.* 2>/dev/null | awk '{t+=$1}END{printf "%d", t}')
	# Add already concatenated data
	if [ -f "${file_to_save}" ];then
		concatenated_kb=$(BLOCKSIZE=1024 du -k "${file_to_save}" 2>/dev/null | awk '{print $1}')
		total_kb=$((total_kb + concatenated_kb))
	fi
	
	duration=$((`date +%s`-$start_time))
	
	# Calculate percentage
	downloaded_bytes=$((total_kb * 1024))
	percentage=$((downloaded_bytes * 100 / size_in_byte))
	[ $percentage -gt 100 ] && percentage=100
	
	# Calculate current speed
	current_speed=$((total_kb - prev_kb))
	
	# Check if download has stalled
	if [ $current_speed -eq 0 ] && [ $percentage -lt 100 ];then
		stall_count=$((stall_count+1))
		if [ $stall_count -ge $stall_timeout ];then
			echo
			printf "\e[33mDownload stalled, falling back to single-threaded download.\e[0m\n"
			# Kill all workers
			jobs -p | xargs -r kill 2>/dev/null
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
		printf "\rProgress: %3d%% | Speed: %4d KiB/s | Avg: %4d KiB/s | Chunks: %d/%d" \
			$percentage $current_speed $avg_speed $concatenated_up_to $total_chunks
	fi
	
	# Try to concatenate more chunks
	(
		flock -x 200
		concat_ready_chunks
	) 200>"$chunk_lock"
	
	sleep 1
done

# Wait for all workers to finish
wait

# Concatenate any remaining chunks
while [ $concatenated_up_to -lt $total_chunks ]; do
	if [ -f "temp.$$.chunk.$concatenated_up_to" ];then
		cat "temp.$$.chunk.$concatenated_up_to" >> "${file_to_save}"
		rm "temp.$$.chunk.$concatenated_up_to"
		concatenated_up_to=$((concatenated_up_to + 1))
	else
		# Missing chunk, something went wrong
		echo
		printf "\e[31mError: Missing chunk $concatenated_up_to\e[0m\n"
		exit 1
	fi
done

# Cleanup
rm -f "$chunk_lock"
rm -f temp.$$.*

echo
