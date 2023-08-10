#!/bin/bash

# Enable the nullglob option to handle unmatched wildcards
shopt -s nullglob

# Source directory where Transmission downloads files
source_dir="/var/lib/transmission-daemon/downloads"

# Nextcloud
nextcloud_user="www-data"
nextcloud_group="www-data"
nextcloud_occ_path="/var/www/nextcloud/occ"
nextcloud_data_dir="/mnt/hdd1/nextcloud/data"
nextcloud_destination_dir="/bob/files/Downloads/torrent"
destination_dir="$nextcloud_data_dir/$nextcloud_destination_dir"
destination_dir_owner="$nextcloud_user:$nextcloud_group"

# Replace these values with your actual Transmission settings
TRANSMISSION_URL="http://localhost:9091/transmission/rpc"
TRANSMISSION_USER=""
TRANSMISSION_PASSWORD=""

# upload ratio threshold
upload_ratio_threshold=0

# Calculate half of the upload_ratio_threshold
half_upload_ratio_threshold=$(awk "BEGIN {print $upload_ratio_threshold / 2}")
half_upload_ratio_threshold=$(echo "$half_upload_ratio_threshold" | tr , .)

# Initialize an array to store files for which upload_ratio > 0
files_and_ratios=()

# Set a flag variable to control loop continuation
continue_loop=true

# Function to handle Ctrl+C and user input
function handle_exit() {
    echo "Exiting..."
    continue_loop=false
}

# Trap Ctrl+C and call the handler function
trap handle_exit SIGINT

# Function to fetch the session ID
get_session_id() {
    session_id_response=$(curl -sD - -u "$TRANSMISSION_USER:$TRANSMISSION_PASSWORD" "$TRANSMISSION_URL")
    session_id=$(echo "$session_id_response" | grep -i 'X-Transmission-Session-Id:' | awk '{print $2}' | tr -d '\r' | head -n 1)
    echo "$session_id"
}

# List to store moved torrents
moved_torrents=()

# Make the API request to get the torrent's information
session_id=$(get_session_id)
torrent_info=$(curl -s -u "$TRANSMISSION_USER:$TRANSMISSION_PASSWORD" \
    -H "X-Transmission-Session-Id: $session_id" \
    -d '{"method":"torrent-get","arguments":{"fields":["name","hashString","uploadRatio","status"]}}' \
    "$TRANSMISSION_URL")

# Check if the API requests are successful
if [ -z "$torrent_info" ]; then
    echo "Error: Unable to retrieve torrent information."
    exit 1
fi

# Loop through the files in the source directory
for file in "$source_dir"/*; do

    # Check the flag variable
    if [ "$continue_loop" = false ]; then
        echo "Exiting loop."
        break  # Break out of the loop
    fi

    # Check if the current item is a directory
    if [[ -d "$file" ]]; then
        # Check if any file within the directory ends with ".part"
        incomplete_files=("$file"/*.part)
        if (( ${#incomplete_files[@]} )); then
            echo "Skipping incomplete folder: $file"
            echo "=========================================="
            continue
        fi
    else
        # Check if the file name ends with ".part"
        if [[ $file == *.part ]]; then
            echo "Skipping incomplete file: $file"
            echo "=========================================="
            continue
        fi
    fi

    # Check if the "torrents" array is not empty
    if [ "$(echo "$torrent_info" | jq -e '.arguments.torrents')" != "null" ]; then
        # Get the torrent name from the file name
        torrent_name=$(basename "$file")

        # Extract the torrent hash
        torrent_hash=$(echo "$torrent_info" | jq -r ".arguments.torrents[] | select(.name == \"$torrent_name\").hashString")

        # Extract the upload ratio for the torrent
        upload_ratio=$(echo "$torrent_info" | jq -r ".arguments.torrents[] | select(.hashString == \"$torrent_hash\").uploadRatio")

        # Extract the status for the torrent
        torrent_status=$(echo "$torrent_info" | jq -r ".arguments.torrents[] | select(.hashString == \"$torrent_hash\").status")

        # Check if the torrent_hash is retrieved
        if [ -z "$torrent_hash" ]; then
            echo "Error: Unable to retrieve torrent hash for $torrent_name."
            continue
        fi

        # Check if the upload ratio is above half of upload_ratio_threshold
        if (( $(awk 'BEGIN {print ("'"$upload_ratio"'" > "'"$half_upload_ratio_threshold"'")}') )); then
            files_and_ratios+=("$torrent_name: $upload_ratio / $upload_ratio_threshold")
        fi

        # Check if the torrent is seeding and upload ratio is above the threshold
        if [ "$torrent_status" -eq 6 ] && awk -v ratio="$upload_ratio" -v threshold="$upload_ratio_threshold" 'BEGIN { exit !(ratio >= threshold) }'; then
            # Move the file or folder to the destination directory
            if [ -f "$file" ]; then
                echo "Moving file: $file"
                if sudo mv -f "$file" "$destination_dir/"; then
                    echo "Move successful."
                    # Change ownership to www-data:www-data
                    if sudo chown "$destination_dir_owner" "$destination_dir/$(basename "$file")"; then
                        echo "Ownership change successful."
                    else
                        echo "Error changing ownership."
                        continue
                    fi
                else
                    echo "Error moving file."
                    continue
                fi
            elif [ -d "$file" ]; then
                echo "Moving folder: $file"
                folder_name=$(basename "$file")

                # Check if destination directory is not empty
                if [ -d "$destination_dir/$folder_name" ] && [ -n "$(ls -A "$destination_dir/$folder_name")" ]; then
                    echo "Removing contents of destination directory: $destination_dir/$folder_name"
                    sudo rm -r "$destination_dir/$folder_name/"*  # Remove contents of the destination directory
                fi

                if sudo mv -f "$file" "$destination_dir/"; then
                    echo "Move successful."
                    # Change ownership of the moved folder
                    if sudo chown -R "$destination_dir_owner" "$destination_dir/$folder_name"; then
                        echo "Ownership change successful."
                    else
                        echo "Error changing ownership."
                        continue
                    fi
                else
                    echo "Error moving folder."
                    continue
                fi
            fi

            # Stop the torrent using its hash and suppress output
            curl -u "$TRANSMISSION_USER:$TRANSMISSION_PASSWORD" -H "X-Transmission-Session-Id: $session_id" \
                -X POST -d "{\"method\":\"torrent-stop\",\"arguments\":{\"ids\":[\"$torrent_hash\"]}}" \
                "$TRANSMISSION_URL" >/dev/null 2>&1

            # Remove the torrent and its data using its hash and suppress output
            curl -u "$TRANSMISSION_USER:$TRANSMISSION_PASSWORD" -H "X-Transmission-Session-Id: $session_id" \
                -X POST -d "{\"method\":\"torrent-remove\",\"arguments\":{\"ids\":[\"$torrent_hash\"],\"delete-local-data\":true}}" \
                "$TRANSMISSION_URL" >/dev/null 2>&1

            echo "=========================================="
            # Add the moved torrent name to the list
            moved_torrents+=("$torrent_name")
        fi
    fi

    # Check for user input without waiting
    read -t 0.1 -n 1 user_input
    if [[ "$user_input" == [Qq] ]]; then
        echo "Exiting loop."
        break  # Break out of the loop
    fi

done

# Print files and their upload ratios that are ready for move
if [ ${#files_and_ratios[@]} -gt 0 ]; then
    echo "Files almost ready for move (Name: Upload Ratio > $half_upload_ratio_threshold):"
    for item in "${files_and_ratios[@]}"; do
        echo "$item"
    done
else
    echo "No files ready for move."
fi

# Print summary of moved torrents
if [ ${#moved_torrents[@]} -gt 0 ]; then
    echo "Torrents moved:"
    for torrent in "${moved_torrents[@]}"; do
        echo "- $torrent"
    done
    sudo chown -R "$destination_dir_owner" "$destination_dir" # for sure
    sudo -u $nextcloud_user php $nextcloud_occ_path files:scan --path="$nextcloud_destination_dir"
else
    echo "No torrents moved."
fi