#!/bin/sh

unset SSH_AUTH_SOCK

while true; do
  if source ~/kayobe.env; then
    break
  fi
  echo "waiting for ~/kayobe.env"
  sleep 5
done

source ~/current.env

echo "Waiting for $KOLLA_CONFIG_PATH/admin-openrc.sh"
echo "Please note it normally takes half an hour or more. At this stage you can safely stop terraform and run this command again later to see status of deploy."

while true; do
  if [ -f "$KOLLA_CONFIG_PATH/admin-openrc.sh" ]; then
    echo "All done"
    cat "$LOGD/time.log"
    echo "Next is a check for failed or unreachable ansible status (one unreachable in 05-seed-create.log is expected):"
    echo --------
    grep ok= "$LOGD"/[0-9]*.log|grep '\(unreachable\|failed\)=[1-9]'
    echo --------
    break
  elif ! pgrep -f 'control-node-scripts/cluster-do-setup.sh' >/dev/null; then
    echo "ERROR: script exited:"
    cat "$LOGD/time.log"
    grep ok= "$LOGD"/[0-9]*.log|grep '\(unreachable\|failed\)=[1-9]'
    exit 1
  else
    sleep 10
  fi
done
