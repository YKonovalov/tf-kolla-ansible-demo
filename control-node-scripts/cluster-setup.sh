#!/bin/sh
D=`dirname $0`

bash "$D/cluster-infra.sh" 2>&1 | tee /tmp/00-cluster-infra.log
tmux -vv set-option -g history-limit 15000 \; new-session -d -s setup
tmux send -t setup "bash $D/cluster-do-setup.sh $1 $2" ENTER
