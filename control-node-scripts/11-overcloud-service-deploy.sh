#!/bin/sh
set -e

source ~/kayobe.venv

echo "FIXME5: Stopping tungsten rabbit to free epmd (TCP:4369) port, otherwise kayobe will fail"
pdsh -g head docker stop config_database_rabbitmq_1

kayobe overcloud service deploy

echo "FIXME5: Starting tungsten rabbit that we stopped earlier"
pdsh -g head docker start config_database_rabbitmq_1
