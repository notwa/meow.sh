#!/usr/bin/env bash
SEP=$'\1'
curl=(curl -sS -m 32 --connect-timeout 8 --retry 3 --retry-delay 1)

# all timestamps are given in seconds since the epoch
declare -A groupinsane # unsanitized group names
declare -A groupregex
declare -A grouptime # last seen release

die() {
    echo -E "$@" >&2
    exit 1
}

retrieve() {
    ${curl[@]} -d page=search --data-urlencode "term=[$1]" -d page=rss \
      "http://www.nyaa.eu/"
}

nullcheck() { # {group name}
    [[ -n "$1" ]] || die "Null group name";
}

sanitize() {
    sed -e 's/[^0-9a-zA-Z_]/_/g'
}

splittags() { # {tag}
    awk -v tag="$1" -f "$SRCDIR/splittags.awk"
}

scrape() { # {group name} {timestamp}
    TZ=UTC0 awk -v g="$1" -v ts="${2:-0}" -v sep="$SEP" -f "$SRCDIR/scrape.awk"
}

watch() { # {group name} [regex...]
    nullcheck "$1"
    local gs="$(sanitize<<<"$1")" regex=
    groupinsane[$gs]="$1"
    shift
    for regex; do
        groupregex[$gs]+="|($regex)"
    done
}

touchgroup() { # {group name} {timestamp}
    nullcheck "$1"
    local gs="$(sanitize<<<"$1")"
    grouptime[$gs]="$2"
}

groupreleases() { # groupname [timestamp]
    nullcheck "$1"
    retrieve "$1" | tr -d '\r\n'"$SEP" | splittags item | scrape "$1" "${2:-}"
    [ ${PIPESTATUS[0]} = 0 ] || die "Failed to retrieve releases for $1"
}

groupfilter() { # groupname regex [timestamp]
    groupreleases "$1" "${3:-}" | while IFS=$SEP read -r title etc; do
        grep -P "$2" <<< "$title" >/dev/null && echo -E "$title$SEP$etc"
    done
    [ ${PIPESTATUS[0]} = 0 ] || exit 1
}

cleanup() {
    local gs= v=
    for gs in "${!grouptime[@]}"; do
        v="${grouptime[$gs]}"
        echo -E "touchgroup $gs $v" >> times.sh
        [ -e "$gs.xml" ] && rm "$gs.xml"
    done
    exit ${1:-1}
}

rungroup() {
    local insane= regex= timestamp= res= _= recent=
    insane="${groupinsane[$1]}"
    regex="${groupregex[$1]:1}"
    timestamp="${grouptime[$1]}"
    res="$(groupfilter "$insane" "$regex" "$timestamp")"
    [ $? = 0 ] || return $?
    IFS=$SEP read -r _ _ recent <<< "$res"
    [ -n "$recent" ] && {
        grouptime[$1]="$recent"
        echo -E "$res"
    }
    return 0
}

runall() {
    trap cleanup INT
    local ret=0 gs=
    for gs in "${!groupregex[@]}"; do rungroup "$gs" || ret=1; done
    cleanup $ret
}
