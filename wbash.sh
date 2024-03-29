#!/bin/bash


# Host supported: athena, zeus, local
WHOST=zeus
declare -A DEFAULT_WORKDIR=( ["athena"]=work ["zeus"]=work ["local"]='..' )
declare -A DEFAULT_QUEUE=( ["athena"]=poe_medium ["zeus"]=p_gams ["local"]=fake )
declare -A DEFAULT_QUEUE_SHORT=( ["athena"]=poe_short ["zeus"]=s_short ["local"]=fake )
declare -A DEFAULT_BSUB=( ["athena"]="bsub -R span[hosts=1] -sla SC_gams" ["zeus"]="bsub -P 0352" ["local"]="local_bsub" )
declare -A DEFAULT_NPROC=( ["athena"]=8 ["zeus"]=18 ["local"]=fake ["acib"]=10 )
declare -A DEFAULT_SSH=( ["athena"]=ssh ["zeus"]=ssh ["local"]=local_ssh ["acib"]=ssh )
declare -A DEFAULT_RSYNC_PREFIX=( ["athena"]="athena:" ["zeus"]="zeus:" ["local"]="" ["acib"]="acib:" )
declare -A DEFAULT_WDIR_SAME=( ["athena"]="" ["zeus"]="" ["local"]="TRUE" ["acib"]="" )

WAIT=T

if [ "$PS4" = "+ " ]; then
    export PS4=$'\e[33m[wbash/$(eval echo $WHOST)]\e[0m '
fi

wecho-header () {
    blue=$(tput setaf 4)
    normal=$(tput sgr0)    
    printf "\n${blue}${@}${normal}\n"
}

wecho-confirm () {
  while true; do
    read -r -n 1 -p "${1:-Continue?} [y/n]: " REPLY
    case $REPLY in
      [yY]) echo ; return 0 ;;
      [nN]) echo ; return 1 ;;
      *) printf " \033[31m %s \n\033[0m" "invalid input"
    esac 
  done  
}

wsetup-zeus () {
    [ -z "$EDITOR" ] && read -p "Enter editor executable (code,vi,nano,emacs): " EDITOR
    STEP="$1"
    wecho-header "${STEP}) Setup Zeus"
    wecho-confirm || return 1
    wecho-header "${STEP}a) What is your username on zeus?"
    read -p "Enter username: " USER
    wecho-header "${STEP}b) Copy the following into ~/.ssh/config:"
    cat <<EOF
Host *
     Compression yes
     PreferredAuthentications publickey,password 
     Protocol 2
     ControlMaster auto
     ControlPath   ~/.ssh/control-%h-%p-%r
     ControlPersist 60m

Host zeus
     Hostname zeus01.cmcc.scc
     User $USER
     IdentityFile ~/.ssh/id_rsa.pub
EOF
    read -p "Press [Enter] to open ~/.ssh/config in your editor..."
    $EDITOR ~/.ssh/config
    wecho-header "${STEP}c) Copy your public key on zeus:"
    ssh-copy-id -i ~/.ssh/id_rsa.pub zeus
    read -p "Press [Enter] to continue..."
    wecho-header "${STEP}d) Test if connection work"
    read -p "Press [Enter] to connect to zeus, afterwards [ctrl-d] to proceed:"
    ssh zeus
    wecho-header "${STEP}e) Include the following lines in zeus ~/.bashrc"
    cat <<'EOF'
# gcc compiler
module load gcc_9.1.0/9.1.0

# curl
module load curl/7.66.0

# R
export R_LIBS_USER=~/R/x86_64-pc-linux-gnu-library/3.6
[ -d ${R_LIBS_USER} ] || mkdir -p ${R_LIBS_USER}
module load gcc_9.1.0/R/3.6.1

# GAMS
module load gams/28.2.0
EOF
    read -p "Press [Enter] to open zeus' bashrc locally and change it:"
    TEMP_BASHRC=$(mktemp)
    /usr/bin/rsync -avP zeus:.bashrc $TEMP_BASHRC
    $EDITOR $TEMP_BASHRC
    read -p "Press [Enter] to upload the file just edited to zeus' bashrc:"
    /usr/bin/rsync -avP $TEMP_BASHRC zeus:.bashrc
    wecho-header "${STEP}f) Create work link under home:"
    ssh zeus ln -sv -ni /work/seme/${USER}/ work
    read -p "Press [Enter] to continue..."
    wecho-header "${STEP}g) Sync witch-data & witchtools and install needed R libraries:"
    wecho-confirm && WHOST=zeus wsetup
    read -p "Press [Enter] to continue..."
}

wsetup-athena () {
    [ -z "$EDITOR" ] && read -p "Enter editor executable (code,vi,nano,emacs): " EDITOR
    STEP="$1"
    wecho-header "${STEP}) Setup Athena"
    wecho-confirm || return 1
    wecho-header "${STEP}a) What is your username on athena?"
    read -p "Enter username: " USER
    wecho-header "${STEP}b) Copy the following into ~/.ssh/config:"
    cat <<EOF
Host *
     Compression yes
     PreferredAuthentications publickey,password 
     Protocol 2
     ControlMaster auto
     ControlPath   ~/.ssh/control-%h-%p-%r
     ControlPersist 60m

Host itaca
     HostName itaca.cmcc.it
     User $USER
     IdentityFile ~/.ssh/id_rsa.pub

Host athena
     HostName athena
     User $USER
     ProxyCommand ssh itaca -W %h:%p
     IdentityFile ~/.ssh/id_rsa.pub
EOF
    read -p "Press [Enter] to open ~/.ssh/config in your editor..."
    $EDITOR ~/.ssh/config
    wecho-header "${STEP}c) Copy your public key on athena:"
    ssh-copy-id -i ~/.ssh/id_rsa.pub itaca
    /usr/bin/rsync -avP ~/.ssh/id_rsa.pub itaca:mykey.pub
    ssh itaca 'ssh-copy-id -i ~/mykey.pub athena'
    read -p "Press [Enter] to continue..."
    wecho-header "${STEP}d) Test if connection work"
    read -p "Press [Enter] to connect to athena, then [ctrl-d] to proceed:"
    ssh athena
    wecho-header "${STEP}e) Include the following lines in athena ~/.bashrc"
    cat <<'EOF'
# GAMS
. /users/home/opt/gams/load_latest_GAMS_module.sh
export PATH=$HOME/opt/gams:$PATH

# R
export R_LIBS_USER=~/R/x86_64-pc-linux-gnu-library/3.4
[ -d ${R_LIBS_USER} ] || mkdir -p ${R_LIBS_USER}
module load R/r-3.4.3

# GCC
module unload GCC/gcc-4.9.4
module load GCC/gcc-8.2.0
GCCPATH=/users/home/opt-intel_2018/gcc/gcc-8.2.0
export LD_LIBRARY_PATH=${GCCPATH}/lib:${GCCPATH}/lib64:${GCCPATH}/libexec:${LD_LIBRARY_PATH}
export CPATH=${GCCPATH}/include:${CPATH}
export C_INCLUDE_PATH=${GCCPATH}/include:${C_INCLUDE_PATH}
export CPLUS_INCLUDE_PATH=${GCCPATH}/include:${CPLUS_INCLUDE_PATH}

# GIT
module load GIT/git-2.18.0.321
EOF
    read -p "Press [Enter] to open athena's bashrc locally and change it:"
    TEMP_BASHRC=$(mktemp)
    /usr/bin/rsync -avP athena:.bashrc $TEMP_BASHRC
    $EDITOR $TEMP_BASHRC
    read -p "Press [Enter] to upload the file just edited to athena's bashrc:"
    /usr/bin/rsync -avP $TEMP_BASHRC athena:.bashrc
    wecho-header "${STEP}f) Create work link under home:"
    ssh athena ln -sv -ni /work/${USER}/ work
    read -p "Press [Enter] to continue..."
    wecho-header "${STEP}g) Sync witch-data & witchtools and install needed R libraries:"
    wecho-confirm && WHOST=athena wsetup
    read -p "Press [Enter] to continue..."
}

wsetup-ssh () {
    [ -z "$EDITOR" ] && read -p "Enter editor executable (code,vi,nano,emacs): " EDITOR
    STEP="$1"
    wecho-header "${STEP}a) Generate SSH keys"
    [ ! -f ~/.ssh/id_rsa.pub ] && ssh-keygen -t rsa
    ls -alh ~/.ssh/
    read -p "Press [Enter] to continue..."
    wecho-header "${STEP}b) Add SSH key to GitHub"
    printf 'Visit https://github.com/settings/ssh/new and add the following:\n'
    cat ~/.ssh/id_rsa.pub 
    read -p "Press [Enter] to continue..."
    wecho-header "${STEP}c) Check SSH connection to GitHub"
    ssh -T git@github.com
}

wsetup-wizard () {
    wecho-header '0a) Make sure you are in a WITCH cloned repo:'
    read -p "Press [Enter] to continue, [Ctrl-C] to exit and change directory..."
    wecho-header '0b) Choose your text editor'
    [ -z "$EDITOR" ] && read -p "Enter editor executable (code,vi,nano,emacs): " EDITOR
    echo "Using $EDITOR"
    EDITOR=$EDITOR wsetup-ssh 2
    EDITOR=$EDITOR wsetup-athena 3
    EDITOR=$EDITOR wsetup-zeus 4
    wecho-header '5) DONE!'
}


wshow () {
    SCEN="$1"
    ${DEFAULT_SSH[$WHOST]} -T ${WHOST} "cd ${DEFAULT_WORKDIR[$WHOST]}/$(wdirname) && sed -n 's/[*]/ /;s/ \+/ /g;/^Level SetVal/,/macro definitions/p;/macro definitions/q' ${SCEN}/${SCEN}.lst | cut -f 3,5 -d ' ' | sort -u -t\  -k1,1 | column -t -s' '" | perl -pe '$_ = "\e[92m$_\e[0m" if($. % 2)'
}

wrsync () {
    END_ARGS=FALSE
    RELATIVE="TRUE"
    while [ $END_ARGS = FALSE ]; do
        key="$1"
        case $key in
            -a|-absolute)
                RELATIVE=""
                shift
                ;;
            *)
                END_ARGS=TRUE
                ;;
        esac
    done
    RSYNC_ARGS=()
    [ -n "$RELATIVE" ] && RSYNC_ARGS=( --relative )
    set -x
    /usr/bin/rsync -avzP --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r "${RSYNC_ARGS[@]}" "${@}"
    { set +x; } 2>/dev/null
}

wdefault () {
    echo WHOST=${WHOST}
    echo DEFAULT_WORKDIR=${DEFAULT_WORKDIR[$WHOST]}
    echo DEFAULT_QUEUE=${DEFAULT_QUEUE[$WHOST]}
    echo DEFAULT_QUEUE_SHORT=${DEFAULT_QUEUE_SHORT[$WHOST]}
    echo DEFAULT_NPROC=${DEFAULT_NPROC[$WHOST]}
}

wsync () {
    WPWD="$(pwd)"
    [ -d ../witch-data ] || git clone git@github.com:witch-team/witch-data.git ../witch-data
    cd ../witch-data && git pull
    [ "$WHOST" = local ] || wup -t witch-data .
    [ -d ../witchtools ] || git clone git@github.com:witch-team/witchtools.git ../witchtools
    cd ../witchtools && git pull
    [ "$WHOST" = local ] || wup -t witchtools .
    [ -d ../gdxtools ] || git clone git@github.com:lolow/gdxtools.git ../gdxtools
    cd ../gdxtools && git pull
    [ "$WHOST" = local ] || wup -t gdxtools .
    cd "$WPWD"
    [ "$WHOST" = local ] || wup .
}

wsetup () {
    END_ARGS=FALSE
    FORCE_WITCHTOOLS="FALSE"
    FORCE_GDXTOOLS="FALSE"
    FORCE_HECTOR="FALSE"
    while [ $END_ARGS = FALSE ]; do
        key="$1"
        case $key in
            -w|-witchtools)
                FORCE_WITCHTOOLS="TRUE"
                shift
                ;;
            -g|-gdxtools)
                FORCE_GDXTOOLS="TRUE"
                shift
                ;;
            -h|-hector)
                FORCE_HECTOR="TRUE"
                shift
                ;;
            -a|-all)
                FORCE_WITCHTOOLS="TRUE"
                FORCE_GDXTOOLS="TRUE"
                FORCE_HECTOR="TRUE"
                shift
                ;;
            *)
                END_ARGS=TRUE
                ;;
        esac
    done
    wsync
    TEMP_SETUP_R=$(mktemp --suffix='.R')
    cat <<EOF > $TEMP_SETUP_R
r <- "https://cloud.r-project.org"

if(!require(remotes)) {
    install.packages("remotes", dependencies=TRUE, repos=r)
}

#if(!require(gdxtools)) {
    if (dir.exists("../gdxtools")) {
        remotes::install_local("../gdxtools", dependencies=TRUE, repos=r, force=${FORCE_GDXTOOLS})
    } else {
        remotes::install_github("lolow/gdxtools", dependencies=TRUE, repos=r, force=${FORCE_GDXTOOLS})
    }
#}

#if(!require(witchtools)) {
    if (dir.exists("../witchtools")) {
        remotes::install_local("../witchtools", dependencies=TRUE, repos=r, force=${FORCE_WITCHTOOLS})
    } else {
        remotes::install_github("witch-team/witchtools", dependencies=TRUE, repos=r, force=${FORCE_WITCHTOOLS})
    }
#}

#if(!require(hector)) {
    remotes::install_github('witch-team/hector', dependencies=TRUE, repos=r, force=${FORCE_HECTOR})
#}
EOF
    wrsync -a $TEMP_SETUP_R ${DEFAULT_RSYNC_PREFIX[$WHOST]}${DEFAULT_WORKDIR[$WHOST]}/$(wdirname)/
    wssh ${DEFAULT_BSUB[$WHOST]} -q ${DEFAULT_QUEUE[$WHOST]} -I -tty Rscript --vanilla $(basename $TEMP_SETUP_R)
    wssh rm -v $(basename $TEMP_SETUP_R)
    rm -v $TEMP_SETUP_R
}

wdirname () {
    # Name of directory under DEFAULT_WORKDIR to use for upload
    PWD="$(basename $(pwd))"
    DESTDIR="${PWD}"
    if [ -z "${DEFAULT_WDIR_SAME[$WHOST]}" ]; then
        if [ -d .git ]; then
            BRANCH="$(git branch --show-current)"
            [[ "$PWD" =~ .*${BRANCH} ]] && DESTDIR="${PWD}" || DESTDIR="${PWD}-${BRANCH}"
        fi
    fi
    #DESTDIR=${DESTDIR%-master}
    echo "${DESTDIR}"
}

wup () {
    USAGE="$(cat <<- EOM
    Upload SOURCE to ${DEFAULT_RSYNC_PREFIX[$WHOST]}${DEFAULT_WORKDIR[$WHOST]}/TARGET
    By default, TARGET="$(wdirname)".
    To upload current directory, use "." as SOURCE.
    If ALL not specified, upload only git-versioned files.

    Usage: wup [options] [wrsync arguments] SOURCE
    
    Options
    -l|-all             Upload also gitignored files
    -t|-target TARGET   Upload to subdir TARGET
EOM
)"
    END_ARGS=FALSE
    ONLY_GIT="TRUE"
    WTARGET="$(wdirname)"
    while [ $END_ARGS = FALSE ]; do
        key="$1"
        case $key in
            -l|-all)
                ONLY_GIT=""
                shift
                ;;
            -t|-target)
                WTARGET="$2"
                shift
                shift
                ;;
            *)
                END_ARGS=TRUE
                ;;
        esac
    done
    MAYBE_SOURCE=()
    [ $# -eq 0 ] && echo "$USAGE" && return 1
    [[ ! "${@: -1}" == [^-]* ]] && echo "$USAGE" && return 1
    RSYNC_ARGS=()
    TMPDIR=""
    if [ -n "$ONLY_GIT" ]; then
        TMPDIR="$(mktemp -d)"
        git -C . ls-files --exclude-standard -oi > ${TMPDIR}/excludes && RSYNC_ARGS=( --exclude=.git --exclude=.dvc --exclude-from=$(echo ${TMPDIR}/excludes) ) || RSYNC_ARGS=( --exclude=.git --exclude=.dvc )
    fi
    wrsync "${RSYNC_ARGS[@]}" ${@} ${DEFAULT_RSYNC_PREFIX[$WHOST]}${DEFAULT_WORKDIR[$WHOST]}/${WTARGET}
    RET=$?
    [ -n "$ONLY_GIT" ] && rm -r "${TMPDIR}"
    return $RET
}

wdown () {
    USAGE="$(cat <<- EOM
    Download SUBDIR from "${DEFAULT_RSYNC_PREFIX[$WHOST]}${DEFAULT_WORKDIR[$WHOST]}/$(wdirname)" using relative paths.
    Exclude all_data_*.gdx files unless otherwise stated.

    Usage: wdown [options] SUBDIR 

    Options
    -l|-all     Download also all_data_*.gdx file
EOM
)"
    [ $# -eq 0 ] && echo "$USAGE" && return 1
    END_ARGS=FALSE
    EXCLUDE_ALLDATATEMP="TRUE"
    while [ $END_ARGS = FALSE ]; do
        key="$1"
        case $key in
            -l|-all)
                EXCLUDE_ALLDATATEMP=""
                shift
                ;;   
            *)
                END_ARGS=TRUE
                ;;
        esac
    done
    RSYNC_ARGS=()
    [ -n "$EXCLUDE_ALLDATATEMP" ] && RSYNC_ARGS=(--exclude '*/all_data_*.gdx')
    wrsync "${RSYNC_ARGS[@]}" "${DEFAULT_RSYNC_PREFIX[$WHOST]}${DEFAULT_WORKDIR[$WHOST]}/$(wdirname)/./$1" .
}

wrun () {
    END_ARGS=FALSE
    QUEUE=${DEFAULT_QUEUE[$WHOST]}
    NPROC=${DEFAULT_NPROC[$WHOST]}
    JOB_NAME=""
    BSUB_INTERACTIVE=""
    CALIB=""
    ONLY_SOLVE=""
    VERBOSE=""
    RESDIR_CALIB=""
    USE_CALIB=""
    USE_CALIB2=""
    START=""
    STARTBOOST=""
    BAU=""
    BASELINE="ssp2"
    FIX=""
    DEST="${DEFAULT_RSYNC_PREFIX[$WHOST]}${DEFAULT_WORKDIR[$WHOST]}/$(wdirname)"
    REG_SETUP=""
    DRY_RUN=""
    EXTRA_ARGS=""
    POSTDB=""
    OUTSYNC="TRUE"
    while [ $END_ARGS = FALSE ]; do
        key="$1"
        case $key in
            # WITCH
            -s|-start)
                START="$2"
                shift
                shift
                ;;   
            -S|-startboost)
                START="$2"
                STARTBOOST=TRUE
                shift
                shift
                ;; 
            -r|-regions)
                REG_SETUP="$2"
                shift
                shift
                ;;
            -B|-baseline)
                BASELINE="$2"
                shift
                shift
                ;;
            -b|--bau)
                BAU="$2"
                shift
                shift
                ;;   
            -f|-gdxfix)
                FIX="$2"
                shift
                shift
                ;;
            -d|-debug)
                ONLY_SOLVE="$2"
                shift
                shift
                ;;            
            -v|-verbose)
                VERBOSE=TRUE
                shift
                ;;
            -P|-postdb)
                POSTDB=TRUE
                shift
                ;;
            # FLOW
            -z|-no-outsync)
                OUTSYNC=""
                shift
                ;;
            # CALIBRATION
            -c|-calib)
                CALIB=TRUE
                shift
                ;;
            -C|-resdircalib)
                RESDIR_CALIB=TRUE
                CALIB=TRUE
                shift
                ;;
            -u|-usecalib)
                USE_CALIB="$2"
                shift
                shift
                ;;
            -2|-usecalib2)
                USE_CALIB2="$2"
                shift
                shift
                ;;
            # BSUB
            -D|-dryrun)
                DRY_RUN=TRUE
                shift
                ;;
            -j|-job)
                JOB_NAME="$2"
                shift
                shift
                ;;
            -i|-interactive)
                BSUB_INTERACTIVE=TRUE
                shift
                ;;
            -q|-queue)
                QUEUE="$2"
                shift
                shift
                ;;
            -n|-nproc)
                NPROC="$2"
                shift
                shift
                ;;
            *)
                END_ARGS=TRUE
                ;;
        esac
    done
    [ -z "$JOB_NAME" ] && echo "Usage: wrun -j job-name [...]" && return 1
    [ -n "$CALIB" ] && EXTRA_ARGS="${EXTRA_ARGS} --calibration=1"
    [ -n "$RESDIR_CALIB" ] && EXTRA_ARGS="${EXTRA_ARGS} --write_tfp_file=resdir --caliboutgdx=${JOB_NAME}/data_calib_${JOB_NAME}"
    [ "$BASELINE" != "ssp2" ] && [ -n "$RESDIR_CALIB" ] && [ -z "$USE_CALIB" ] && echo "To calibrate ${BASELINE} within its folder you need -u calib_ssp2" && return 1
    if [ -n "$USE_CALIB" ]; then
        if [ "$BASELINE" != "ssp2" ]; then
            [ -n "$CALIB" ] && EXTRA_ARGS="${EXTRA_ARGS} --gdxfix=${USE_CALIB2}/results_${USE_CALIB2} --tfix=4 --tfpgdxssp2=${USE_CALIB2}/data_tfp_${USE_CALIB2}"
            [ -z "$CALIB" ] && [ -z "$USE_CALIB2" ] && echo "You need a -2 calib_ssp2" && return 1
            EXTRA_ARGS="${EXTRA_ARGS} --calibgdx=${USE_CALIB2}/data_calib_${USE_CALIB2} --tfpgdx=${USE_CALIB}/data_tfp_${USE_CALIB}"
        else
            EXTRA_ARGS="${EXTRA_ARGS} --calibgdx=${USE_CALIB}/data_calib_${USE_CALIB} --tfpgdx=${USE_CALIB}/data_tfp_${USE_CALIB}"
        fi
        [ -z "$BAU" ] && BAU="${USE_CALIB}/results_${USE_CALIB}.gdx"
        [ -z "$START" ] && START="${USE_CALIB}/results_${USE_CALIB}.gdx"
    fi
    if [ -n "$START" ]; then
        wssh test -f "$START" && STARTGDX_EXISTS=TRUE || STARTGDX_EXISTS=""
        if [ -z "$STARTGDX_EXISTS" ]; then
            BASE_START="$(basename "${START}")"
            if [ -f $START ]; then
                wrsync -a $START "$BASE_START"
                START="$BASE_START"
                wrsync -a $START ${DEST}/
            else
                START="${BASE_START}/results_${BASE_START}.gdx"
                wssh test -f "$START" && STARTGDX_EXISTS=TRUE || STARTGDX_EXISTS=""
                if [ -z "$STARTGDX_EXISTS" ]; then
                    START="${BASE_START}/all_data_temp_${BASE_START}.gdx"
                    wssh test -f "$START" && STARTGDX_EXISTS=TRUE || STARTGDX_EXISTS=""
                    if [ -z "$STARTGDX_EXISTS" ]; then
                        echo "Unable to find $START"
                        return 1
                    fi
                fi
            fi
        fi
        EXTRA_ARGS="${EXTRA_ARGS} --startgdx=${START%.gdx}"
        [ -z "$BAU" ] && BAU="${START}"
        [ -n "$CALIB" ] && EXTRA_ARGS="${EXTRA_ARGS} --tfpgdx=${START%.gdx}"
    fi
    if [ -n "$BAU" ]; then
        if [ ! "$BAU" = "0" ]; then
            wssh test -f "$BAU" && BAUGDX_EXISTS=TRUE || BAUGDX_EXISTS=""
            if [ -z "$BAUGDX_EXISTS" ]; then
                if [ -f $BAU ]; then
                    wrsync -a $BAU $(basename $BAU)
                    BAU=$(basename $BAU)
                    wrsync -a $BAU ${DEST}/
                else
                    BAU="${BAU}/results_$(basename ${BAU}).gdx"
                    wssh test -f "$BAU" && BAUGDX_EXISTS=TRUE || BAUGDX_EXISTS=""
                    if [ -z "$BAUGDX_EXISTS" ]; then
                        echo "Unable to find $BAU"
                        return 1
                    fi
                fi
            fi
        EXTRA_ARGS="${EXTRA_ARGS} --baugdx=${BAU%.gdx}"
        fi
    fi
    if [ -n "$FIX" ]; then
        if [ ! "$FIX" = "0" ]; then
            wssh test -f "$FIX" && FIXGDX_EXISTS=TRUE || FIXGDX_EXISTS=""
            if [ -z "$FIXGDX_EXISTS" ]; then
                if [ -f $FIX ]; then
                    wrsync -a $FIX $(basename $FIX)
                    FIX=$(basename $FIX)
                    wrsync -a $FIX ${DEST}/
                else            
                    FIX="${FIX}/results_$(basename ${FIX}).gdx"
                    wssh test -f "$FIX" && FIXGDX_EXISTS=TRUE || FIXGDX_EXISTS=""
                    if [ -z "$FIXGDX_EXISTS" ]; then
                        echo "Unable to find $FIX"
                        return 1
                    fi
                fi
            fi
            EXTRA_ARGS="${EXTRA_ARGS} --gdxfix=${FIX%.gdx}"
        fi
    fi
    [ -n "$ONLY_SOLVE" ] && EXTRA_ARGS="${EXTRA_ARGS} --max_iter=1 --rerun=3 --only_solve=${ONLY_SOLVE} --limrow=100000 --limcol=100000" || EXTRA_ARGS="${EXTRA_ARGS} --solvergrid=memory"
    [ -n "$VERBOSE" ] && EXTRA_ARGS="${EXTRA_ARGS} --verbose=1"
    [ -n "$STARTBOOST" ] && EXTRA_ARGS="${EXTRA_ARGS} --startboost=1"
    [ -n "$REG_SETUP" ] && EXTRA_ARGS="${EXTRA_ARGS} --n=${REG_SETUP}"
    wup .
    wup -l input/data
    BSUB="${DEFAULT_BSUB[$WHOST]}"
    [ -n "$BSUB_INTERACTIVE" ] && BSUB="$BSUB -I -tty"
    if [ -z "${DRY_RUN}" ]; then
        CHDIR="${DEFAULT_WORKDIR[$WHOST]}/$(wdirname)"
        set -x
        ${DEFAULT_SSH[$WHOST]} ${WHOST} "cd ${CHDIR} && rm -rfv ${JOB_NAME}/*.{lst,err,out,txt} 225_${JOB_NAME} && mkdir -p ${JOB_NAME} 225_${JOB_NAME} && $BSUB -J ${JOB_NAME} -n $NPROC -R span[ptile=${NPROC}] -q $QUEUE -o ${JOB_NAME}/${JOB_NAME}.out -e ${JOB_NAME}/${JOB_NAME}.err \"gams run_witch.gms ps=0 pw=32767 gdxcompress=1 Output=${JOB_NAME}/${JOB_NAME}.lst Procdir=225_${JOB_NAME} --nameout=${JOB_NAME} --resdir=${JOB_NAME}/ --gdxout=results_${JOB_NAME} ${EXTRA_ARGS} --baseline=${BASELINE} ${@}\""
        { set +x; } 2>/dev/null
        if [ -n "$BSUB_INTERACTIVE" ]; then
            #BAU4DB="${BAU/$JOB_NAME\//}"
            #BAU4DB="${BAU4DB/.gdx/}"
            # BAU4DB="${BAU}"
            # -b "${BAU4DB}"
            [ -n "$POSTDB" ] && wdb "$JOB_NAME"
            if [ -n "$OUTSYNC" ]; then
                [ -n "$CALIB" ] && [ -z "$RESDIR_CALIB" ] && wdown 'data_*'
                wdown "${JOB_NAME}"
            fi
            [ -x /usr/bin/notify-send ] && notify-send "Done ${JOB_NAME}" || true
        fi
    fi
}

wworktree () {
    BRANCH="$1"
    [ -z "${BRANCH}" ] && echo "Usage: wworktree branch-name" && return 1
    _REMOTE="$2"
    REMOTE="${_REMOTE:-origin}"
    # check if branch exists
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    CURRENT_DIR=$(basename $(pwd))
    ROOT_NAME=${CURRENT_DIR%"-${CURRENT_BRANCH}"}
    git fetch
    git branch --remotes | grep --extended-regexp "^[[:space:]]+${REMOTE}/${BRANCH}$"
    if [ ! $? -eq 0 ]; then
        echo "Creating branch ${REMOTE}/${BRANCH}..."
        git checkout -b "${BRANCH}"
        git push -u ${REMOTE} HEAD
        git checkout ${CURRENT_BRANCH}
    else
        git checkout ${REMOTE}/${BRANCH}
        git checkout ${CURRENT_BRANCH}
    fi
    set -x
    TGT_DIR="../${ROOT_NAME}-${BRANCH}"
    git worktree add --checkout ${TGT_DIR} ${BRANCH}
    cd ${TGT_DIR}
    # git worktree add -b $BRANCH ../$(basename $(pwd))-${BRANCH} ${REMOTE}/${BRANCH}
    { set +x; } 2>/dev/null
}

wdb () {
    _WHOST="local"
    END_ARGS=FALSE
    QUEUE=${DEFAULT_QUEUE[$_WHOST]}
    NPROC=${DEFAULT_NPROC[$_WHOST]}
    JOB_NAME=""
    DEST="${DEFAULT_RSYNC_PREFIX[$_WHOST]}${DEFAULT_WORKDIR[$_WHOST]}/$(wdirname)"
    DRY_RUN=""
    DB_OUT=""
    EXTRA_ARGS=""
    GDXBAU=""
    while [ $END_ARGS = FALSE ]; do
        key="$1"
        case $key in
            # WITCH
            -o|-dbout)
                DB_OUT="$2"
                shift
                shift
                ;;   
            -b|-baugdx)
                GDXBAU="$2"
                shift
                shift
                ;;   
            *)
                END_ARGS=TRUE
                ;;
        esac
    done
    SCEN="$1"
    shift
    [ -z "$GDXBAU" ] && GDXBAU="${SCEN}/results_${SCEN}.gdx"
    PROCDIR="225_db_${SCEN}"
    [ -z "$DB_OUT" ] && DB_OUT="db_${SCEN}"
    BSUB="${DEFAULT_BSUB[$_WHOST]} -I -tty"
    WHOST=local wup .
    WHOST=local echo ${DEFAULT_SSH[$_WHOST]} ${_WHOST} "cd ${DEFAULT_WORKDIR[$_WHOST]}/$(wdirname) && rm -rfv ${SCEN}/db_* && $BSUB -J db_${SCEN} -n 1 -q $QUEUE -o ${SCEN}/db_${SCEN}.out -e ${SCEN}/db_${SCEN}.err \"gams post/database.gms ps=0 pw=32767 gdxcompress=1 Output=${SCEN}/db_${SCEN}.lst --outgdx=results_${SCEN} --outgdx_db=${DB_OUT} --resdir=${SCEN}/ --baugdx=${GDXBAU} ${@}\""
    WHOST=local ${DEFAULT_SSH[$_WHOST]} ${_WHOST} "cd ${DEFAULT_WORKDIR[$_WHOST]}/$(wdirname) && rm -rfv ${SCEN}/db_* && $BSUB -J db_${SCEN} -n 1 -q $QUEUE -o ${SCEN}/db_${SCEN}.out -e ${SCEN}/db_${SCEN}.err \"gams post/database.gms ps=0 pw=32767 gdxcompress=1 Output=${SCEN}/db_${SCEN}.lst --outgdx=results_${SCEN} --outgdx_db=${DB_OUT} --resdir=${SCEN}/ --baugdx=${GDXBAU} ${@}\""
    WHOST=local wdown "${SCEN}/db*gdx"
    [ -x /usr/bin/notify-send ] && notify-send "Done db_${SCEN}" || true
}


wgams () {
    USAGE="$(cat <<- EOM
    Change dir to ${WHOST}:${DEFAULT_WORKDIR[$WHOST]}/$(wdirname), then bsub a gams job.
    Put .out, .err and .lst files under JOB_NAME dir, use 225_JOB_NAME as procdir.
    If interactive is on, download JOB_NAME dir after finishing.

    Usage: wgams -j JOB_NAME [options] file.gms [gams arguments]

    Options:
    -j|-job JOB_NAME    Set name of the job to JOB_NAME (mandatory option)
    -n|-nproc X         Set number of processors for the job to X
    -i|-interactive     Wait for job to finish before returning
    -q|-queue X         Choose queue X
EOM
)"
    END_ARGS=FALSE
    QUEUE=${DEFAULT_QUEUE[$WHOST]}
    NPROC=${DEFAULT_NPROC[$WHOST]}
    JOB_NAME=""
    BSUB_INTERACTIVE=""
    DEST="${DEFAULT_RSYNC_PREFIX[$WHOST]}${DEFAULT_WORKDIR[$WHOST]}/$(wdirname)"
    REG_SETUP=""
    DRY_RUN=""
    EXTRA_ARGS=""
    [ $# -eq 0 ] && echo "$USAGE" && return 1
    while [ $END_ARGS = FALSE ]; do
        key="$1"
        case $key in
            # BSUB
            -j|-job)
                JOB_NAME="$2"
                shift
                shift
                ;;
            -i|-interactive)
                BSUB_INTERACTIVE=TRUE
                shift
                ;;
            -q|-queue)
                QUEUE="$2"
                shift
                shift
                ;;
            -n|-nproc)
                NPROC="$2"
                shift
                shift
                ;;
            *)
                END_ARGS=TRUE
                ;;
        esac
    done
    [ -z "$JOB_NAME" ] && echo "Usage: wrun -j job-name [...]" && return 1
    BSUB="${DEFAULT_BSUB[$WHOST]}"
    [ -n "$BSUB_INTERACTIVE" ] && BSUB="$BSUB -I -tty"
    PROCDIR="225_${JOB_NAME}"
    wup
    set -x
    ${DEFAULT_SSH[$WHOST]} ${WHOST} "cd ${DEFAULT_WORKDIR[$WHOST]}/$(wdirname) && rm -rfv ${PROCDIR} && mkdir -p ${PROCDIR} ${JOB_NAME} && $BSUB -J ${JOB_NAME} -n $NPROC -q $QUEUE -o ${JOB_NAME}/${JOB_NAME}.out -e ${JOB_NAME}/${JOB_NAME}.err \"gams ${@} ps=0 pw=32767 gdxcompress=1 Output=${JOB_NAME}/${JOB_NAME}.lst Procdir=${PROCDIR}\""
    RETVAL=$?
    { set +x; } 2>/dev/null
    if [ -n "$BSUB_INTERACTIVE" ]; then
        wdown "$JOB_NAME"
        [ -x /usr/bin/notify-send ] && notify-send "Done ${JOB_NAME}" || true
    fi
    return $RETVAL
}

wsub () {
    END_ARGS=FALSE
    QUEUE=${DEFAULT_QUEUE[$WHOST]}
    NPROC=${DEFAULT_NPROC[$WHOST]}
    JOB_NAME=""
    BSUB_INTERACTIVE=""
    DEST="${DEFAULT_RSYNC_PREFIX[$WHOST]}${DEFAULT_WORKDIR[$WHOST]}/$(wdirname)"
    REG_SETUP=""
    DRY_RUN=""
    EXTRA_ARGS=""
    SYNC=""
    while [ $END_ARGS = FALSE ]; do
        key="$1"
        case $key in
            # BSUB
            -j|-job)
                JOB_NAME="$2"
                shift
                shift
                ;;
            -i|-interactive)
                BSUB_INTERACTIVE=TRUE
                shift
                ;;
            -q|-queue)
                QUEUE="$2"
                shift
                shift
                ;;
            -Y|-sync)
                SYNC=TRUE
                shift
                ;;
            -n|-nproc)
                NPROC="$2"
                shift
                shift
                ;;
            *)
                END_ARGS=TRUE
                ;;
        esac
    done
    [ -z "$JOB_NAME" ] && echo "Usage: wrun -j job-name [...]" && return 1
    BSUB="${DEFAULT_BSUB[$WHOST]}"
    [ -n "$BSUB_INTERACTIVE" ] && BSUB="$BSUB -I -tty"
    wup
    set -x
    ${DEFAULT_SSH[$WHOST]} ${WHOST} "cd ${DEFAULT_WORKDIR[$WHOST]}/$(wdirname) && rm -rfv ${PROCDIR} && mkdir -p ${PROCDIR} ${JOB_NAME} && $BSUB -J ${JOB_NAME} -n $NPROC -q $QUEUE -o ${JOB_NAME}.out -e ${JOB_NAME}.err \"${@}\""
    RETVAL=$?
    { set +x; } 2>/dev/null
    if [ -n "$BSUB_INTERACTIVE" ]; then
        [ -n "$SYNC" ] && wdown ${JOB_NAME}
        [ -x /usr/bin/notify-send ] && notify-send "Done ${JOB_NAME}" || true
    fi
    return $RETVAL
}


wdata () {
    END_ARGS=FALSE
    QUEUE=${DEFAULT_QUEUE_SHORT[$WHOST]}
    BSUB_INTERACTIVE="TRUE"
    SYNC=""
    REG_SETUP="witch17"
    METHOD="dvc"
    while [ $END_ARGS = FALSE ]; do
        key="$1"
        case $key in
            # BSUB
            -n|-regions)
                REG_SETUP="$2"
                shift
                shift
                ;;
            -m|-method)
                METHOD="$2"
                shift
                shift
                ;;
            -N|-noninteractive)
                BSUB_INTERACTIVE=
                shift
                ;;
            -Y|-sync)
                SYNC=TRUE
                shift
                ;;
            *)
                END_ARGS=TRUE
                ;;
        esac
    done
    JOB_NAME="data_${REG_SETUP}"
    [ -z "$SYNC" ] || wsync
    BSUB="${DEFAULT_BSUB[$WHOST]}"
    SETUP="-n ${REG_SETUP} -m ${METHOD}"
    [ -n "$BSUB_INTERACTIVE" ] && BSUB="$BSUB -I -tty"
    CHDIR="${DEFAULT_WORKDIR[$WHOST]}/$(wdirname)"
    set -x
    ${DEFAULT_SSH[$WHOST]} ${WHOST} "cd ${CHDIR} && rm -rfv ${JOB_NAME}/${JOB_NAME}.{err,out} && mkdir -p ${JOB_NAME} && $BSUB -J ${JOB_NAME} -n 1 -q $QUEUE -o ${JOB_NAME}/${JOB_NAME}.out -e ${JOB_NAME}/${JOB_NAME}.err \"Rscript --vanilla input/translate_witch_data.R ${SETUP} ${@}\""
    { set +x; } 2>/dev/null
    if [ -n "$BSUB_INTERACTIVE" ]; then
        [ -n "$SYNC" ] && wdown ${JOB_NAME}
        [ -x /usr/bin/notify-send ] && notify-send "Done ${JOB_NAME}" || true
    fi
}


local_bsub () {
    END_ARGS=FALSE
    while [ $END_ARGS = FALSE ]; do
        key="$1"
        case $key in
            # BSUB
            -R)
                shift
                shift
                ;;
            -n)
                shift
                shift
                ;;
            -o)
                shift
                shift
                ;;
            -e)
                shift
                shift
                ;;
            -q)
                shift
                shift
                ;;
            -J)
                shift
                shift
                ;;
            -I)
                shift
                ;;
            -tty)
                shift
                ;;
            *)
                END_ARGS=TRUE
                ;;
        esac
    done
    eval "$@"
}

wssh () {
    CHDIR="${DEFAULT_WORKDIR[$WHOST]}/$(wdirname)"
    set -x
    ${DEFAULT_SSH[$WHOST]} -T ${WHOST} "cd ${CHDIR} && $@"
    RETVAL=$?
    { set +x; } 2>/dev/null
    (exit $RETVAL);
}

wsshq () {
   ${DEFAULT_SSH[$WHOST]} -T ${WHOST} "cd ${DEFAULT_WORKDIR[$WHOST]}/$(wdirname) && \"${@}\""
}

wcheck () {
    JOB_NAME="$1"
    if [ -z "$JOB_NAME" ]; then
        ssh ${WHOST} bjobs -w
    else
        ssh ${WHOST} "cd ${DEFAULT_WORKDIR[$WHOST]}/$(wdirname) && bpeek -f -J ${JOB_NAME}"
    fi
}

wrename () {
    OLDNAME="$1"
    NEWNAME="$2"
    [ "$#" -ne 2 ] && echo 'Usage: wrename OLD_DIRECTORY_NAME NEW_DIRECTORY_NAME' && return 1
    mv -v "$OLDNAME" "$NEWNAME"
    cd "$NEWNAME"
    for f in *; do
        mv -v "${f}" "${f/$OLDNAME/$NEWNAME}"
    done
    cd -
}

werr () {
    JOB_NAME="$1"
    if [ -z "$JOB_NAME" ]; then
        A=$(ssh ${WHOST} "bjobs -w | tail -n +2 | cut -f17 -d\ ")
        echo "$A"
        IFS=$'\n'
        for JOB_NAME in $A; do
            echo "Checking ${JOB_NAME}..."
            ssh ${WHOST} "cd ${DEFAULT_WORKDIR[$WHOST]}/$(wdirname) && tail -n 20 ${JOB_NAME}/errors_${JOB_NAME}.txt"
            echo $?
        done
    else
        ssh ${WHOST} "cd ${DEFAULT_WORKDIR[$WHOST]}/$(wdirname) && tail -n 20 ${JOB_NAME}/errors_${JOB_NAME}.txt"
    fi
}


wtemp ()
{
JOB_NAME="$1"
WORKDIR=${DEFAULT_WORKDIR[$WHOST]}/$(wdirname)/${JOB_NAME}
    TEMP_SETUP_SH=$(mktemp --suffix='.sh')
    cat <<'EOF' > $TEMP_SETUP_SH
JOB_NAME="$1"
F=${JOB_NAME}/all_data_temp_${JOB_NAME}.gdx
FNAME=${JOB_NAME}/temp_${JOB_NAME}
cp ${F} ${FNAME}_1.gdx
until gdxdump ${FNAME}_1.gdx -V 2>&1 >/dev/null; do sleep 2; cp ${F} ${FNAME}_1.gdx; done
AHASH=$(md5sum ${FNAME}_1.gdx | cut -d' ' -f1)
echo "${F} -> ${FNAME}_1.gdx (${AHASH})"
tail -n1 ${JOB_NAME}/errors_${JOB_NAME}.txt
BHASH=$AHASH
while [ "$AHASH" == "$BHASH" ]; do sleep 2;BHASH=$(md5sum ${F} | cut -d' ' -f1); done
cp ${F} ${FNAME}_2.gdx
until gdxdump ${FNAME}_2.gdx -V 2>&1 >/dev/null; do sleep 2; cp ${F} ${FNAME}_2.gdx; done
BHASH=$(md5sum ${FNAME}_2.gdx | cut -d' ' -f1)
echo "${F} -> ${FNAME}_2.gdx (${BHASH})"
tail -n1 ${JOB_NAME}/errors_${JOB_NAME}.txt
EOF
    wrsync -a $TEMP_SETUP_SH ${DEFAULT_RSYNC_PREFIX[$WHOST]}${DEFAULT_WORKDIR[$WHOST]}/$(wdirname)/
    wssh bash $(basename $TEMP_SETUP_SH) $JOB_NAME
    wdown -l "${JOB_NAME}/temp*"
    wssh rm -v $(basename $TEMP_SETUP_SH)
    rm -v $TEMP_SETUP_SH
}


wclean ()
{
wssh rm -rv 225* */*{lst,out,err}
}

wcompare () {
    ADIR="$1"
    BDIR="$2"
    for F in ${ADIR}/*.gdx; do
        FBASE=$(basename "$F")
        G=${BDIR}/${FBASE}
        if [ -f $G ]; then
            gdxdump $F > prova1.txt
            gdxdump $G > prova2.txt
            ASUM=$(md5sum prova1.txt | cut -d' ' -f1)
            BSUM=$(md5sum prova2.txt | cut -d' ' -f1)
            if [ $ASUM != $BSUM ]; then
                echo "Showing differences for ${FBASE}"
                bcompare prova1.txt prova2.txt
            fi
        fi
    done
}
    
#     [ $# -lt 3 ] && echo 'Usage: wrun [job-name] [ncpu]exit 1
#     mkdir -p ${JOB_NAME}
#     bsub -J ${JOB_NAME} -I -R span[hosts=1] -sla SC_gams -n $(3) -q poe_medium -o ${JOB_NAME}/${JOB_NAME}.out -e ${JOB_NAME}/${JOB_NAME}.err '$(2)'

# wrun-contained ()
# {
# RUN=$1
# NPROC=$2
# wrun_general serial_24h ${RUN} ${NPROC} ${@:3}
# }

# WITCH_CMD = rm -rfv ${JOB_NAME} 225_${JOB_NAME} && mkdir -p ${JOB_NAME} 225_${JOB_NAME} && gams run_witch.gms ps=9999 pw=32767 gdxcompress=1 Output=${JOB_NAME}/${JOB_NAME}.lst Procdir=225_${JOB_NAME} --nameout=${JOB_NAME} --resdir=${JOB_NAME}/ --gdxout=results_${JOB_NAME} $(2) && cat ${JOB_NAME}/errors_${JOB_NAME}.txt
# WCALIB = --calibration=1 --write_tfp_file=resdir --caliboutgdx=${JOB_NAME}/tfp_${JOB_NAME}
# WDEBUG := 
# ## BSUB_CMD (1: job-name) (2: command to bsub) (3: number of cores)
# BSUB_CMD       = mkdir -p ${JOB_NAME} && bsub -J ${JOB_NAME} -I -R span[hosts=1] -sla SC_gams -n $(3) -q poe_medium -o ${JOB_NAME}/${JOB_NAME}.out -e ${JOB_NAME}/${JOB_NAME}.err '$(2)'
# BSUB_CMD_QUEUE = mkdir -p ${JOB_NAME} && bsub -J ${JOB_NAME} -R span[hosts=1] -sla SC_gams -n $(3) -q poe_medium -o ${JOB_NAME}/${JOB_NAME}.out -e ${JOB_NAME}/${JOB_NAME}.err '$(2)'
# ## BSUB_WITCH (1: job-name) (2: extra arguments to gams run_witch.gms)
# BSUB_WITCH = $(call BSUB_CMD,${JOB_NAME},$(call RUN_WITCH,${JOB_NAME},$(2)),8)
# ## SSH_RUN (1: job-name) (2: cmd to run)
# SSH_CMD       = $(MAKE) up && ssh athena "cd work/witch-techno-cost/ && ${JOB_NAME}";$(RSYNC) athena:'work/witch-techno-cost/$(2)' ./
# SSH_CMD_QUEUE = $(MAKE) up && ssh athena "cd work/witch-techno-cost/ && ${JOB_NAME}"
# ## RUN_XXX (1: cmd to run) (2: job-name) (3: num cpus)
# RUN_SSH = $(call SSH_CMD,$(call BSUB_CMD,$(2),${JOB_NAME},$(3)),$(2))
# RUN_LOC = export R_GAMS_SYSDIR=/opt/gams && ${JOB_NAME}
# RUN_QUEUE = $(call SSH_CMD_QUEUE,$(call BSUB_CMD_QUEUE,$(2),${JOB_NAME},$(3)),$(2))




# wdump ()
# {
# WHAT=$1
# shift
# while [ "$1" != "" ]; do
#     for f in ${1}/all_data_temp*gdx; do
#         echo -e "\n\e[33m${f}:\e[0m" 1>&2 
#         gdxdump $f symb=${WHAT}
#     done
#     shift
# done
# }

# wcleandir ()
# {
# SCENDIR=$1
# PROCDIR=225_${SCENDIR}
# if [ -d ${PROCDIR} ]; then
# rm -rf ${PROCDIR}/*
# else
# mkdir -p ${PROCDIR}
# fi
# if [ -d ${SCENDIR} ]; then
# rm ${SCENDIR}/{*lst,job*{out,err}}
# else
# mkdir -p ${SCENDIR}
# fi
# }

# wrun_general ()
# {
# QUEUE=$1
# RUN=$2
# NPROC=$3
# wcleandir ${RUN}
# mkdir -p ${RUN} 225_${RUN}
# EXTRA_ARGS=""
# PREV_CONV="$(gdxdump ${RUN}/results_${RUN}.gdx symb=stop_nash format=csv | tail -n1 | sed 's/[[:space:]]//g')"
# if [[ $PREV_CONV =~ ^1$ ]]; then
# [[ ! ${@:4} =~ startgdx ]] && EXTRA_ARGS="$EXTRA_ARGS --startgdx=${RUN}/results_${RUN} --calibgdx=${RUN}/results_${RUN} --tfpgdx=${RUN}/results_${RUN}"
# [[ ! ${@:4} =~ startgdx ]] && [[ ! ${@:4} =~ gdxfix ]] && EXTRA_ARGS="$EXTRA_ARGS --startboost=1"
# [[ ! ${@:4} =~ baugdx ]] && [[ ${RUN} =~ bau ]] && EXTRA_ARGS="$EXTRA_ARGS --baugdx=${RUN}/results_${RUN}"
# fi
# [ -z "$EXTRA_ARGS" ] || echo "AUTO EXTRA ARGS: $EXTRA_ARGS"
# bsub -n${NPROC} -J "$RUN" -R "span[hosts=1]" -q ${QUEUE} -o ${RUN}/job_${RUN}.out -e ${RUN}/job_${RUN}.err gams call_default.gms pw=32767 gdxcompress=1 Output="${RUN}/${RUN}.lst" Procdir=225_${RUN} --nameout="${RUN}" --resdir=$RUN/ --gdxout=results_${RUN} --gdxout_report=report_${RUN} --gdxout_start=start_${RUN} --verbose=1 --parallel=incore ${EXTRA_ARGS} ${@:4}
# }


# wrun6 ()
# {
# RUN=$1
# NPROC=$2
# wrun_general serial_6h ${RUN} ${NPROC} ${@:3}
# }

# wbrun ()
# {
# RUN=$1
# NPROC=$2
# BASEGDX=$3
# wrun ${RUN} ${NPROC} --startgdx=${BASEGDX} --baugdx=${BASEGDX} --calibgdx=${BASEGDX} --tfpgdx=${BASEGDX} --startboost=1 ${@:4}
# }      

# wbrun6 ()
# {
# RUN=$1
# NPROC=$2
# BASEGDX=$3
# wrun6 ${RUN} ${NPROC} --startgdx=${BASEGDX} --baugdx=${BASEGDX} --calibgdx=${BASEGDX} --tfpgdx=${BASEGDX} --startboost=1 ${@:4}
# }      

# wcrun ()
# {
# RUN=$1
# NPROC=$2
# BASEGDX=$3
# wbrun ${RUN} ${NPROC} ${BASEGDX} --calibration=1 ${@:4}
# }      

# wfrun ()
# {
# RUN=$1
# NPROC=$2
# BASEGDX=$3
# wbrun ${RUN} ${NPROC} ${BASEGDX} --gdxfix=${BASEGDX} ${@:4}
# }      

# wtax ()
# {
# RUN=$1
# NPROC=$2
# BASEGDX=$3
# TAXSTARTPERIOD=$4
# TAXSTARTVAL=$5
# TAXGROWTHRATE=$6
# TFIX=$(expr ${TAXSTARTPERIOD} - 1)
# echo "Carbon tax starting in period ${TAXSTARTPERIOD} at ${TAXSTARTVAL} USD2005/tCO2 and growing at ${TAXGROWTHRATE} rate"
# wfrun ${RUN} ${NPROC} ${BASEGDX} --tfix=${TFIX} --policy=ctax --tax_start=${TAXSTARTPERIOD} --ctax2015=${TAXSTARTVAL} --ctaxgrowth=${TAXGROWTHRATE} ${@:7}
# }      

# wfind ()
# {
# grep -i "$1" *.gms */*.gms
# }

# gdiff ()
# {
#     type dwdiff &>nul 2>&1;
#     if [ $? -eq 0 ]; then
#         CMD=dwdiff;
#     else
#         if [ ! -f dwdiff ]; then
#             echo 'WARN: dwdiff tool not found... downloading'
#             curl http://os.ghalkes.nl/dist/dwdiff-2.1.0.tar.bz2 > dwdiff-2.1.0.tar.bz2
#             tar xjf dwdiff-2.1.0.tar.bz2 
#             cd dwdiff-2.1.0
#             ./configure
#             make all
#             mv dwdiff ../
#             cd ..
#             rm -rf dwdiff-2.1.0.tar.bz2 dwdiff-2.1.0
#             CMD=./dwdiff;
#         fi
#     fi;
#     SYMB=$1;
#     MATCHES=$2
#     DMPLIST=(one two);
#     IGDX=0;
#     AWKPARAM="/\"$(sed 's|,|[a-z]*"/ \&\& /"|g' <<<"${MATCHES}")[a-z]*\"/"
#     for GDX in ${@:3};
#     do
#         echo $GDX;
#         DMP=${GDX%.gdx}zzz.txt;
#         rm -fv "$DMP"
#         gdxdump $GDX symb=$SYMB format=csv | awk "$AWKPARAM" | sed 's/","/ /g;s/"//g;s/,/ /;' > "$DMP"
#         DMPLIST[IGDX]=$DMP;
#         let IGDX=IGDX+1;
#     done;
#     $CMD -c -L -d' ,.' ${DMPLIST[@]}
# }

local_ssh () {
    END_ARGS=FALSE 
    while [ $END_ARGS = FALSE ]; do
        key="$1"
        case $key in
            -T)
                shift
                ;;
            *)
                END_ARGS=TRUE
                ;;
        esac
    done
    shift
    eval "$@"
}

# alias bw='bjobs -w'

# alias bwg='bjobs -w | egrep -i'

# alias bag='bjobs -aw | grep -i'

# alias bal='bjobs -aw | tail'

# alias bl='bjobs -l'

# alias blj='bjobs -l -J'

# alias bf='bpeek -f'

# alias bfj='bpeek -f -J'

# alias bq='bqueues | egrep "(QUEUE_NAME|serial|gams)"'

# alias bk='bkill'

# alias bkj='bkill -J'

# alias lsl='ls -lcth | head -n20'

# alias lsld='ls -lcth | egrep "^d" | grep -v " 225_" | head -n20'

