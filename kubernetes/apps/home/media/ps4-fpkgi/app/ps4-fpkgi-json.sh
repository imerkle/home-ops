#!/usr/bin/env bash

# Parameters check
if [ -z "$SERVER_URL" ]; then
    echo "SERVER_URL environment variable must be set"
    exit 1
fi

# Ensure SERVER_URL has a trailing slash (matching reference script behaviour)
[[ "$SERVER_URL" != */ ]] && SERVER_URL="$SERVER_URL/"

INPUT_DIR="/workspace"
JSON_GAMES="GAMES.json"
JSON_UPDATES="UPDATES.json"
JSON_DLC="DLC.json"
cGames=0
cDlc=0
cUpd=0

# PkgTool path
PKG_TOOL="/lib/OpenOrbisSDK/bin/linux/PkgTool.Core"

# Function to update JSON
update_json() {
    local json_file="$1"
    local key="$2"
    local value="$3"

    # Create a new file if it doesn't exist
    if [ ! -f "$json_file" ]; then
        echo '{"DATA": {}}' > "$json_file"
    fi

    # Update the JSON file by adding the new value to the "DATA" block
    jq --arg k "$key" --argjson v "$value" '.DATA += {($k): $v}' "$json_file" > tmp.json && mv tmp.json "$json_file"
}

# Function to check if a PKG is already listed in a JSON
# Matches reference: checks by pkg_name (basename only)
pkg_exists_in_json() {
    local pkg_name="$1"
    local json_file="$2"

    if [ ! -f "$json_file" ]; then
        return 1
    fi

    result=$(grep -Fo "$pkg_name" "$json_file" | wc -l)

    if [ "$result" -gt 0 ]; then
        return 0
    else
        return 1
    fi
}

cleanup_json() {
    local json_file="$1"

    if [ ! -f "$json_file" ] || [ ! -s "$json_file" ]; then
        echo "JSON file $json_file not found or empty. Skipping cleanup."
        return
    fi

    # Read keys (full URLs) from JSON
    original_keys=$(jq -r '.DATA | keys[]' "$json_file")

    kept_keys=""
    deleted_keys=""

    # For every key (full URL), strip SERVER_URL to get relative path, check if file exists
    while IFS= read -r key; do
        # Strip SERVER_URL prefix to get relative path (same as reference)
        # Avoid curly braces to prevent Flux substitution
        full_path=$(echo "$key" | sed "s|^$SERVER_URL||")

        if [ -f "$INPUT_DIR/$full_path" ]; then
            kept_keys+="$key"$'\n'
        else
            echo "Record deleted (not found) in $json_file: $INPUT_DIR/$full_path"
            deleted_keys+="$key"$'\n'
        fi
    done <<< "$(echo "$original_keys")"

    # Removes invalid records from JSON
    jq --argjson kept_keys "$(echo "$kept_keys" | jq -R -s -c 'split("\n") | map(select(length > 0))')" '
        {DATA: ( .DATA | to_entries | map(select(.key as $key | $kept_keys | index($key))) | from_entries )}' \
        "$json_file" > tmp.json && mv tmp.json "$json_file"

    echo "Cleanup completed for $json_file"
}

# cd into INPUT_DIR — all relative paths and find . will work from here
cd "$INPUT_DIR" || exit 1

# Create json files if they dont exist
if [ ! -f "$JSON_GAMES" ]; then
    echo '{"DATA": {}}' > "$JSON_GAMES"
fi
if [ ! -f "$JSON_UPDATES" ]; then
    echo '{"DATA": {}}' > "$JSON_UPDATES"
fi
if [ ! -f "$JSON_DLC" ]; then
    echo '{"DATA": {}}' > "$JSON_DLC"
fi

# Ensure _img directory exists
mkdir -p _img

while read -r pkg; do
    pkg_name=$(basename "$pkg")
    pkg_dir=$(dirname "$pkg")

    # Build relative path including subdir (mirrors reference script logic)
    # INPUT_DIR has no trailing slash; pkg_dir is like ./subdir
    # Strip leading ./ from pkg_dir to get the subdir portion
    pkg_dir_rel=$(echo "$pkg_dir" | sed 's|^\./||')
    if [[ -n "$pkg_dir_rel" && "$pkg_dir_rel" != "." ]]; then
        rel_pkg_path="$pkg_dir_rel/$pkg_name"
    else
        rel_pkg_path="$pkg_name"
    fi

    # Check if pkg is already in jsons — use basename only (matches reference)
    if pkg_exists_in_json "$pkg_name" "$JSON_GAMES" || pkg_exists_in_json "$pkg_name" "$JSON_UPDATES" || pkg_exists_in_json "$pkg_name" "$JSON_DLC"; then
        echo "Skip: $pkg_name already listed in JSONs."
        continue
    fi

    echo "Processing: $rel_pkg_path"

    # Execute command and saves output in tmpfile1
    if ! "$PKG_TOOL" pkg_listentries "$pkg" > ./tmpfile1; then
        echo "ERROR: PkgTool failed for $pkg"
        continue
    fi

    param_sfo_index=$(grep "PARAM_SFO" ./tmpfile1 | awk '{print $4}')

    sfo_file="./tmp_sfo.sfo"
    "$PKG_TOOL" pkg_extractentry "$pkg" "$param_sfo_index" "$sfo_file"

    "$PKG_TOOL" sfo_listentries "$sfo_file" > ./tmpfile

    category=$(grep "^CATEGORY " ./tmpfile | awk -F'=' '{print $2}' | tr -d ' ')
    title_id=$(grep "^TITLE_ID " ./tmpfile | awk -F'=' '{print $2}' | tr -d ' ')
    title=$(grep "^TITLE " ./tmpfile | awk -F'=' '{print $2}' | sed 's/^ *//;s/ *$//')
    version=$(grep "^APP_VER " ./tmpfile | awk -F'=' '{print $2}' | tr -d ' ')
    release_tmp=$(grep "^PUBTOOLINFO " ./tmpfile | grep -o "c_date=[0-9]*" | cut -d'=' -f2)
    release=$(echo "$release_tmp" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\2-\3-\1/')
    size=$(stat -c %s "$pkg")
    content_id=$(grep "^CONTENT_ID " ./tmpfile | awk -F'=' '{print $2}' | tr -d ' ')

    region=$(echo "$content_id" | cut -c1)
    if [[ "$region" == "J" ]]; then
        region="JAP"
    elif [[ "$region" == "E" ]]; then
        region="EUR"
    elif [[ "$region" == "U" ]]; then
        region="USA"
    else
        region="null"
    fi

    # Build URLs — SERVER_URL already has trailing slash
    # Avoid curly braces to prevent Flux substitution
    cover_url="${SERVER_URL}_img/$title_id.png"
    pkg_url="$SERVER_URL$rel_pkg_path"

    coverexists=0
    if [[ -e "./_img/$title_id.png" ]]; then
        coverexists=1
    else
        icon0_index=$(grep 'ICON0_PNG' ./tmpfile1 | awk '{print $4}')
        # If ICON0 is empty, try PIC0
        if [[ -z "$icon0_index" ]]; then
            icon0_index=$(grep 'PIC0_PNG' ./tmpfile1 | awk '{print $4}')
        fi
    fi

    echo "========================="
    echo "DEBUG: category=$category title_id=$title_id pkg_url=$pkg_url"

    # Create json entry for the element
    json_entry=$(jq -n \
        --arg title_id "$title_id" \
        --arg region "$region" \
        --arg name "$title" \
        --arg version "$version" \
        --arg release "$release" \
        --argjson size "$size" \
        --arg cover_url "$cover_url" \
        '{title_id: $title_id, region: $region, name: $name, version: $version, release: $release, size: $size, cover_url: $cover_url}')

    case "$category" in
        "gd")
            echo "CATEGORY: GAME"
            if [[ $coverexists -eq 0 && -n "$icon0_index" ]]; then
                "$PKG_TOOL" pkg_extractentry "$pkg" "$icon0_index" "./_img/$title_id.png"
            fi
            update_json "$JSON_GAMES" "$pkg_url" "$json_entry"
            cGames=$((cGames + 1))
            ;;
        "gp")
            echo "CATEGORY: UPDATE"
            update_json "$JSON_UPDATES" "$pkg_url" "$json_entry"
            cUpd=$((cUpd + 1))
            ;;
        "ac")
            echo "CATEGORY: DLC"
            update_json "$JSON_DLC" "$pkg_url" "$json_entry"
            cDlc=$((cDlc + 1))
            ;;
    esac

    echo "TITLE_ID: $title_id"
    echo "REGION: $region"
    echo "TITLE: $title"
    echo "VERSION: $version"
    echo "RELEASE: $release"
    echo "SIZE: $size"
    echo "PKG_URL: $pkg_url"
    echo "COVER_URL: $cover_url"

    # Remove tmp files
    rm -f "$sfo_file" ./tmpfile ./tmpfile1

done < <(find . -type f -iname "*.pkg")

echo "========================="
echo "PKGs added to jsons:"
echo "  GAMES: $cGames"
echo "  UPDATES: $cUpd"
echo "  DLCs: $cDlc"
echo ""
echo "Cleaning $JSON_GAMES..."
cleanup_json "$JSON_GAMES"
echo "Cleaning $JSON_UPDATES..."
cleanup_json "$JSON_UPDATES"
echo "Cleaning $JSON_DLC..."
cleanup_json "$JSON_DLC"
echo ""
echo "URLs of the JSONs:"
echo "$SERVER_URL$JSON_GAMES"
echo "$SERVER_URL$JSON_UPDATES"
echo "$SERVER_URL$JSON_DLC"
echo ""
echo "Processing completed."
