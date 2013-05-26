#!/usr/bin/env bash
SEP=$'\1'

die() {
  echo -E "$@" 1>&2
  exit 1
}

nullcheck() {
  [[ -n "$1" ]] || die "Null group name";
}

sanitize() {
  sed -e 's/[^0-9a-zA-Z_]/_/g'
}

splittags() {
  awk -v tag="$1" -f splittags.awk
}

scrape() {
  TZ=UTC0 awk -v g="$1" -v timestamp="${2:-0}" -v sep="$SEP" -f scrape.awk
}

declare -A groupinsane # unsanitized group names
declare -A groupshows # regexes
watch() { # {group name} [regex...]
  nullcheck "$1"
  local gs="$(sanitize<<<"$1")"
  groupinsane[$gs]="$1"
  shift
  while (( "$#" )); do
    groupshows[$gs]+="|($1)"
    shift
  done
}

declare -A grouptimes # last times timestamp
touchgroup() { # {group name} {unix time}
  nullcheck "$1"
  local gs="$(sanitize<<<"$1")"
  grouptimes[$gs]="$2"
}

groupreleases() { # groupname [timestamp]
  nullcheck "$1"
  # TODO: escapeurl $1
  local URL="http://www.nyaa.eu/?page=search&term=%5B$1%5D&page=rss"
  curl -LsS "$URL" > "$1.xml" || die "Failed to retrieve releases for $1"
  tr -d '\r\n'"$SEP" < "$1.xml" | splittags item | scrape "$1" "${2:-}"
}

groupfilter() { # groupname regex [timestamp]
  groupreleases "$1" "${3:-}" | while IFS=$SEP read -r title torrent; do
    grep -P "$2" <<< "$title" 1>/dev/null && echo "$title$SEP$torrent"
  done
}

cleanup() {
  for gs in "${!grouptimes[@]}"; do
    local v="${grouptimes[$gs]}"
    echo "touchgroup $gs $v" >> times.sh
    [ -e "$gs.xml" ] && rm "$gs.xml"
  done
  exit 0
}

# TODO: optionally buffer lists so interrupting and restarting wont give the same output

runall() {
  trap cleanup INT

  local insane regex timestamp now
  for gs in "${!groupshows[@]}"; do
    insane="${groupinsane[$gs]}"
    regex="${groupshows[$gs]:1}"
    timestamp="${grouptimes[$gs]}"
    now="$(date -u '+%s')"
    groupfilter "$insane" "$regex" "$timestamp"
    touchgroup "$gs" "$now"
  done

  cleanup
}
