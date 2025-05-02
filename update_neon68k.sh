#!/bin/bash

ARCHIVE_ID="neon68k"
DEST_DIR="/media/fat"
TMP_DIR="/tmp/neon68k"
LASTRUN_FILE="/media/fat/Scripts/.config/neon68k/lastrun.txt"

mkdir -p "$DEST_DIR"
mkdir -p "$TMP_DIR"
mkdir -p "/media/fat/Scripts/.config/neon68k"

check_for_update() {
        
    current_script="$0"
        
    #upstream_script="https://raw.githubusercontent.com/Neon68K/Automatic-Updater-Script/refs/heads/main/update_neon68k.sh"
    upstream_script="https://uncomentaboveanddeleteme"

    # Retrieve the latest script from upstream 
    curl -kLs $upstream_script -o $TMP_DIR/update_neon68k.sh
    if [[ $? -ne 0 ]]; then
        # Add a dialog informing user auto update failed. 
        return  
                
    else    
        latest_script="$TMP_DIR/update_neon68k.sh"
    fi
        
    # Compare new and old script, if different, replace and rerun.
    if diff "$current_script" "$latest_script" > /dev/null 2>&1; then
      continue
    else    
      chmod +x "$latest_script"
      mv "$latest_script" "$current_script"
      exec "$current_script"
    fi  
}
        
check_for_update 


# Show dialog prompt for full download
dialog --clear --title "Download All Files?" \
--yesno "Do you want to download the full Neon68K set?" 7 50
full_download=$?

# Show dialog prompt for scaler type
dialog --clear --title "Select Scaler Type" \
--menu "Choose your display scaler:" 10 50 2 \
1 "External 4K Upscaler" \
2 "MiSTer Upscaler" 2> "$TMP_DIR/scaler_choice.txt"

scaler_choice=$(cat "$TMP_DIR/scaler_choice.txt" 2>/dev/null)
rm -f "$TMP_DIR/scaler_choice.txt"

# Determine scaler path
if [ "$scaler_choice" == "1" ]; then
    scaler_dir="External 4K Upscaler"
else
    scaler_dir="MiSTer Upscaler"
fi

# Function to URL-encode file paths
url_encode() {
    local str="$1"
    local encoded=""
    local pos c o

    for (( pos=0 ; pos<${#str} ; pos++ )); do
        c=${str:$pos:1}
        case "$c" in
            [a-zA-Z0-9.~_-]) o="$c" ;;
            *) printf -v o '%%%02X' "'$c"
        esac
        encoded+="$o"
    done
    echo "$encoded"
}

# Fetch file list from archive.org
fetch_file_list() {
    echo "Fetching file list..."
    file_list_json=$(wget -qO- "https://archive.org/metadata/$ARCHIVE_ID?output=json")

    if [ -z "$file_list_json" ]; then
        echo "Failed to fetch file list from archive."
        return 1
    fi

    all_files=$(echo "$file_list_json" \
        | grep -o '"name":"[^"]*\.zip"' \
        | sed 's/"name":"\([^"]*\)"/\1/' \
        | sed 's/\\\//\//g')

    if [ -z "$all_files" ]; then
        echo "No zip files found."
        return 1
    fi

    all_files=$(echo "$all_files" | grep "^Neon68K-[^/]*/$scaler_dir/")
    echo "$all_files"
    return 0
}

# Download and extract matching files
sync_files() {
    echo "Starting sync..."
    file_list=$(fetch_file_list) || exit 1

    if [ "$full_download" -ne 0 ]; then
        last_run=$(cat "$LASTRUN_FILE" 2>/dev/null || echo 0)
        echo "Performing incremental sync since: $last_run"
    fi

    while IFS= read -r file; do
        [ -z "$file" ] && continue

        if [ "$full_download" -ne 0 ]; then
            mod_time=$(wget --spider --server-response "https://archive.org/download/$ARCHIVE_ID/$(url_encode "$file")" 2>&1 \
                | grep -i '^ *Last-Modified:' \
                | tail -n1 \
                | sed 's/^.*Last-Modified: //' \
                | xargs -I{} date -d "{}" +%s 2>/dev/null)

            if [[ -n "$mod_time" && "$mod_time" -le "$last_run" ]]; then
                echo "Skipping (not newer): $file"
                continue
            fi
        fi

        echo "Downloading \"$file\"..."
        wget -q --show-progress -O "$TMP_DIR/tmp.zip" "https://archive.org/download/$ARCHIVE_ID/$(url_encode "$file")"

        if [ $? -ne 0 ] || [ ! -f "$TMP_DIR/tmp.zip" ]; then
            echo "Download failed: $file"
            continue
        fi

        unzip -q -o "$TMP_DIR/tmp.zip" -d "$TMP_DIR"

        for dir in "_Computer" "config" "games"; do
            if [ -d "$TMP_DIR/$dir" ]; then
                echo "Copying $dir to $DEST_DIR"
                cp -r "$TMP_DIR/$dir" "$DEST_DIR"
            fi
        done

        rm -f "$TMP_DIR/tmp.zip"
        rm -rf "$TMP_DIR/_Computer" "$TMP_DIR/config" "$TMP_DIR/games"

    done <<< "$file_list"

    echo "Sync complete."
    date +%s > "$LASTRUN_FILE"
}

clear
sync_files
clear
echo "Done."
