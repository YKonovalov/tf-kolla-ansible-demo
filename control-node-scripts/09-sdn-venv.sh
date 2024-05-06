#!/bin/sh
set -e

. ~/kayobe.venv

REQS="'ansible>=2.9.0,<3.0' 'oslo.config>=5.2.0' 'PyYAML>=3.12'"

. /etc/os-release
case $ID in
  ubuntu)
    venv="virtualenv -v -p python3 --clear --system-site-packages"
    if [ "$os" == "2023.2" -a "$VERSION_ID" == "20.04" ]; then
      apt-get -y install python3.9{,-dev,-minimal,-venv}
      venv="virtualenv -v -p python3.9 --clear --system-site-packages" # 2023.2 kayobe req
    fi
    
    ;;
  centos)
    venv="virtualenv -v -p python3 --clear --system-site-packages" # victoria
    REQS="$REQS docker-compose"
    ;;
  *)
    ;;
esac
pdsh -a "$venv $TF_VENV_PATH && $TF_VENV_PATH/bin/pip install --no-color $REQS"
