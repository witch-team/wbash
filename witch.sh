#!/bin/bash

RSYNC='/usr/bin/rsync -avzP --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r --exclude=.git'
ERSYNC=
DEFAULT_HOST=athena
DEFAULT_WORKDIR=work
DEFAULT_QUEUE=poe_medium
DEFAULT_QUEUE_SHORT=poe_short
DEFAULT_NPROC=8
WAIT=TRUE

wdirname () {
    # Name of directory under DEFAULT_WORKDIR to use for upload
    BRANCH="$(git branch --show-current)"
    PWD="$(basename $(pwd))"
    DESTDIR=""
    [[ "$PWD" =~ .*${BRANCH} ]] && DESTDIR="${PWD}" || DESTDIR="${PWD}-${BRANCH}"
    DESTDIR=${DESTDIR%-master}
    echo "${DESTDIR}"
}


wup () {
    [ "$1" = '-h' ] && echo "Upload ./ to ${DEFAULT_HOST}:${DEFAULT_WORKDIR}/$(wdirname), excluding non-git files" && return 1
    TMPDIR="$(mktemp -d)"
    ERSYNC="${RSYNC} --exclude-from=$(git -C . ls-files --exclude-standard -oi > ${TMPDIR}/excludes; echo ${TMPDIR}/excludes) ${@} ./ ${DEFAULT_HOST}:${DEFAULT_WORKDIR}/$(wdirname)"
    echo "${ERSYNC}"
    ${ERSYNC}
    rm -r "${TMPDIR}"
}

wdown () {
    ${RSYNC} "${DEFAULT_HOST}:${DEFAULT_WORKDIR}/$(wdirname)/$1" ./
}

wsub () {
    END_ARGS=FALSE
    QUEUE=${DEFAULT_QUEUE}
    NPROC=${DEFAULT_NPROC}
    JOB_NAME=""
    BSUB_INTERACTIVE=""
    CALIB=""
    DEBUG=""
    RESDIR_CALIB=""
    USE_CALIB=""
    START=""
    STARTBOOST=""
    BAU=""
    FIX=""
    DEST="${DEFAULT_HOST}:${DEFAULT_WORKDIR}/$(wdirname)"
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
                STARTBOOST=TRUE
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
                DEBUG=TRUE
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
    [ -z "$JOB_NAME" ] && echo "Usage: wsub -j job-name [...]" && return 1
    [ -n "$CALIB" ] && EXTRA_ARGS="${EXTRA_ARGS} --calibration=1"
    [ -n "$RESDIR_CALIB" ] && EXTRA_ARGS="${EXTRA_ARGS} --write_tfp_file=resdir --calibgdxout=${JOB_NAME}/data_calib_${JOB_NAME}"
    if [ -n "$USE_CALIB" ]; then
        EXTRA_ARGS="${EXTRA_ARGS} --calibgdxout=${USE_CALIB}/data_calib_${USE_CALIB} --tfpgdx=${USE_CALIB}/data_tfp_${USE_CALIB}"
        [ -z "$BAU" ] && BAU="${USE_CALIB}/results_${USE_CALIB}.gdx"
        [ -z "$START" ] && START="${USE_CALIB}/results_${USE_CALIB}.gdx"
    fi
    if [ -n "$START" ]; then
        wssh test -f "$START"
        if [ ! $? -eq 0 ]; then
            if [ -f $START ]; then
                ${RSYNC} $START $(basename $START)
                START=$(basename $START)
                ${RSYNC} $START ${DEST}/
            else
                START="${START}/results_${START}.gdx"
            fi
        fi
        EXTRA_ARGS="${EXTRA_ARGS} --startgdx=${START}"
        [ -z "$BAU" ] && BAU="${START}"
        [ -n "$CALIB" ] && EXTRA_ARGS="${EXTRA_ARGS} --tfpgdx=${START}"
    fi
    if [ -n "$BAU" ]; then
        wssh test -f "$BAU"
        if [ ! $? -eq 0 ]; then
            if [ -f $BAU ]; then
                ${RSYNC} $BAU $(basename $BAU)
                BAU=$(basename $BAU)
                ${RSYNC} $BAU ${DEST}/
            else
                BAU="${BAU}/results_${BAU}.gdx"
            fi
        fi
        EXTRA_ARGS="${EXTRA_ARGS} --baugdx=${BAU}"
    fi
    if [ -n "$FIX" ]; then
        wssh test -f "$FIX"
        if [ ! $? -eq 0 ]; then
            if [ -f $FIX ]; then
                ${RSYNC} $FIX $(basename $FIX)
                FIX=$(basename $FIX)
                ${RSYNC} $FIX ${DEST}/
            else            
                FIX="${FIX}/results_${FIX}.gdx"
            fi
        fi
        EXTRA_ARGS="${EXTRA_ARGS} --gdxfix=${FIX}"
    fi
    [ -n "$DEBUG" ] && EXTRA_ARGS="${EXTRA_ARGS} --max_iter=1 --rerun=0 --only_solve=c_usa --parallel=false --holdfixed=0"
    [ -n "$STARTBOOST" ] && EXTRA_ARGS="${EXTRA_ARGS} --startboost=1"
    wup
    BSUB=bsub
    [ -n "$BSUB_INTERACTIVE" ] && BSUB="bsub -I"
    echo ssh ${DEFAULT_HOST} "cd ${DEFAULT_WORKDIR}/$(wdirname) && rm -rfv ${JOB_NAME} 225_${JOB_NAME} && mkdir -p ${JOB_NAME} 225_${JOB_NAME} && $BSUB -J ${JOB_NAME} -R span[hosts=1] -sla SC_gams -n $NPROC -q $QUEUE -o ${JOB_NAME}/${JOB_NAME}.out -e ${JOB_NAME}/${JOB_NAME}.err \"gams run_witch.gms ps=9999 pw=32767 gdxcompress=1 Output=${JOB_NAME}/${JOB_NAME}.lst Procdir=225_${JOB_NAME} --nameout=${JOB_NAME} --resdir=${JOB_NAME}/ --gdxout=results_${JOB_NAME} ${EXTRA_ARGS} ${@}\""
    ssh ${DEFAULT_HOST} "cd ${DEFAULT_WORKDIR}/$(wdirname) && rm -rfv ${JOB_NAME} 225_${JOB_NAME} && mkdir -p ${JOB_NAME} 225_${JOB_NAME} && $BSUB -J ${JOB_NAME} -R span[hosts=1] -sla SC_gams -n $NPROC -q $QUEUE -o ${JOB_NAME}/${JOB_NAME}.out -e ${JOB_NAME}/${JOB_NAME}.err \"gams run_witch.gms ps=9999 pw=32767 gdxcompress=1 Output=${JOB_NAME}/${JOB_NAME}.lst Procdir=225_${JOB_NAME} --nameout=${JOB_NAME} --resdir=${JOB_NAME}/ --gdxout=results_${JOB_NAME} ${EXTRA_ARGS} ${@}\""
    [ -n "$BSUB_INTERACTIVE" ] && wdown ${JOB_NAME}
}

wdata () {
    END_ARGS=FALSE
    QUEUE=${DEFAULT_QUEUE_SHORT}
    BSUB_INTERACTIVE=""
    REG_SETUP="witch17"
    while [ $END_ARGS = FALSE ]; do
        key="$1"
        case $key in
            # BSUB
            -r|-regions)
                REG_SETUP="$2"
                shift
                shift
                ;;
            -i|-interactive)
                BSUB_INTERACTIVE=TRUE
                shift
                ;;
            *)
                END_ARGS=TRUE
                ;;
        esac
    done
    JOB_NAME="data_${REG_SETUP}"
    wup
    cd ../witch-data && git pull && wup && cd -
    cd ../witchtools && git pull && wup && cd -
    BSUB=bsub
    [ -n "$BSUB_INTERACTIVE" ] && BSUB="bsub -I -tty"
    ssh ${DEFAULT_HOST} "cd ${DEFAULT_WORKDIR}/$(wdirname) && rm -rfv ${JOB_NAME}/${JOB_NAME}.{err,out} && mkdir -p ${JOB_NAME} && $BSUB -J ${JOB_NAME} -R span[hosts=1] -sla SC_gams -n 1 -q $QUEUE -o ${JOB_NAME}/${JOB_NAME}.out -e ${JOB_NAME}/${JOB_NAME}.err \"Rscript --vanilla input/translate_witch_data.R -n ${REG_SETUP} ${@}\""
    [ -n "$BSUB_INTERACTIVE" ] && wdown ${JOB_NAME}
}


wssh () {
   ssh ${DEFAULT_HOST} "cd ${DEFAULT_WORKDIR}/$(wdirname) && $@"
}

wcheck () {
    JOB_NAME="$1"
    if [ -z "$JOB_NAME" ]; then
        ssh ${DEFAULT_HOST} bjobs -w
    else
        ssh ${DEFAULT_HOST} "cd ${DEFAULT_WORKDIR}/$(wdirname) && bpeek -f -J ${JOB_NAME}"
    fi
}

werr () {
    JOB_NAME="$1"
    if [ -z "$JOB_NAME" ]; then
        ssh ${DEFAULT_HOST} bjobs -w
    else
        ssh ${DEFAULT_HOST} "cd ${DEFAULT_WORKDIR}/$(wdirname) && cat ${JOB_NAME}/errors_${JOB_NAME}.txt"
    fi
}

    
#     [ $# -lt 3 ] && echo 'Usage: wsub [job-name] [ncpu]exit 1
#     mkdir -p ${JOB_NAME}
#     bsub -J ${JOB_NAME} -I -R span[hosts=1] -sla SC_gams -n $(3) -q poe_medium -o ${JOB_NAME}/${JOB_NAME}.out -e ${JOB_NAME}/${JOB_NAME}.err '$(2)'

# wrun-contained ()
# {
# RUN=$1
# NPROC=$2
# wrun_general serial_24h ${RUN} ${NPROC} ${@:3}
# }

# WITCH_CMD = rm -rfv ${JOB_NAME} 225_${JOB_NAME} && mkdir -p ${JOB_NAME} 225_${JOB_NAME} && gams run_witch.gms ps=9999 pw=32767 gdxcompress=1 Output=${JOB_NAME}/${JOB_NAME}.lst Procdir=225_${JOB_NAME} --nameout=${JOB_NAME} --resdir=${JOB_NAME}/ --gdxout=results_${JOB_NAME} $(2) && cat ${JOB_NAME}/errors_${JOB_NAME}.txt
# WCALIB = --calibration=1 --write_tfp_file=resdir --calibgdxout=${JOB_NAME}/tfp_${JOB_NAME}
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




wdump ()
{
WHAT=$1
shift
while [ "$1" != "" ]; do
    for f in ${1}/all_data_temp*gdx; do
        echo -e "\n\e[33m${f}:\e[0m" 1>&2 
        gdxdump $f symb=${WHAT}
    done
    shift
done
}

wtemp ()
{
workdir="$1"
ngdx="$2"
match="$3"
for f in ${workdir}/all_data_temp_${match}*; do
fbase=$(basename ${f}); fnameext=${fbase:14}; fname=temp_${fnameext%.gdx}
until rsync ${f} ${fname}_1.gdx; do sleep 1; done
ahash=$(md5sum ${fname}_1.gdx | cut -d' ' -f1)
echo "${f} -> ${fname}_1.gdx (${ahash})"
tail -n1 ${workdir}/errors_${match}*
bhash=$ahash
for i in $(seq 2 $ngdx); do
while [ "$ahash" == "$bhash" ]; do sleep 4;bhash=$(md5sum ${f} | cut -d' ' -f1); done
until rsync ${f} ${fname}_${i}.gdx; do sleep 1; done
echo "${f} -> ${fname}_${i}.gdx (${bhash})"; tail -n1 ${workdir}/errors_${match}*
ahash="${bhash}"
done
done
}

wclean ()
{
rm -rv 225*
rm -v */*{lst,out,err}
}

wcleandir ()
{
SCENDIR=$1
PROCDIR=225_${SCENDIR}
if [ -d ${PROCDIR} ]; then
rm -rf ${PROCDIR}/*
else
mkdir -p ${PROCDIR}
fi
if [ -d ${SCENDIR} ]; then
rm ${SCENDIR}/{*lst,job*{out,err}}
else
mkdir -p ${SCENDIR}
fi
}

wrun_general ()
{
QUEUE=$1
RUN=$2
NPROC=$3
wcleandir ${RUN}
mkdir -p ${RUN} 225_${RUN}
EXTRA_ARGS=""
PREV_CONV="$(gdxdump ${RUN}/results_${RUN}.gdx symb=stop_nash format=csv | tail -n1 | sed 's/[[:space:]]//g')"
if [[ $PREV_CONV =~ ^1$ ]]; then
[[ ! ${@:4} =~ startgdx ]] && EXTRA_ARGS="$EXTRA_ARGS --startgdx=${RUN}/results_${RUN} --calibgdx=${RUN}/results_${RUN} --tfpgdx=${RUN}/results_${RUN}"
[[ ! ${@:4} =~ startgdx ]] && [[ ! ${@:4} =~ gdxfix ]] && EXTRA_ARGS="$EXTRA_ARGS --startboost=1"
[[ ! ${@:4} =~ baugdx ]] && [[ ${RUN} =~ bau ]] && EXTRA_ARGS="$EXTRA_ARGS --baugdx=${RUN}/results_${RUN}"
fi
[ -z "$EXTRA_ARGS" ] || echo "AUTO EXTRA ARGS: $EXTRA_ARGS"
bsub -n${NPROC} -J "$RUN" -R "span[hosts=1]" -q ${QUEUE} -o ${RUN}/job_${RUN}.out -e ${RUN}/job_${RUN}.err gams call_default.gms pw=32767 gdxcompress=1 Output="${RUN}/${RUN}.lst" Procdir=225_${RUN} --nameout="${RUN}" --resdir=$RUN/ --gdxout=results_${RUN} --gdxout_report=report_${RUN} --gdxout_start=start_${RUN} --verbose=1 --parallel=incore ${EXTRA_ARGS} ${@:4}
}


wrun6 ()
{
RUN=$1
NPROC=$2
wrun_general serial_6h ${RUN} ${NPROC} ${@:3}
}

wbrun ()
{
RUN=$1
NPROC=$2
BASEGDX=$3
wrun ${RUN} ${NPROC} --startgdx=${BASEGDX} --baugdx=${BASEGDX} --calibgdx=${BASEGDX} --tfpgdx=${BASEGDX} --startboost=1 ${@:4}
}      

wbrun6 ()
{
RUN=$1
NPROC=$2
BASEGDX=$3
wrun6 ${RUN} ${NPROC} --startgdx=${BASEGDX} --baugdx=${BASEGDX} --calibgdx=${BASEGDX} --tfpgdx=${BASEGDX} --startboost=1 ${@:4}
}      

wcrun ()
{
RUN=$1
NPROC=$2
BASEGDX=$3
wbrun ${RUN} ${NPROC} ${BASEGDX} --calibration=1 ${@:4}
}      

wfrun ()
{
RUN=$1
NPROC=$2
BASEGDX=$3
wbrun ${RUN} ${NPROC} ${BASEGDX} --gdxfix=${BASEGDX} ${@:4}
}      

wtax ()
{
RUN=$1
NPROC=$2
BASEGDX=$3
TAXSTARTPERIOD=$4
TAXSTARTVAL=$5
TAXGROWTHRATE=$6
TFIX=$(expr ${TAXSTARTPERIOD} - 1)
echo "Carbon tax starting in period ${TAXSTARTPERIOD} at ${TAXSTARTVAL} USD2005/tCO2 and growing at ${TAXGROWTHRATE} rate"
wfrun ${RUN} ${NPROC} ${BASEGDX} --tfix=${TFIX} --policy=ctax --tax_start=${TAXSTARTPERIOD} --ctax2015=${TAXSTARTVAL} --ctaxgrowth=${TAXGROWTHRATE} ${@:7}
}      

wfind ()
{
grep -i "$1" *.gms */*.gms
}

gdiff ()
{
    type dwdiff &>nul 2>&1;
    if [ $? -eq 0 ]; then
        CMD=dwdiff;
    else
        if [ ! -f dwdiff ]; then
            echo 'WARN: dwdiff tool not found... downloading'
            curl http://os.ghalkes.nl/dist/dwdiff-2.1.0.tar.bz2 > dwdiff-2.1.0.tar.bz2
            tar xjf dwdiff-2.1.0.tar.bz2 
            cd dwdiff-2.1.0
            ./configure
            make all
            mv dwdiff ../
            cd ..
            rm -rf dwdiff-2.1.0.tar.bz2 dwdiff-2.1.0
            CMD=./dwdiff;
        fi
    fi;
    SYMB=$1;
    MATCHES=$2
    DMPLIST=(one two);
    IGDX=0;
    AWKPARAM="/\"$(sed 's|,|[a-z]*"/ \&\& /"|g' <<<"${MATCHES}")[a-z]*\"/"
    for GDX in ${@:3};
    do
        echo $GDX;
        DMP=${GDX%.gdx}zzz.txt;
        rm -fv "$DMP"
        gdxdump $GDX symb=$SYMB format=csv | awk "$AWKPARAM" | sed 's/","/ /g;s/"//g;s/,/ /;' > "$DMP"
        DMPLIST[IGDX]=$DMP;
        let IGDX=IGDX+1;
    done;
    $CMD -c -L -d' ,.' ${DMPLIST[@]}
}

alias bw='bjobs -w'

alias bwg='bjobs -w | egrep -i'

alias bag='bjobs -aw | grep -i'

alias bal='bjobs -aw | tail'

alias bl='bjobs -l'

alias blj='bjobs -l -J'

alias bf='bpeek -f'

alias bfj='bpeek -f -J'

alias bq='bqueues | egrep "(QUEUE_NAME|serial|gams)"'

alias bk='bkill'

alias bkj='bkill -J'

alias lsl='ls -lcth | head -n20'

alias lsld='ls -lcth | egrep "^d" | grep -v " 225_" | head -n20'
