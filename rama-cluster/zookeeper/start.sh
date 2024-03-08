##!/bin/bash

echo "Starting zookeeper..." >> setup.log

sudo cp zookeeper.service /etc/systemd/system >> setup.log 2>&1;
sudo systemctl start zookeeper.service >> setup.log 2>&1;
sudo systemctl enable zookeeper.service >> setup.log 2>&1;