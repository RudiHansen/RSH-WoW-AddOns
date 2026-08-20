#!/usr/bin/env bash

set -euo pipefail

saved_variables_directory="/home/rsh/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft/_retail_/WTF/Account/RUDIHANSEN2/SavedVariables"
script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -d "$saved_variables_directory" ]]; then
    echo "SavedVariables directory not found: $saved_variables_directory" >&2
    exit 1
fi

shopt -s nullglob
data_files=("$saved_variables_directory"/RSH_*.lua "$saved_variables_directory"/RSH_*.lua.bak)

if (( ${#data_files[@]} == 0 )); then
    echo "No RSH_*.lua or RSH_*.lua.bak files found in: $saved_variables_directory" >&2
    exit 1
fi

cp -- "${data_files[@]}" "$script_directory/"

echo "Copied ${#data_files[@]} SavedVariables file(s) to: $script_directory"
echo "Run /reload or log out in World of Warcraft before copying to get the latest data."
