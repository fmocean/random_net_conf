#!/usr/bin/env bash

EC2_IP="10x.5x.1x1.1x4"
KEY="$HOME/.ssh/EC2_1.pem"

chmod 400 "$KEY"
ssh -i "$KEY" ec2-user@"$EC2_IP"