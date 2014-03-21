#!/usr/bin/env bash
SEP=$'\t'
curl=(curl -sS -m 32 --connect-timeout 8 --retry 3 --retry-delay 1)

URL_SEARCH='http://www.nyaa.se/'
URL_DOWNLOAD='http://www.nyaa.se/?page=download&tid='

# all timestamps are given in seconds since the epoch
declare -A searchquery
declare -A searchregex

die() {
    echo -E "$@" >&2
    exit 1
}

retrieve() {
    ${curl[@]} -G --data-urlencode "term=[$1]" -d page=rss "$URL_SEARCH"
}

nullcheck() { # {query}
    [[ -n "$1" ]] || die "Null search query";
}

sanitize() {
    sed -e 's/[^0-9a-zA-Z_]/_/g'
}

splittags() { # {tag}
    awk -v tag="$1" -f "$SRCDIR/splittags.awk"
}

scrape() {
    TZ=UTC0 awk -v sep="$SEP" -f "$SRCDIR/scrape.awk"
}

watch() { # {search query} [regex...]
    nullcheck "$1"
    local gs="$(sanitize<<<"$1")" regex=
    searchquery[$gs]="$1"
    shift
    for regex; do
        searchregex[$gs]+="|($regex)"
    done
}

search() {
    nullcheck "$1"
    retrieve "$1" | tr -d '\r\n'"$SEP" | splittags item | scrape
    [ ${PIPESTATUS[0]} = 0 ] || die "Failed to search for $1"
}

searchfilter() { # database regex [timestamp]
    while read -r; do
        IFS=$SEP read -r time tid title <<< "$REPLY"
        [ "$time" -gt "${3:-0}" ] \
        && grep -qP "$2" <<< "$title" \
        && echo -E "$REPLY"
    done < "$1"
}

runfilter() { # {action} [database]
    declare -A already
    local action="${1:-echo}"
    local mark="$action.txt"
    local db="${2:-db.txt}"
    local ret=0

    touch "$mark"
    while IFS=$SEP read -r tid time; do
        already["$tid"]="$time"
    done < "$mark"

    now="$(date +%s)"
    while IFS=$SEP read -r time tid title; do
        [ -n "${already[$tid]}" ] || {
            $action $time $tid "$title" && already[$tid]="$now"
        } || {
            echo "[meow.sh] failed to run $action" >&2
            echo "[meow.sh] torrent title: $title" >&2
            echo "[meow.sh] torrent id: $tid" >&2
            ret=1
            break
        }
    done < <(for regex in "${searchregex[@]}"; do
        searchfilter "$db" "${regex:1}"
    done)

    rm "$mark"
    for tid in "${!already[@]}"; do
        echo "$tid$SEP${already[$tid]}" >> "$mark"
    done

    return "$ret"
}

runsearch() { # [database]
    local db="${1:-db.txt}"
    local tmp=`mktemp`
    touch "$db"
    for q in "${!searchquery[@]}"; do
        search "${searchquery[$q]}" \
        | while IFS=$SEP read -r title torrent time; do
            local tid="${torrent##*=}"
            echo -E "$time$SEP$tid$SEP$title"
        done
    done | sort -n -- "$db" - | uniq > $tmp
    # TODO: don't accidentally overwrite $db with something blank/incomplete
    #       maybe check if filesize has decreased and die if so
    mv $tmp "$db"
}
