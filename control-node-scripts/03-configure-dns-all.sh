#!/bin/bash

pdsh -a -X control mkdir -p /etc/systemd/resolved.conf.d
pdcp -a -X control /etc/systemd/resolved.conf.d/00-global.conf /etc/systemd/resolved.conf.d/00-global.conf 
pdsh -a -X control systemctl restart systemd-resolved
pdsh -a -X control systemctl enable systemd-resolved
pdsh -a -X control ln -fs /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
pdsh -a 'hostnamectl set-hostname %h'
pdcp -a /etc/hosts /etc/hosts
pdcp -a /etc/genders /etc/genders
