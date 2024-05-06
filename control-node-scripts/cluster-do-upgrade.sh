#!/bin/sh

D=`dirname $0`
ID=`date +%Y%m%d%H%M`
ME=`basename $0`
LOGD="$ME-$ID"
mkdir -p "$LOGD"

os=
newos=

if [ -f ~/kayobe.env ]; then
  os="$(nodeattr -v $chost os)"
  os="${os:-wallaby}"
  case "$os" in
  ussuri)
    newos=victoria
    ;;
  victoria)
    newos=wallaby
    ;;
  *)
    echo "Do not know how to upgrae $os"
    exit 2
    ;;
  esac
  sed -i "s/os=$os/os=$newos/" /etc/genders
  tar cf $os.logs.tar /root/*.log /tmp/tlog
  (. ~/kayobe.env; rm -rf "$SRC" "$VENVS")
else
  echo "No previous version found"
  exit 1
fi

S="
01-env.sh
02-configure.sh
03-installer.sh
04-control-host-bootstrap.sh
05-seed-host-configure.sh
06-overcloud-host.sh
07-tf.sh
09-overcloud-service-upgrade.sh
"

#
# kayobe control host upgrade
# kayobe seed host package update --packages "*"
# kayobe seed host upgrade
# kayobe overcloud host package update --packages "*"
# kayobe overcloud host upgrade
# kayobe overcloud service configuration save
# kayobe overcloud service upgrade
#

unset SSH_AUTH_SOCK

dolog(){
  cmd="bash "$D/$1" 2>&1 | tee "$LOGD/$(basename -s .sh "$1").$newos$2.log""
  \time -f "%E %C (exit code: %x)" -a -o /tmp/tlog sh -eo pipefail -c "$cmd"
}

mv /tmp/tlog /tmp/tlog.$os || rm -f /tmp/tlog
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

cat /tmp/tlog
