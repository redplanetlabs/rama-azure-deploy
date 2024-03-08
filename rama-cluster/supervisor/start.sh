#!/usr/bin/env bash

sudo cp rama.yaml /data/rama/rama.yaml

cat <<EOF >> /data/rama/rama.yaml

supervisor.host:
  "${private_ip}"
EOF

sudo cp supervisor.service /etc/systemd/system
sudo systemctl enable supervisor.service
sudo systemctl start supervisor.service
