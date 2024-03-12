#!/usr/bin/env bash

# Unpacks ~/rama.zip into the /data/rama directory

sudo mv /home/${username}/license.yaml /data/rama/license
sudo mv /home/${username}/rama.yaml /data/rama
sudo mv /home/${username}/rama.zip /data/rama
cd /data/rama

sudo unzip -n rama.zip

# Get the rama.zip into the jar directory so supervisors can download it
local_dir=$(grep "local.dir" rama.yaml | cut -d ":" -f2 | xargs)

sudo mkdir -p "$local_dir/conductor/jars"
sudo cp rama.zip "$local_dir/conductor/jars"
