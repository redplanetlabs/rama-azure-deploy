#!/usr/bin/env bash

sudo cp conductor.service /etc/systemd/system
sudo systemctl enable conductor.service
sudo systemctl start conductor.service
