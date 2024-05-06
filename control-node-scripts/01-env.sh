#!/bin/sh

ID=`date +%Y%m%d%H%M`
os=$(grep -v "^#" /etc/genders |grep -o "os=[^,]\+,");os=${os##*=};os=${os%*,};
LOGD=~/"logs/$ID-$os"
mkdir -p "$LOGD"

rm -f ~/kayobe.{,v}env

cat > ~/kayobe.env << \EOF
SRC=/opt/kayobe/src
VENVS=/opt/kayobe/venvs

export KAYOBE_CONFIG_ROOT=$SRC/kayobe-config
ETC="$KAYOBE_CONFIG_ROOT/etc"

export KAYOBE_CONFIG_PATH="$ETC/kayobe"
export KAYOBE_SOURCE_PATH="$SRC/kayobe"
export KAYOBE_VENV_PATH="$VENVS/kayobe"

export KOLLA_CONFIG_PATH="$ETC/kolla"
export KOLLA_SOURCE_PATH="$SRC/kolla-ansible"
export KOLLA_VENV_PATH="$VENVS/kolla-ansible"

export TF_CONFIG_PATH="$ETC/opensdn/opensdn.yml"
export TF_SOURCE_PATH="$SRC/tf-ansible-deployer"
export TF_VENV_PATH="$VENVS/tf-ansible-deployer"
EOF
cat >> ~/kayobe.env << EOF
export LOGD="$LOGD"
EOF

cat > ~/kayobe.venv << \EOF
source ~/kayobe.env
echo "Using Kayobe config from $KAYOBE_CONFIG_ROOT"
source "$KAYOBE_VENV_PATH/bin/activate"
EOF
