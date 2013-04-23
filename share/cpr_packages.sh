#!/bin/sh
#fix error:"ln: /usr/local/bin/autoconf: File exists"
export LN='/bin/ln -f'

set -o errexit

export PKG_SUFX=txz
export PACKAGES=/packages

export BATCH=yes
export DISABLE_VULNERABILITIES=yes

export PATH="/usr/lib/distcc/bin:$PATH"
#export CCACHE_PREFIX="/usr/local/bin/distcc"
export CCACHE_PATH="/usr/bin:/usr/local/bin"
export PATH="/usr/local/libexec/ccache:$PATH:/usr/local/bin:/usr/local/sbin"


LOGFILE="/tmp/packages.log"
BUILDLOG="/tmp/build.log"

# fatal error for interactive session.
err()
{
    exitval=$1
    shift
    echo "$*" 1>&2
    echo "$*" >> ${LOGFILE}
    exit $exitval
}

truncate -s0 ${LOGFILE} ${BUILDLOG} 
rm -f /tmp/port_log* > /dev/null 2>&1 ||true
#determine how we have free ccachefs 
#CCACHE_SIZE=`df -m /root/.ccache | tail -n1 |awk '{print $2}'`
#[ -z "${CCACHE_SIZE}" ] && CCACHE_SIZE="4096"
#/usr/local/bin/ccache -M ${CCACHE_SIZE}m >>${LOGFILE} 2>&1|| err 1 "Cannot set ccache size"

find /usr/ports -type d -name work -exec rm -rf {} \; || true

PORT_DIRS=`cat /tmp/ports_list.txt`

mkdir -p ${PACKAGES}/All >>${LOGFILE} 2>&1|| err 1 "Cannot create PACKAGES/All directory!"

PROGRESS=`wc -l /tmp/ports_list.txt |awk '{printf $1"\n"'}`

set +o errexit
# config recursive while 
for dir in $PORT_DIRS; do
    pkg info -e `make -C ${dir} -V PKGNAME` && continue
    #this is hack for determine that we have no options anymore - script dup stdout then we can grep for Dialog-Ascii-specific symbol
    NOCONF=0
    while [ $NOCONF -eq 0 ]; do
	echo -e "\033[40;35m Do config-recursive while not set for all options \033[0m"
	script -q /tmp/test.$$ make config-recursive -C ${dir} || break
	grep "\[" /tmp/test.$$
    [ $? -eq 1 ] && NOCONF=1
    done
done
rm -f /tmp/test.$$

set -o errexit
for dir in $PORT_DIRS; do
    PROGRESS=$((PROGRESS - 1))
    echo -e "\033[40;35m Working on ${dir}. ${PROGRESS} ports left. \033[0m"
    # skip if ports already registered

    if [ -f /tmp/buildcontinue ]; then
	cd /tmp/packages 
	PORTNAME=`make -C ${dir} -V PKGNAME`
	pkg info -e ${PORTNAME} >/dev/null 2>&1 || {
	    [ -f "./${PORTNAME}.txz" ] && env ASSUME_ALWAYS_YES=yes pkg add ./${PORTNAME}.txz && echo -e "\033[40;35m ${PORTNAME} found and added from cache. \033[0m"
	}
    fi

    pkg info -e `make -C ${dir} -V PKGNAME` && continue

    yes |portmaster -CK --no-confirm -y -H ${dir} 2>&1|tee >>${BUILDLOG} 
done

pkg2ng >>${LOGFILE} 2>&1|| err 1 "Cannot pkg2ng ports"

echo -e "\033[40;35m Creating packages... \033[0m"

for i in `pkg info -oa | cut -d : -f1`; do 
	pkg create -n -g -f txz -o ${PACKAGES}/All/ $i |tee >>${LOGFILE}
done

cd ${PACKAGES} || err 1 "Cannot change directory"
####pkg repo ${PACKAGES}/ /tmp/id_rsa
pkg repo ${PACKAGES}/ >>${LOGFILE} 2>&1|| err 1 "Cannot create packages repo archive"