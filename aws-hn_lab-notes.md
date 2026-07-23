# AWS HN_LAB VPC Notes

## VPC

- Name: HN_LAB
- VPC ID: vpc-0aaf0ca5e0fda7938
- CIDR: 10.50.0.0/16
- Region: us-east-1

## Subnets

- public: 10.50.1.0/24 (us-east-1b)
- private: 10.50.10.0/24
- private_mgmt: (created in HN_LAB)

## Route table

- ID: rtb-09ae00a14efdc8ad5
- 10.50.0.0/16 -> local
- 0.0.0.0/0   -> igw-005c927b623f8366f

## Internet Gateway

- ID: igw-005c927b623f8366f
- Attached to VPC HN_LAB

## EC2 jump host

- Name: EC2_lab
- AMI: Amazon Linux 2023
- Public IP: 1x0.xx.1x1.1xx
- Private IP: 10.50.1.154/24
- SSH user: ec2-user
- Key: EC2_1.pem