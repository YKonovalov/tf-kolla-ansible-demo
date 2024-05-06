#!/bin/sh
# Script takes two boolean args. 
# First indicates the need for ceph deployment
# Second says about using nfs as a backend for cinder backup

D=`dirname $0`

ID=`date +%Y%m%d%H%M`
ME=`basename $0`
os=$(grep -v "^#" /etc/genders |grep -o "os=[^,]\+,");os=${os##*=};os=${os%*,};
LOGD=~/"logs/$ID-$os"
mkdir -p "$LOGD"

cat > ~/current.env << EOF
export LOGD="$LOGD"
EOF

cleanup(){
 set -x
 tar cf "$LOGD/configs.tar" /opt/kayobe/src/kayobe-config "$D"
 exit
}
trap cleanup EXIT SIGINT SIGTERM SIGQUIT

S="
00-prereqs.sh
01-env.sh
02-configure-dns.sh
03-configure-dns-all.sh
04-configure.sh
05-installer.sh
06-control-host-bootstrap.sh
07-seed-host-configure.sh
08-overcloud-host.sh
09-sdn-venv.sh
10-sdn.sh
"
if echo "$1"|grep -q -i true; then
  S="$S ceph-install.sh"
fi
S="$S
11-overcloud-service-deploy.sh
13-resources-basic.sh
14-resources-demo.sh
"

if [ "$2" = "true" ]
then
  export USE_NFS_CINDER_BACKUP=true
fi

unset SSH_AUTH_SOCK

dolog(){
  cmd="bash "$D/$1" 2>&1 | tee "$LOGD/$(basename -s .sh "$1")$2.log""
  \time -f "%E %C (exit code: %x)" -a -o "$LOGD/time.log" sh -eo pipefail -c "$cmd"
}

for s in $S; do
 if ! dolog $s; then
   e=$?
   echo "ERROR: $s exits with error code: $e" >&2
   echo "Retrying one more time..."
   if ! dolog $s ".retry"; then
     e=$?
     echo "FATAL: $s exits with error code second time: $e" >&2
     exit $e
   fi
 fi
done

cat "$LOGD/time.log"
