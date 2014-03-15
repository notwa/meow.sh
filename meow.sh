#!/usr/bin/env bash
SEP=$'\t'
curl=(curl -sS -m 32 --connect-timeout 8 --retry 3 --retry-delay 1)

# all timestamps are given in seconds since the epoch
declare -A searchquery
declare -A searchregex
declare -A searchtime # last seen release

die() {
    echo -E "$@" >&2
    exit 1
}

retrieve() {
    ${curl[@]} -G --data-urlencode "term=[$1]" -d page=rss \
      "http://www.nyaa.se/"
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

touchquery() { # {search query} {timestamp}
    nullcheck "$1"
    local gs="$(sanitize<<<"$1")"
    searchtime[$gs]="$2"
}

search() {
    nullcheck "$1"
    retrieve "$1" | tr -d '\r\n'"$SEP" | splittags item | scrape
    [ ${PIPESTATUS[0]} = 0 ] || die "Failed to search for $1"
}

searchfilter() { # key regex [timestamp]
    while IFS=$SEP read -r title etc; do
        grep -P "$2" <<< "$title" >/dev/null && echo -E "$title$SEP$etc"
    done < db.txt
    [ ${PIPESTATUS[0]} = 0 ] || exit 1
}

cleanup() {
    local gs= v=
    for gs in "${!searchtime[@]}"; do
        v="${searchtime[$gs]}"
        echo -E "touchquery $gs $v" >> times.sh
        [ -e "$gs.xml" ] && rm "$gs.xml"
    done
    exit ${1:-1}
}

runfilter() {
    local query= regex= timestamp= res= _= recent=
    query="${searchquery[$1]}"
    regex="${searchregex[$1]:1}" # exclude first | character
    timestamp="${searchtime[$1]}"
    res="$(searchfilter "$query" "$regex" "$timestamp")"
    [ $? = 0 ] || return $?
    IFS=$SEP read -r _ _ recent <<< "$res"
    [ -n "$recent" ] && {
        searchtime[$1]="$recent"
        echo -E "$res"
    }
    return 0
}

runsearch() { # [database]
    local db="${1:-db.txt}"
    local tmp=`mktemp`
    touch "$db"
    for q in "${!searchquery[@]}"; do
        search "${searchquery[$q]}" \
        | while IFS=$SEP read -r title torrent time; do
            echo -E "$time$SEP$q$SEP$title$SEP$torrent"
        done
    done | sort -n -- "$db" - | uniq > $tmp
    # TODO: don't accidentally overwrite $db with something blank/incomplete
    #       maybe check if filesize has decreased and die if so
    mv $tmp "$db"
}

runall() {
    trap cleanup INT
    local ret=0 gs=
    for gs in "${!searchregex[@]}"; do runfilter "$gs" || ret=1; done
    cleanup $ret
}
