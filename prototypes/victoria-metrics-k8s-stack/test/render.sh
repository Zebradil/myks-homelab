#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash prometheus-alertmanager bat

set -euo pipefail

function printColoredTestHeader() {
  local text="$1"
  local colorCode="\033[1;34m" # Bold Blue
  local resetCode="\033[0m"
  echo -e "${colorCode}===== ${text} =====${resetCode}"
}

function printTestDelimiter() {
  local colorCode="\033[1;34m" # Bold Blue
  local resetCode="\033[0m"
  echo -e "${colorCode}=========================${resetCode}"
}

for dataFile in ./data/*.json; do
  printColoredTestHeader "Rendering alert from $dataFile"
  amtool template render \
    --template.glob=../lib/tg.gotmpl \
    --template.text='{{ template "telegram.message" . }}' \
    --template.data="$dataFile" \
    | bat --language=html --style=plain
  echo
  printTestDelimiter
  echo
done
