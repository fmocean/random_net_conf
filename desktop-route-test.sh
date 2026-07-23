#!/usr/bin/env bash
set -e

# Add lab route toward rtr1
sudo ip route add 10.10.0.0/16 via 10.0.0.50

# Show resulting route
ip route | grep 10.10.0.0

# Basic reachability tests
ping -c3 10.10.10.10 || true
ping -c3 10.10.20.10 || true
ping -c3 10.10.30.10 || true
ping -c3 10.10.40.10 || true