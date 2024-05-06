#!/bin/bash

mkdir -p /etc/systemd/resolved.conf.d

cat >/etc/systemd/resolved.conf.d/00-global.conf << EOF
[Resolve]
DNS=77.88.8.8
#DNS=1.1.1.1
LLMNR=no
MulticastDNS=no
DNSSEC=no
DNSOverTLS=no
EOF

systemctl restart systemd-resolved
ln -fs /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

resolvectl domain
resolvectl dns
