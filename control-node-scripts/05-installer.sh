#!/bin/sh

. ~/kayobe.env

chost="$(nodeattr -n control|head -1)"
os="$(nodeattr -v $chost os)"
tf="$(nodeattr -v $chost tf)"
virt="$(nodeattr -v $chost virt)"

os="${os:-ussuri}"
tf="${tf:-dev}"
virt="${virt:-kvm}"

. /etc/os-release
case $ID in
  ubuntu)
    pdsh -a 'apt -y install git python3-virtualenv python3-docker python3-dev libffi-dev gcc libssl-dev time jq mc ca-certificates'
    venv="virtualenv -v -p python3 --clear --system-site-packages"
    # wallaby 2004 apt-get remove ansible
    # pdsh -a 'apt-get -y remove python3-openssl ; apt -y autoremove' #zed
    if [ "$os" == "2023.2" -a "$VERSION_ID" == "20.04" ]; then
      apt-get -y install python3.9{,-dev,-minimal,-venv}
      venv="virtualenv -v -p python3.9 --clear --system-site-packages" # 2023.2 kayobe req
    fi
    ;;
  centos)
    dnf -y install git python3-virtualenv python3-devel libffi-devel gcc openssl-devel python3-libselinux python3-dnf time jq
    dnf -y install centos-release-openstack-yoga
    dnf -y install python3-openstackclient python3-heatclient
    venv=virtualenv-3
    venv="virtualenv -v -p python3 --clear --system-site-packages" # victoria

    export PDSH_SSH_ARGS_APPEND='-o StrictHostKeyChecking=no'
    pdsh -a 'dnf -y install lsof jq python3-virtualenv python3-dnf'
    pdsh -a 'dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo'
    pdsh -a 'dnf -y install docker-ce python3-docker docker-compose-plugin'
    # TF on centos-stream needs compatible kernel
    pdsh -g compute 'dnf -y install  https://vault.centos.org/8.2.2004/BaseOS/x86_64/os/Packages/kernel{,-core,-modules,-tools,-tools-libs}-4.18.0-193.28.1.el8_2.x86_64.rpm'
    pdsh -g compute 'a=`dnf repoquery --installonly --latest-limit=1 -q|grep -v 193.28.1.el8_2`; if [ -n "$a" ]; then rpm -evh $a; fi'
    ;;
  *)
    ;;
esac

echo
echo "     venv: $venv"
echo "openstack: $os"
echo "distrover: $VERSION_ID"
echo 

cd
mkdir -p $SRC ||:

[ -d "$KAYOBE_SOURCE_PATH" ] ||
  git clone https://github.com/openstack/kayobe.git -b stable/$os "$KAYOBE_SOURCE_PATH" ||
  git clone https://github.com/openstack/kayobe.git -b ${os}-eol "$KAYOBE_SOURCE_PATH" ||
  git clone https://github.com/openstack/kayobe.git -b unmaintained/${os} "$KAYOBE_SOURCE_PATH"


[ -d "$TF_SOURCE_PATH" ] ||
  git clone https://github.com/tungstenfabric/tf-ansible-deployer.git -b master "$TF_SOURCE_PATH"


[ -d "$KAYOBE_VENV_PATH" ] || (
$venv "$KAYOBE_VENV_PATH"
source "$KAYOBE_VENV_PATH/bin/activate"
 pip install -U pip
 pip install "$KAYOBE_SOURCE_PATH"
deactivate
)
$venv "$KOLLA_VENV_PATH"
