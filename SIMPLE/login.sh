#!/bin/bash

# ssh -p 47054 root@76.66.207.49 -L 8080:localhost:8080

INSTANCE_IP=${1:-"76.66.207.49"}
INSTANCE_PORT=${2:-"47054"}
