#!/bin/bash

# TODO
# * update games when files are missing or the media_path has changed
# * allow filtering of game categories and games

ARCHIVE_ID="neon68k"
NEON68K_VERSION="Neon68K-20250428"

DEST_DIR="/media/fat"
TMP_DIR="/tmp/neon68k"
ARCHIVE_METADATA="${TMP_DIR}/metadata.json"
SCRIPTS_DIR="${DEST_DIR}/Scripts"
CONFIG_DIR="${SCRIPTS_DIR}/.config/neon68k"
LASTRUN_FILE="${CONFIG_DIR}/lastrun.txt"
SCRIPT_INI="${SCRIPTS_DIR}/update_neon68k.ini"

[[ -e "${DEST_DIR}"   ]] || mkdir -p "$DEST_DIR"
[[ -e "${TMP_DIR}"    ]] || mkdir -p "$TMP_DIR"
[[ -e "${CONFIG_DIR}" ]] || mkdir -p "${CONFIG_DIR}"

# Paths to check for games directory
MEDIA_PATHS=(
  '/media/usb0'
  '/media/usb1'
  '/media/usb2'
  '/media/usb3'
  '/media/usb4'
  '/media/usb5'
  '/media/fat/cifs'
  '/media/fat'
)

for media_path in "${MEDIA_PATHS[@]}"; do
  if [ -e "${media_path}/games" ]; then
    GAMES_PATH="${media_path}"
    break
  fi
done

[[ -f "${SCRIPT_INI}" ]] && source "${SCRIPT_INI}"

# Function to get values from an ini file
ini_get() {
  if [ -f ${SCRIPT_INI} ]; then
    grep -E "^${1}=.*$" ${SCRIPT_INI} | cut -d= -f2 ; true
  fi
}

# Function to set values to an ini file
ini_set() {
  ! [ -f ${SCRIPT_INI} ] && touch ${SCRIPT_INI}

  local val
  val="$(ini_get "${1}" "${2}")"

  if [[ -z "${val}" ]]; then
    echo "${1}=${2}" >> ${SCRIPT_INI}
  else
    sed -i -e "s!${1}=.*!${1}=${2}!g" ${SCRIPT_INI}
  fi

  source ${SCRIPT_INI}
}

get_scaler() {
  # The first item in this array is empty. Due to historical reasons the scalers
  # list in the scaler dialog command started at 1 but arrays start at 0

  # The scaler names in this array match up with the directory names in the archive
  local scalers=(
    ""
    "External 4K Upscaler"
    "MiSTer Upscaler"
  )
  echo "${scalers[${1}]}"
}

# Function to URL-encode file paths
url_encode() {
    local str="$1"
    local encoded=""
    local pos c o

    for (( pos=0 ; pos<${#str} ; pos++ )); do
        c=${str:$pos:1}
        case "$c" in
            [a-zA-Z0-9.~_-])
              o="$c" ;;
            *)
              printf -v o '%%%02X' "'$c"
        esac
        encoded+="$o"
    done
    echo "$encoded"
}

# Parse file list from archive.org metadata
parse_file_list() {
    all_files=$(jq -r '.files[].name' < $ARCHIVE_METADATA | grep -E "${NEON68K_VERSION}/${scaler_dir}/.*\.zip$")

    if [ -z "$all_files" ]; then
        echo "No zip files found."
        return 1
    fi

    echo "$all_files"
    return 0
}

# Download and extract matching files
sync_files() {
    echo "Fetching archive metadata..."
    if ! wget -qO${ARCHIVE_METADATA} "https://archive.org/metadata/$ARCHIVE_ID?output=json"
    then
      echo "Failed to download archive metadata, exiting"
      exit 1
    fi

    echo "Starting sync..."
    echo "Fetching file list..."
    file_list=$(parse_file_list) || exit 1

    if [ "$full_download" -eq 0 ]; then
        last_run=$(cat "$LASTRUN_FILE" 2>/dev/null || echo 0)
        echo -n "Performing incremental sync"
    fi

    while IFS= read -r file; do
        [ -z "$file" ] && continue

        if [ "$full_download" -eq 0 ]; then
            mod_time=$(jq --arg file "${file}" -r '.files[] | select(.name==$file) | .mtime' < $ARCHIVE_METADATA)
            if [[ -n "$mod_time" && "$mod_time" -le "$last_run" ]]; then
                echo -n .
                continue
            fi
        fi

        echo Downloading "${file}"...
        if ! wget -q --show-progress -O "$TMP_DIR/tmp.zip" \
              "https://archive.org/download/$ARCHIVE_ID/$(url_encode "$file")"
        then
            echo "Download failed: $file"
            continue
        fi

        for dir in "_Computer" "config"; do
            echo "Copying $dir to $DEST_DIR"
            unzip -q -o "$TMP_DIR/tmp.zip" "${dir}/*" -d "$DEST_DIR"
        done

        echo "Copying games to ${GAMES_PATH}"
        unzip -q -o "$TMP_DIR/tmp.zip" "games/*" -d "${GAMES_PATH}"

        rm -f "$TMP_DIR/tmp.zip"

    done <<< "$file_list"
    echo

    date +%s > "$LASTRUN_FILE"
    rm -f ${ARCHIVE_METADATA}
    echo "Sync complete."
}

choose_scaler() {
  local old_scaler
  old_scaler=$(ini_get scaler)

  # Show dialog prompt for scaler type
  dialog \
    --clear \
    --title "Select Scaler Type" \
    --menu "Choose your display scaler:" 10 50 2 \
      1 "$(get_scaler 1)" \
      2 "$(get_scaler 2)" \
    2> "$TMP_DIR/scaler_choice.txt"

  ini_set scaler "$(cat "$TMP_DIR/scaler_choice.txt" 2>/dev/null)"
  rm -f "$TMP_DIR/scaler_choice.txt"

  clear -x
  echo "$(get_scaler "$(ini_get scaler)") selected"

  if [ "${old_scaler}" != "$(ini_get scaler)" ]; then
    echo "Scaler setting has changed, performing full download..."
    full_download=1
  fi
}

main_dialog() {
  echo "
               _   __                     _____  ____   __ __
              / | / /___   ____   ____   / ___/ ( __ ) / //_/
             /  |/ // _ \ / __ \ / __ \ / __ \ / __  |/ ,<
            / /|  //  __// /_/ // / / // /_/ // /_/ // /| |
           /_/ |_/ \___/ \____//_/ /_/ \____/ \____//_/ |_|

        Neon68K - the easiest X68000 games setup for MiSTer FPGA
"

  if [[ -z "$(ini_get scaler)" ]]; then
    choose_scaler
  fi

  # Determine scaler path
  scaler_dir="$(get_scaler "$(ini_get scaler)")"

  echo "Current settings:
  * Games install path: ${GAMES_PATH}/games
  * Scaler: ${scaler_dir}
"

  if [[ -f ${LASTRUN_FILE} ]]; then
        echo "update_neon68k was last run $(date -d @"$(cat ${LASTRUN_FILE})")"
  fi

  if [ -f ${LASTRUN_FILE} ]; then
    full_download=0
  else
    if dialog \
      --clear \
      --title "update_neon68k First Time Run" \
      --yesno "No last run file was found. Have you already downloaded Neon68K?\nAnswering No will trigger a full download." \
      10 50
    then
      date +%s > "$LASTRUN_FILE"
      full_download=0
    else
      full_download=1
    fi

    clear -x
    sync_files
    exit
  fi

  echo "
  *Press <UP>,    To select scaler option.
  *Press <LEFT>,  To exit.
  *Press <RIGHT>, To force a full download.
  *Press <DOWN>,  To check for updates.

Waiting for 10 seconds then we'll automatically check for updates...
"

  while true; do
    escape_char=$(printf "\u1b")
    read -t 10 -rsn1 mode # get 1 character

    # If it times out we break out and carry on to sync_files
    [[ $? -gt 128 ]] && break

    if [[ $mode == "$escape_char" ]]; then
      read -rsn2 mode     # read 2 more chars
    fi

    case $mode in
      '[A') # Up
          choose_scaler
          break
        ;;
      '[B') # Down
          echo Checking for updates
          break
        ;;
      '[C') # Right
          echo "Running a full download"
          full_download=1
          break
        ;;
      '[D') # Left
        echo Exiting
        exit 0
        ;;
    esac
  done
}

main_dialog
sync_files
