#!/usr/bin/env bash

# This is intended to be run as root - user data scripts are run as such automatically

mkdir -p /data

USERNAME='${username}'
if [ "$USERNAME" != '${username}' ]; then
  USERNAME="$1"
fi

mkdir -p /data/rama/license
sudo chown -R "$USERNAME:$USERNAME" /data/

fallocate -l 10G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
echo 'vm.swappiness=0' | tee -a /etc/sysctl.conf
