#!/usr/bin/env bash
set -e
shopt -s extglob
## refresh from corpsusops.bootstrap/hacking/shell_glue (copy paste until last function)
readlinkf() {
    if ( uname | egrep -iq "darwin|bsd" );then
        if ( which greadlink 2>&1 >/dev/null );then
            greadlink -f "$@"
        elif ( which perl 2>&1 >/dev/null );then
            perl -MCwd -le 'print Cwd::abs_path shift' "$@"
        elif ( which python 2>&1 >/dev/null );then
            python -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$@"
        fi
    else
        readlink -f "$@"
    fi
}
# colors
RED="\\e[0;31m"
CYAN="\\e[0;36m"
YELLOW="\\e[0;33m"
NORMAL="\\e[0;0m"
NO_COLOR=${NO_COLORS-${NO_COLORS-${NOCOLOR-${NOCOLORS-}}}}
LOGGER_NAME=${LOGGER_NAME:-corpusops_build}
ERROR_MSG="There were errors"
uniquify_string() {
    local pattern=$1
    shift
    echo "$@" \
        | sed -e "s/${pattern}/\n/g" \
        | awk '!seen[$0]++' \
        | tr "\n" "${pattern}" \
        | sed -e "s/^${pattern}\|${pattern}$//g"
}
do_trap_() { rc=$?;func=$1;sig=$2;${func};if [ "x${sig}" != "xEXIT" ];then kill -${sig} $$;fi;exit $rc; }
do_trap() { rc=${?};func=${1};shift;sigs=${@};for sig in ${sigs};do trap "do_trap_ ${func} ${sig}" "${sig}";done; }
is_ci() { return $( set +e;( [ "x${TRAVIS-}" != "x" ] || [ "x${GITLAB_CI}" != "x" ] );echo $?; ); }
log_() {
    reset_colors;msg_color=${2:-${YELLOW}};
    logger_color=${1:-${RED}};
    logger_slug="${logger_color}[${LOGGER_NAME}]${NORMAL} ";
    shift;shift;
    if [ "x${NO_LOGGER_SLUG}" != "x" ];then logger_slug="";fi
    printf "${logger_slug}${msg_color}$(echo "${@}")${NORMAL}\n" >&2;
    printf "" >&2;  # flush
}
reset_colors() { if [ "x${NO_COLOR}" != "x" ];then BLUE="";YELLOW="";RED="";CYAN="";fi; }
log() { log_ "${RED}" "${CYAN}" "${@}"; }
get_chrono() { date "+%F_%H-%M-%S"; }
cronolog() { log_ "${RED}" "${CYAN}" "($(get_chrono)) ${@}"; }
debug() { if [ "x${DEBUG-}" != "x" ];then log_ "${YELLOW}" "${YELLOW}" "${@}"; fi; }
warn() { log_ "${RED}" "${CYAN}" "${YELLOW}[WARN] ${@}${NORMAL}"; }
bs_log(){ log_ "${RED}" "${YELLOW}" "${@}"; }
bs_yellow_log(){ log_ "${YELLOW}" "${YELLOW}" "${@}"; }
may_die() {
    reset_colors
    thetest=${1:-1}
    rc=${2:-1}
    shift
    shift
    if [ "x${thetest}" != "x0" ]; then
        if [ "x${NO_HEADER-}" = "x" ]; then
            NO_LOGGER_SLUG=y log_ "" "${CYAN}" "Problem detected:"
        fi
        NO_LOGGER_SLUG=y log_ "${RED}" "${RED}" "$@"
        exit $rc
    fi
}
die() { may_die 1 1 "${@}"; }
die_in_error_() {
    ret=${1}; shift; msg="${@:-"$ERROR_MSG"}";may_die "${ret}" "${ret}" "${msg}";
}
die_in_error() { die_in_error_ "${?}" "${@}"; }
die_() { NO_HEADER=y die_in_error_ $@; }
sdie() { NO_HEADER=y die $@; }
parse_cli() { parse_cli_common "${@}"; }
parse_cli_common() {
    USAGE=
    for i in ${@-};do
        case ${i} in
            --no-color|--no-colors|--nocolor|--no-colors)
                NO_COLOR=1;;
            -h|--help)
                USAGE=1;;
            *) :;;
        esac
    done
    reset_colors
    if [ "x${USAGE}" != "x" ]; then
        usage
    fi
}
has_command() {
    ret=1
    if which which >/dev/null 2>/dev/null;then
      if which "${@}" >/dev/null 2>/dev/null;then
        ret=0
      fi
    else
      if command -v "${@}" >/dev/null 2>/dev/null;then
        ret=0
      else
        if hash -r "${@}" >/dev/null 2>/dev/null;then
            ret=0
        fi
      fi
    fi
    return ${ret}
}
pipe_return() {
    local filter=$1;shift;local command=$@;
    (((($command; echo $? >&3) | $filter >&4) 3>&1) | (read xs; exit $xs)) 4>&1;
}
output_in_error() { ( do_trap output_in_error_post EXIT TERM QUIT INT;\
                      output_in_error_ "${@}" ; ); }
output_in_error_() {
    if [ "x${OUTPUT_IN_ERROR_DEBUG-}" != "x" ];then set -x;fi
    if ( is_ci );then
        DEFAULT_CI_BUILD=y
    fi
    CI_BUILD="${CI_BUILD-${DEFAULT_CI_BUILD-}}"
    if [ "x$CI_BUILD" != "x" ];then
        DEFAULT_NO_OUTPUT=y
        DEFAULT_DO_OUTPUT_TIMER=y
    fi
    VERBOSE="${VERBOSE-}"
    TIMER_FREQUENCE="${TIMER_FREQUENCE:-120}"
    NO_OUTPUT="${NO_OUTPUT-${DEFAULT_NO_OUTPUT-1}}"
    DO_OUTPUT_TIMER="${DO_OUTPUT_TIMER-$DEFAULT_DO_OUTPUT_TIMER}"
    LOG=${LOG-}
    if [ "x$NO_OUTPUT" != "x" ];then
        if [  "x${LOG}" = "x" ];then
            LOG=$(mktemp)
            DEFAULT_CLEANUP_LOG=y
        else
            DEFAULT_CLEANUP_LOG=
        fi
    else
        DEFAULT_CLEANUP_LOG=
    fi
    CLEANUP_LOG=${CLEANUP_LOG:-${DEFAULT_CLEANUP_LOG}}
    if [ "x$VERBOSE" != "x" ];then
        log "Running$([ "x$LOG" != "x" ] && echo "($LOG)"; ): $@";
    fi
    TMPTIMER=
    if [ "x${DO_OUTPUT_TIMER}" != "x" ]; then
        TMPTIMER=$(mktemp)
        ( i=0;\
          while test -f $TMPTIMER;do\
           i=$((++i));\
           if [ `expr $i % $TIMER_FREQUENCE` -eq 0 ];then \
               log "BuildInProgress$( if [ "x$LOG" != "x" ];then echo "($LOG)";fi ): ${@}";\
             i=0;\
           fi;\
           sleep 1;\
          done;\
          if [ "x$VERBOSE" != "x" ];then log "done: ${@}";fi; ) &
    fi
    # unset NO_OUTPUT= LOG= to prevent output_in_error children to be silent
    # at first
    reset_env="NO_OUTPUT LOG"
    if [ "x$NO_OUTPUT" != "x" ];then
        ( unset $reset_env;"${@}" ) >>"$LOG" 2>&1;ret=$?
    else
        if [ "x$LOG" != "x" ] && has_command tee;then
            ( unset $reset_env; pipe_return "tee -a $tlog" "${@}"; )
            ret=$?
        else
            ( unset $reset_env; "${@}"; )
            ret=$?
        fi
    fi
    if [ -e "$TMPTIMER" ]; then rm -f "${TMPTIMER}";fi
    if [ "x${OUTPUT_IN_ERROR_NO_WAIT-}" = "x" ];then wait;fi
    if [ -e "$LOG" ] &&  [ "x${ret}" != "x0" ] && [ "x$NO_OUTPUT" != "x" ];then
        cat "$LOG" >&2
    fi
    if [ "x${OUTPUT_IN_ERROR_DEBUG-}" != "x" ];then set +x;fi
    return ${ret}
}
output_in_error_post() {
    if [ -e "$TMPTIMER" ]; then rm -f "${TMPTIMER}";fi
    if [ -e "$LOG" ] && [ "x$CLEANUP_LOG" != "x" ];then rm -f "$LOG";fi
}
test_silent_log() { ( [ "x${NO_SILENT-}" = "x" ] && ( [ "x${SILENT_LOG-}" != "x" ] || [ x"${SILENT_DEBUG}" != "x" ] ) ); }
test_silent() { ( [ "x${NO_SILENT-}" = "x" ] && ( [ "x${SILENT-}" != "x" ] || test_silent_log ) ); }
silent_run_() {
    (LOG=${SILENT_LOG:-${LOG}};
     NO_OUTPUT=${NO_OUTPUT-};\
     if test_silent;then NO_OUTPUT=y;fi;output_in_error "$@";)
}
silent_run() { ( silent_run_ "${@}" ; ); }
run_silent() {
    (
    DEFAULT_RUN_SILENT=1;
    if [ "x${NO_SILENT-}" != "x" ];then DEFAULT_RUN_SILENT=;fi;
    SILENT=${SILENT-DEFAULT_RUN_SILENT} silent_run "${@}";
    )
}
vvv() { debug "${@}";silent_run "${@}"; }
vv() { log "${@}";silent_run "${@}"; }
silent_vv() { SILENT=${SILENT-1} vv "${@}"; }
quiet_vv() { if [ "x${QUIET-}" = "x" ];then log "${@}";fi;run_silent "${@}";}
## end from glue
LOGGER_NAME="dockerimages-builder"
rc=0
THISSCRIPT=$0
W="$(dirname $(readlinkf $THISSCRIPT))"
cd "$W"
if [[ -n $SDEBUG ]];then set -x;fi
DEFAULT_REGISTRY=${DEFAULT_REGISTRY:-registry.hub.docker.com}
DOCKER_REPO=${DOCKER_REPO:-corpusops}
TOPDIR=$(pwd)
SDEBUG=${SDEBUG-}
DEBUG=${DEBUG-}
DRYRUN=${DRYRUN-}
NOREFRESH=${NOREFRESH-}
NBPARALLEL=${NBPARALLEL-4}
SKIP_MINOR="((node|ruby|php|golang|python|mysql|postgres|solr|elasticsearch|mongo|ruby):.*([0-9]\.?){3})"
SKIP_PRE="((node|traefik|ruby|postgres|solr|elasticsearch|mongo|php|golang):.*(alpha|beta|rc))"
SKIP_OS="(((suse|centos|fedora|redhat|alpine|debian|ubuntu):.*[0-9]{8}.*)"
SKIP_OS="$SKIP_OS|(debian:(6.*|stretch))"
SKIP_OS="$SKIP_OS|(ubuntu:(14.10|12|10|11|13|15))"
SKIP_OS="$SKIP_OS|(lucid|maverick|natty|precise|quantal|raring|saucy)"
SKIP_OS="$SKIP_OS|(centos:5)"
SKIP_OS="$SKIP_OS|(fedora.*modular)"
SKIP_OS="$SKIP_OS|(traefik:(rc.*|(v?([0-9]\.)*[0-9]$)|((latest|maroilles)$)))"
SKIP_OS="$SKIP_OS)"
SKIP_PHP="(php:(.*(RC|-rc-).*))"
SKIP_WINDOWS="(.*(nanoserver|windows))"
SKIPPED_TAGS="($SKIP_MINOR|$SKIP_PRE|$SKIP_OS|$SKIP_PHP|$SKIP_WINDOWS|-?on.?build|-old)"
CURRENT_TS=$(date +%s)
default_images="
library/alpine
library/centos
library/debian
library/fedora
library/golang
library/mysql
library/nginx
library/node
library/php
library/postgres
library/python
library/traefik
library/ruby
library/ubuntu
library/opensuse
library/solr
library/mongo
library/elasticsearch
makinacorpus/pgrouting
mdillon/postgis
"
declare -A registry_tokens
declare -A registry_services

is_on_build() { echo "$@" | egrep -iq "on.*build"; }
slashcount() { local _slashcount="$(echo "${@}"|sed -e 's![^/]!!g')";echo ${#_slashcount}; }

## registry code badly inspired from:
## https://hackernoon.com/inspecting-docker-images-without-pulling-them-4de53d34a604
DEFAULT_REGISTRY=${DEFAULT_REGISTRY:-registry.hub.docker.com}
get_registry() {
    local image=$@
    local registry=${2:-$DEFAULT_REGISTRY}
    local slashcount="$(echo ${image}|sed -e 's![^/]!!g')"
    local nbslash=$(slashcount $image)
    if ( echo "$image" |grep -iq gitlab.com );then
        registry=registry.gitlab.com
    elif [ $nbslash -gt 1 ];then
        registry=$(echo $image|sed -e "s/\/.*//g")
    else
        registry="${registry}"
    fi
    if ( echo $registry | grep -vq -- "://" );then
        registry="${REGISTRY_SCHEME:-https://}${registry}"
    fi
    echo "$registry"
}

setup_token() {
    local registry=${1:-$(get_registry default)}
    if [[ -n "$1" ]];then shift;fi
    local oargs=${@}
    local args=$oargs
    local tkey=${registry}${oargs}
    registry_token=${registry_tokens[$tkey]}
    registry_service=${registry_services[$tkey]}
    if [[ -z "$registry_token" ]];then
        local authinfos=$(curl -vvv $registry/v2/ 2>&1|grep -i Www-Authenticate:)
        if ! ( echo  $authinfos | egrep -iq "Www-Authenticate:.*realm.*service" );then
            return 1
        fi
        # Www-Authenticate: Bearer realm="https://...",service="registry..."
        local authendpoint=$(echo "$authinfos"|sed -e 's!.*realm="\([^"]\+\)".*!\1!g')
        registry_service=$(echo "$authinfos"|sed -e 's!.*service="\([^"]\+\)".*!\1!g')
        if [[ -n $args ]];then args="$args&";fi
        args="${args}service=$registry_service"
        registry_token=$(curl --silent "$authendpoint?$args" | jq -r '.token')
    fi
    if [[ -n $registry_token ]];then
        registry_tokens[$tkey]="$registry_token"
        registry_services[$tkey]="$registry_service"
    fi
}

get_image_scope() {
    echo "scope=repository:$1:pull"
}

get_image_tag() {
    local image="$1"
    if ( echo $image | egrep -q ":[^/]+$" );then
        image=$( echo $image | sed -e 's!\(.*\):[^/]\+$!\1!' )
    fi
    echo $image
}

get_image_version() {
    local image="$1"
    if ( echo $image | egrep -q ":[^/]+$" )
        then local tag=${1//*:/}
        else local tag=latest
    fi
    echo $tag
}

## Retrieve the digest, now specifying in the header
## that we have a token (so we can pe...
get_digest() {
    local fimage="$1"
    local image="$(get_image_tag $1)"
    local tag="$(get_image_version $1)"
    local registry="$(get_registry $1)"
    local scope="$(get_image_scope $image $registry)"
    setup_token $registry $scope
    curl \
        --silent \
        --header "Accept: application/vnd.docker.distribution.manifest.v2+json" \
        --header "Authorization: Bearer $registry_token" \
        "$registry/v2/$image/manifests/$tag" \
        | jq -r '.config.digest'
}

get_image_configuration() {
    local fimage="$1"
    local image="$(get_image_tag $1)"
    local tag="$(get_image_version $1)"
    local registry="$(get_registry $1)"
    local scope="$(get_image_scope $image $registry)"
    setup_token $registry $scope
    local digest=$(get_digest $fimage)
    set -x
    echo $digest
    curl -vvv\
        --silent \
        --location \
        --header "Authorization: Bearer $registry_token" \
        "$registry/v2/$image/blobs/$digest" \
        | jq -r '.'
}

gen_image() {
    local image=$1 tag=$2
    local ldir="$TOPDIR/$image/$tag"
    local system=apt
    local dockeriles=""
    if [ ! -e "$ldir" ];then mkdir -p "$ldir";fi
    cd "$ldir"
    if ( echo "$image $tag"|egrep -iq "redhat|centos|oracle|fedora|red-hat" );then
        system=redhat
    elif ( echo "$image $tag"|egrep -iq suse );then
        system=suse
    elif ( echo "$image $tag"|egrep -iq alpine );then
        system=alpine
    fi
    IMG=$image
    if [ -e ../tag ];then
        IMG=$(cat ../tag )
    fi
    export _cops_BASE=$image
    export _cops_SYSTEM=$system
    export _cops_VERSION=$tag
    export _cops_IMG=$DOCKER_REPO/$(basename $IMG)
    debug "IMG: $_cops_IMG | SYSTEM: $_cops_SYSTEM | BASE: $_cops_image | VERSION: $_cops_VERSION"
    for folder in . .. ../../..;do
        local df="$folder/Dockerfile.override"
        if [ -e "$df" ];then dockerfiles="$dockerfiles $df" && break;fi
    done
    local parts="from args argspost helpers pre base post clean cleanpost"
    for order in $parts;do
        for folder in . .. ../../..;do
            local df="$folder/Dockerfile.$order"
            if [ -e "$df" ];then dockerfiles="$dockerfiles $df" && break;fi
        done
    done
    if [[ -z $dockerfiles ]];then
        log "no dockerfile for $_cops_IMG"
        rc=1
        return $rc
    else
        debug "Using dockerfiles: $dockerfiles from $_cops_IMG"
    fi
    cat $dockerfiles | envsubst '$_cops_BASE;$_cops_VERSION;$_cops_SYSTEM' > Dockerfile
    cd - &>/dev/null
}

is_skipped() {
    local ret=1 t="$@"
    if ( echo "$t" | egrep -q "$SKIPPED_TAGS" );then
        ret=0
    fi
    if ( echo "$t" | egrep -q "/traefik" ) && ( echo "$t" | egrep -vq "alpine" );then
        ret=0
    fi
    return $ret
}

get_image_tags() {
    local n=$1
    local results="" result=""
    local i=0
    local has_more=0
    local t="$TOPDIR/$n/imagetags"
    local u="https://registry.hub.docker.com/v2/repositories/${n}/tags/"
    local last_modified=$(stat -c "%Y" "$t.raw" 2>/dev/null )
    if [ -e "$t.raw" ] && [ $(($CURRENT_TS-$last_modified)) -lt $((24*60*60)) ];then
        has_more=1
    fi
    if [ $has_more -eq 0 ];then
        while [ $has_more -eq 0 ];do
            i=$((i+1))
            result=$( curl "${u}?page=${i}" 2>/dev/null \
                | jq -r '."results"[]["name"]' 2>/dev/null )
            has_more=$?
            if [[ -n "${result}}" ]];then results="${results} ${result}";fi
        done
        rm -f "$t.raw"
        if [ ! -e "$TOPDIR/$n" ];then mkdir -p "$TOPDIR/$n";fi
        printf "$results\n" > "$t.raw"
    fi
    rm -f "$t"
    ( for i in $(cat "$t.raw");do
        if is_skipped "$n:$i";then debug "Skipped: $n:$i";else printf "$i\n";fi
      done | awk '!seen[$0]++' ) >> "$t"
    set -e
    if [ -e "$t" ];then cat "$t";fi
}

make_tags() {
    local image=$1
    log "Operating on $image"
    local tags=$(get_image_tags $image )
    debug "image: $image tags: $( echo $tags )"
    for t in $tags;do if ! ( gen_image "$image" "$t"; );then rc=1;fi;done
}


#  clean_tags $i: clean image tags
do_clean_tags() {
    local image=$1
    log "Cleaning on $image"
    local tags=$(get_image_tags $image )
    debug "image: $image tags: $( echo $tags )"
    while read image;do
        local tag=$(basename $image)
        if ! ( echo "$tags" | egrep -q "^$tag$" );then
            rm -rfv "$image"
        fi
    done < <(find "$TOPDIR/$image" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
}


#  refresh_images $args: refresh images files
#     refresh_images:  (no arg) refresh all images
#     refresh_images library/ubuntu: only refresh ubuntu images
do_refresh_images() {
    local images="${@:-$default_images}"
    while read image;do
        if [[ -n $image ]];then
            do_clean_tags $image
            make_tags $image
        fi
    done <<< "$images"
}

char_occurence() {
    local char=$1
    shift
    echo "$@" | awk -F"$char" '{print NF-1}'
}

record_build_image() {
    # library/ubuntu/latest / mdillion/postgis/latest
    local image=$1
    # ubuntu/latest / mdillion/postgis/latest
    local nimage=$(echo $image / sed -re "s/^library\///g")
    # corpusops
    local repo=$DOCKER_REPO
    # ubuntu / postgis
    local tag=$(basename $(dirname $image))
    # latest / latest
    local version=$(basename $image)
    local i=
    for i in $image $image/.. $image/../../..;do
        # ubuntu-bare / postgis
        if [ -e $i/repo ];then repo=$( cat $i/repo );break;fi
    done
    for i in $image $image/.. $image/../../..;do
        # ubuntu-bare / postgis
        if [ -e $i/tag ];then tag=$( cat $i/tag );break;fi
    done
    local df=${df:-Dockerfile}
    local cmd="docker build -t $repo/$tag:$version . -f $image/$df"
    local run="echo -e \"${RED}$cmd${NORMAL}\" && $cmd"
    book="$(printf "$run\n${book}" )"
}

#  build $args: refresh images files
#     build:  (no arg) refresh all images
#     build library/ubuntu: only refresh ubuntu images
#     build library/ubuntu/latest: only refresh ubuntu:latest image
do_build() {
    local images="${@:-$default_images}"
    local to_build=""
    local i=
    for i in $images;do
        local number_of_slash=$( char_occurence / $i )
        if [ ! -e $i ];then
            sdie "$i: folder does not exist yet, use refresh_images ?"
        elif [ $number_of_slash = 1 ];then
            to_build="$to_build $(find $i -mindepth 1 -maxdepth 1 -type d|sed "s/^.\///g"|sort -V)"
        elif [ $number_of_slash = 2 ];then
            to_build="$to_build $i"
        else
            sdie "$i: invalid number or slash: $number_of_slash"
        fi
    done
    local counter=0
    local book=""
    for i in $to_build;do
        record_build_image $i
        counter=$((counter+1))
    done
    book=$( echo "$book"|tac|awk '!seen[$0]++' )
    if [[ -n $book ]];then
        if [ $NBPARALLEL -gt 1 ];then
            if ! ( has_command parallel );then
                die "install Gnu parallel (package: parrallel on most distrib)"
            fi
            # be sure env_parallel is loaded
            if ! ( echo "$book" | parallel --joblog build.log -j$NBPARALLEL --tty $( [[ -n $DRYRUN ]] && echo "--dry-run" ); );then
                rc=124
            fi
            if [ -e build.log ];then cat build.log;fi
        else
            while read cmd;do
                if [[ -n $cmd ]];then
                    if ! (  $( [[ -n $DRYRUN ]] && echo "log Would run:" || echo "vv" ) $cmd );then rc=123;fi
                fi
            done <<< "$book"
        fi
    fi
    return $rc
}


#  list_images: list images family
do_list_image() {
    for i in $(find -mindepth 2 -type d);do
        if [ -e "$i/Dockerfile" ];then echo "$i";fi
    done\
    | egrep "$@" \
    | sed -re "s|(\./)?(([^/]+(/[^/]+)))(/.*)|\2\5|g"\
    | awk '!seen[$0]++' | sort -V
}
do_list_images() {
    for i in $(find -mindepth 2 -type d);do
        if [ -e "$i/Dockerfile" ];then echo "$i";fi
    done\
    | sed -re "s|(\./)?([^/]+/[^/]+)/.*|\2|g"\
    | awk '!seen[$0]++' | sort -V
}

PRORITY_IMAGES_ALPINE="
library/postgres/alpine \
library/postgres/11-alpine \
library/postgres/10-alpine \
library/postgres/9-alpine \
mdillion/postgis/alpine \
mdillion/postgis/11-alpine \
mdillion/postgis/10-alpine \
mdillion/postgis/9-alpine \
library/traefik/alpine \
library/nginx/alpine \
library/nginx/1.14-alpine \
library/nginx/1.12-alpine \
library/node/alpine \
library/node/lts-alpine \
library/node/slim-alpine \
library/node/7-alpine \
library/node/8-alpine \
library/node/9-alpine \
library/node/10-alpine \
library/node/11-alpine \
library/node/slim-alpine \
library/node/lts-slim-alpine \
library/node/slim-slim-alpine \
library/node/7-slim-alpine \
library/node/8-slim-alpine \
library/node/9-slim-alpine \
library/node/10-slim-alpine \
library/node/11-slim-alpine \
library/ruby/alpine \
library/ruby/1-alpine \
library/ruby/1.9-alpine \
library/ruby/2-alpine \
library/ruby/2.1-alpine \
library/ruby/2.2-alpine \
library/ruby/2.3-alpine \
library/ruby/2.4-alpine \
library/ruby/2.5-alpine \
library/ruby/slim-alpine \
library/ruby/1-slim-alpine \
library/ruby/1.9-slim-alpine \
library/ruby/2-slim-alpine \
library/ruby/2.1-slim-alpine \
library/ruby/2.2-slim-alpine \
library/ruby/2.3-slim-alpine \
library/ruby/2.4-slim-alpine \
library/ruby/2.5-slim-alpine \
library/php/alpine \
library/php/cli-alpine \
library/php/fpm-alpine \
library/php/zts-alpine \
library/php/5-alpine \
library/php/5-cli-alpine \
library/php/5-fpm-alpine \
library/php/5-zts-alpine \
library/php/5.6-alpine \
library/php/5.6-cli-alpine \
library/php/5.6-fpm-alpine \
library/php/5.6-zts-alpine \
library/php/7-alpine \
library/php/7-cli-alpine \
library/php/7-fpm-alpine \
library/php/7-zts-alpine \
library/php/7.0-alpine \
library/php/7.0-cli-alpine \
library/php/7.0-fpm-alpine \
library/php/7.0-zts-alpine \
library/php/7.1-alpine \
library/php/7.1-cli-alpine \
library/php/7.1-fpm-alpine \
library/php/7.1-zts-alpine \
library/php/7.2-alpine \
library/php/7.2-cli-alpine \
library/php/7.2-fpm-alpine \
library/php/7.2-zts-alpine \
library/php/7.3-alpine \
library/php/7.3-cli-alpine \
library/php/7.3-fpm-alpine \
library/php/7.3-zts-alpine \
library/solr/alpine \
library/solr/7-alpine \
library/solr/6-alpine \
library/solr/5-alpine \
library/solr/7-slim-alpine \
library/solr/6-slim-alpine \
library/solr/5-slim-alpine \
library/elasticsearch/1-alpine \
library/elasticsearch/2-alpine \
library/elasticsearch/5-alpine \
" \
PRORITY_IMAGES="
library/ubuntu/latest \
library/ubuntu/18.04 \
library/ubuntu/16.04 \
library/ubuntu/14.04 \
library/ubuntu/trusty \
library/ubuntu/xenial \
library/python/bionic \
library/python/3 \
library/python/3.6 \
library/python/3.7 \
library/python/2 \
library/node/latest \
library/golang/latest \
library/alpine/latest \
library/alpine/latest/3 \
library/centos/latest \
library/centos/7 \
library/debian/latest \
library/debian/7-slim \
library/debian/8-slim \
library/debian/9-slim \
library/debian/7 \
library/debian/8 \
library/debian/9 \
library/debian/sid-slim \
library/debian/stable-slim \
library/debian/sid \
library/debian/stable \
makinacorpus/pgrouting \
library/mysql/5 \
library/mysql/8 \
library/mysql/latest \
library/postgres/latest \
library/postgres/11 \
library/postgres/10 \
library/postgres/9 \
mdillion/postgis/latest \
mdillion/postgis/11 \
mdillion/postgis/10 \
mdillion/postgis/9 \
library/traefik/latest \
library/nginx/latest \
library/nginx/1.14 \
library/nginx/1.12 \
library/node/latest \
library/node/lts \
library/node/slim \
library/node/7 \
library/node/8 \
library/node/9 \
library/node/10 \
library/node/11 \
library/node/slim \
library/node/lts-slim \
library/node/slim-slim \
library/node/7-slim \
library/node/8-slim \
library/node/9-slim \
library/node/10-slim \
library/node/11-slim \
library/ruby/latest \
library/ruby/1 \
library/ruby/1.9 \
library/ruby/2 \
library/ruby/2.1 \
library/ruby/2.2 \
library/ruby/2.3 \
library/ruby/2.4 \
library/ruby/2.5 \
library/ruby/slim \
library/ruby/1-slim \
library/ruby/1.9-slim \
library/ruby/2-slim \
library/ruby/2.1-slim \
library/ruby/2.2-slim \
library/ruby/2.3-slim \
library/ruby/2.4-slim \
library/ruby/2.5-slim \
library/php/latest \
library/php/cli \
library/php/fpm \
library/php/zts \
library/php/5 \
library/php/5-cli \
library/php/5-fpm \
library/php/5-zts \
library/php/5.6 \
library/php/5.6-cli \
library/php/5.6-fpm \
library/php/5.6-zts \
library/php/7 \
library/php/7-cli \
library/php/7-fpm \
library/php/7-zts \
library/php/7.0 \
library/php/7.0-cli \
library/php/7.0-fpm \
library/php/7.0-zts \
library/php/7.1 \
library/php/7.1-cli \
library/php/7.1-fpm \
library/php/7.1-zts \
library/php/7.2 \
library/php/7.2-cli \
library/php/7.2-fpm \
library/php/7.2-zts \
library/php/7.3 \
library/php/7.3-cli \
library/php/7.3-fpm \
library/php/7.3-zts \
library/solr/latest \
library/solr/7 \
library/solr/6 \
library/solr/5 \
library/solr/7-slim \
library/solr/6-slim \
library/solr/5-slim \
library/mongo/latest \
library/mongo/2 \
library/mongo/3 \
library/mongo/4 \
library/elasticsearch/1 \
library/elasticsearch/2 \
library/elasticsearch/5 \
"
BATCHED_IMAGES="\
$PRORITY_IMAGES::1000
$PRORITY_IMAGES_ALPINE::1000
library/ubuntu library/elasticsearch::1000
library/solr library/nginx::25
library/traefik library/php library/debian library/python library/node library/ruby library/golang::70
library/mysql library/postgres mdillon/postgis makinacorpus/pgrouting::500
library/opensuse library/centos library/alpine library/mongo::100
"

is_in_images() {
    local ret=0
    local tomatch="$1"
    shift
    local i=""
    for i in $@;do
        if ! ( echo "$tomatch" | egrep -iq "($i(\"|)|(\"|)$i|^$i | $i | $i$)" );then
            ret=1
            break
        fi
    done
    return $ret
}

## needs to be set:  $_images_/$batch/$counter/$batchsize
get_batched_images() {
    local batch="  - IMAGES=\""
    local counter=0
    local default_batchsize=$1
    shift
    for i in $@;do
        local imgs=${i//::*}
        local batchsize=$default_batchsize
        if $(echo $i|grep -q ::);then batchsize=${i//*::};fi
        debug "_batch_images_($imgs :: $batchsize): $batch"
        for img in $imgs;do
            debug "_batch_image_($img :: $batchsize): $batch"
            local subimages=$(do_list_image $img)
            if [[ -z $subimages ]];then break;fi
            for j in $subimages;do
                if ! ( is_in_images "$_images_ $batch" $j );then
                    local space=" "
                    if [ `expr $counter % $batchsize` = 0 ];then
                        space=""
                        if [ $counter -gt 0 ];then
                            batch="$(printf -- "${batch}\"\n  - IMAGES=\""; )"
                        fi
                    fi
                    counter=$(( $counter+1 ))
                    batch="${batch}${space}${j}"
                fi
            done
        done
    done
    if [ $counter -gt 0 ];then
        _images_="$(printf "${_images_}\n${batch}\"" )"
    fi
}

#  gen_travis; regenerate .travis.yml file
do_gen_travis() {
    local _images_=''
    debug "_images_(pre): $_images_"
    # batch first each explicily built images
    while read imgs;do if [[ -n "$imgs" ]];then
        get_batched_images "${imgs//*::/}" "${imgs//::*/}"
    fi;done <<< "$BATCHED_IMAGES"
    # batch then all leftover images that werent batched at first
    get_batched_images 80 $(do_list_images)
    __IMAGES="$_images_" \
        envsubst '$__IMAGES;' > "$W/.travis.yml" \
        < "$W/.travis.yml.in"
}

#  gen: regenerate both images and travis.yml
do_gen() {
    if [[ -z "$NOREFRESH" ]];then do_refresh_images $@;fi
    do_gen_travis
}

#  usage: show this help
do_usage() {
    echo "$0:"
    # Show autodoc help
    awk '{ if ($0 ~ /^#[^!#]/) { \
                gsub(/^#/, "", $0); print $0 } }' \
                "$THISSCRIPT"|egrep -v "vim|^ colors"
    echo ""
}

do_main() {
    local args=${@:-usage}
    local actions="refresh_images|build|gen_travis|gen|list_images|clean_tags"
    actions="@($actions)"
    action=${1-};
    if [[ -n "$@" ]];then shift;fi
    case $action in
        $actions) do_$action $@;;
        *) do_usage;;
    esac
    exit $rc
}
cd "$W"
do_main "$@"
# vim:set et sts=4 ts=4 tw=0:
