# VMware Net Lab – VyOS Segmentation, Internal Routing, and AWS Hybrid Extension

This lab builds a segmented on-prem VMware environment with **VyOS** open-source routers, routed internal networks, a management desktop, multiple role-based VMs, and a new AWS VPC extension for hybrid networking. The focus is VLAN trunking, inter-VLAN routing, persistent management access, public cloud validation, and preparing for a Site-to-Site VPN between on-prem and AWS.

---

## Big picture

- Ubuntu desktop is the main **management** and **attack** workstation.
- `rtr1` and `rtr2` are **VyOS** routers providing internal routing between isolated lab networks.
- Internal segments represent different roles instead of a single flat LAN.
- VMware virtual networking carries all the lab VLANs and connects routers to VMs.
- The desktop keeps normal internet via DHCP and can also reach all lab subnets through a single static route.
- AWS extends the lab with a dedicated VPC, separate public/private cloud subnets, and a public EC2 jump host for cloud-side validation.
- End goal: connect the VMware/VyOS environment to AWS through a hybrid VPN design.

---

## What this lab simulates

- A small enterprise network with separate:
  - Management, server, security, and attacker zones.
- Router-on-a-stick / inter-VLAN routing inside a virtual environment.
- A management workstation **outside** the routed segments that still needs controlled access into the lab.
- A cloud extension with public and private AWS subnets.
- Real troubleshooting around:
  - Trunks, VLAN tags, default gateways, static routes, Netplan persistence, route tables, Internet Gateways, EC2 access, and hybrid routing design.

---

## Core technologies

- VMware vSwitch / port groups for internal connectivity.
- VyOS open-source virtual routers (`rtr1`, `rtr2`).
- VLAN segmentation and trunk delivery to a routing device.
- Inter-VLAN routing on VyOS.
- Ubuntu Netplan for persistent static routes.
- AWS VPC, subnets, route tables, and Internet Gateway.
- Amazon EC2 for public jump-host validation.
- Linux tools: `ip route`, `ip a`, `ping`, `ssh`, `traceroute`, `curl`.

---

## On-prem lab networks

| Role      | Subnet        | Example host |
|----------|---------------|--------------|
| Management | 10.10.10.0/24 | 10.10.10.10 |
| Server     | 10.10.20.0/24 | 10.10.20.10 |
| Security   | 10.10.30.0/24 | 10.10.30.10 |
| Attacker   | 10.10.40.0/24 | 10.10.40.10 |

---

## AWS lab networks

| Role                     | Subnet / CIDR | Notes                      |
|--------------------------|---------------|----------------------------|
| VPC                      | 10.50.0.0/16  | AWS VPC `HN_LAB`           |
| Public subnet            | 10.50.1.0/24  | EC2 jump host              |
| Private subnet           | 10.50.10.0/24 | Internal AWS workloads     |
| Private management subnet| (created)     | Internal-only admin use    |

---

## Topology (high level)

```text
Ubuntu Desktop
      |
      | static route: 10.10.0.0/16 via 10.0.0.50
      |
    rtr1 (VyOS)
      |
    rtr2 (VyOS)
      |
+------+------+----------+----------+
| mgmt | server | security | attacker |
|10.10.10|10.10.20|10.10.30|10.10.40|
+--------+--------+---------+--------+

                     || future Site-to-Site VPN ||

                 AWS VPC: HN_LAB (10.50.0.0/16)
                        |
         +--------------+---------------+
         |                              |
   public subnet                    private subnets
   10.50.1.0/24                 10.50.10.0/24 + private_mgmt
         |
   EC2 jump host
```

---

## Installation & build steps

### 1. Create the VMware VMs

Create these VMs in VMware:

- Ubuntu Desktop (management / attacker box)
- `rtr1` (VyOS)
- `rtr2` (VyOS)
- Management VM
- Server VM
- Security VM
- Attacker VM

Attach NICs so:

- `rtr1` / `rtr2` see all required internal networks (or a VLAN trunk).
- Each endpoint VM sits in the correct subnet (mgmt, server, security, attacker).

---

### 2. Install VyOS on `rtr1` and `rtr2`

1. Create the router VM and mount the VyOS ISO.
2. Boot into the VyOS live environment.
3. At the console run:

```bash
install image
```

Follow the prompts (auto partition, select disk, set `vyos` password, install bootloader), then:

4. Detach the ISO.
5. Reboot the VM so it boots from the installed image.

Repeat for both `rtr1` and `rtr2`.

---

### 3. Basic VyOS configuration

VyOS uses a commit-style workflow:

```bash
configure
set system host-name rtr1
commit
save
exit
```

Example interface config on a router:

```bash
configure
set interfaces ethernet eth0 address '10.0.0.50/24'
set interfaces ethernet eth0 description 'Desktop side'
set interfaces ethernet eth1 address '10.10.10.1/24'
set interfaces ethernet eth1 description 'Management subnet'
set interfaces ethernet eth2 address '10.10.20.1/24'
set interfaces ethernet eth2 description 'Server subnet'
# add more interfaces/subnets as needed
commit
save
exit
```

Useful VyOS show commands:

```bash
show interfaces
show ip route
show configuration commands
```

---

### 4. Base Ubuntu setup (desktop + VMs)

On each Ubuntu system:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y net-tools iproute2 openssh-server curl wget vim traceroute
```

Verify interfaces and routing:

```bash
ip a
ip route
nmcli device status
```

---

### 5. Temporary static route on desktop

Prove reachability from the desktop into the lab:

```bash
sudo ip route add 10.10.0.0/16 via 10.0.0.50
ip route | grep 10.10.0.0

ping -c3 10.10.10.10
ping -c3 10.10.20.10
ping -c3 10.10.30.10
ping -c3 10.10.40.10
```

This works until reboot; next step makes it permanent.

---

### 6. Make the route persistent with Netplan

Check existing Netplan files:

```bash
sudo cat /etc/netplan/01-network-manager-all.yaml
sudo cat /etc/netplan/50-cloud-init.yaml
```

Edit the file that defines your desktop NIC (example `enp7s0`):

```yaml
network:
  version: 2
  ethernets:
    enp7s0:
      dhcp4: true
      routes:
        - to: 10.10.0.0/16
          via: 10.0.0.50
```

Apply and verify:

```bash
sudo netplan apply
ip route | grep 10.10.0.0
```

Expected:

```text
10.10.0.0/16 via 10.0.0.50 dev enp7s0 proto static metric 100
```

If you see a permissions warning for a Netplan file:

```bash
sudo chmod 600 /etc/netplan/01-network-manager-all.yaml
sudo netplan apply
```

---

## AWS build steps completed

### 1. Create the AWS VPC

Built a dedicated AWS VPC for the cloud side of the lab:

- **Name:** `HN_LAB`
- **VPC ID:** `vpc-0aaf0ca5e0fda7938`
- **IPv4 CIDR:** `10.50.0.0/16`
- DNS resolution enabled

---

### 2. Create AWS subnets

Created three subnets inside the VPC:

- `public`
- `private`
- `private_mgmt`

Validated subnet details:

- Public subnet: `10.50.1.0/24` in `us-east-1b`
- Private subnet: `10.50.10.0/24`

---

### 3. Create and attach the Internet Gateway

Enabled internet access by attaching an Internet Gateway to the VPC.

- **Internet Gateway ID:** `igw-005c927b623f8366f`

---

### 4. Update the public route table

Used route table:

- **Route table ID:** `rtb-09ae00a14efdc8ad5`

Routes:

- `10.50.0.0/16 -> local`
- `0.0.0.0/0 -> igw-005c927b623f8366f`

This made the `public` subnet internet reachable.

---

### 5. Launch and validate the EC2 jump host

Created a public EC2 instance for AWS-side validation.

Observed details:

- **Instance name:** `EC2_lab`
- **Instance ID:** `i-00d4128f3b39f6b4c`
- **Public IPv4:** `100.58.191.114`
- **Private IPv4:** `10.50.1.154/24`
- **AMI:** Amazon Linux 2023
- **Username:** `ec2-user`
- **Key:** `EC2_1.pem`

Successful login command:

```bash
ssh -i ~/.ssh/EC2_1.pem ec2-user@100.58.191.114
```

On the instance:

```bash
ip a
```

Key result:

- Interface `enX0` had `10.50.1.154/24`, confirming the instance landed in the expected public subnet.

---

## Internal routing concept

On-prem:

- `rtr1` / `rtr2` have an interface (or sub-interface) in **each** subnet.
- Every VM uses its local VyOS router IP as the **default gateway**.
- VMware carries the VLANs (or separate port groups) to the routers.
- The desktop knows that `10.10.0.0/16` is reachable via `10.0.0.50`.

AWS:

- The public subnet uses the route table with `0.0.0.0/0` to the Internet Gateway.
- Private subnets are reserved for internal AWS workloads and future VPN-connected traffic.
- The EC2 jump host validates public access into AWS before hybrid VPN work begins.

Common validation commands:

```bash
ip a
ip route
ping -c3 <gateway-ip>
ping -c3 <remote-subnet-host>
sysctl net.ipv4.ip_forward
curl https://api.ipify.org
```

---

## Issues you hit and how you fixed them

### 1. VyOS not installed to disk (live-only)

**Symptoms**

- Router booted but long-term persistence was uncertain.

**Fix**

- Ran `install image` on both routers and rebooted from the installed disk.

---

### 2. VLAN / trunk path issues

**Symptoms**

- Some VMs could not reach their gateway.
- Segments felt isolated even with correct IPs.

**Fix**

- Checked VMware vSwitch / port groups to ensure router-facing NICs carried all required VLANs.
- Verified each VM was on the right internal network.

---

### 3. Wrong default gateways on VMs

**Symptoms**

- VMs could ping local hosts but not other VLANs.
- Router self-pings looked fine; host-to-host failed.

**Fix**

- Set each VM’s default gateway to the router IP in its subnet.
- Re-tested from the VMs, not only from routers.

---

### 4. Desktop could not reach lab networks

**Symptoms**

- Desktop had internet but no access to `10.10.x.x`.
- Internal devices talked to each other fine.

**Fix**

- Added `10.10.0.0/16 via 10.0.0.50` on the desktop.
- Made it persistent with Netplan.

---

### 5. Netplan warnings

**Symptoms**

- `sudo netplan apply` complained about file permissions.

**Fix**

```bash
sudo chmod 600 /etc/netplan/01-network-manager-all.yaml
sudo netplan apply
```

---

### 6. AWS route-table and subnet validation

**Symptoms**

- Needed to verify public subnet, route table, IGW, and EC2 layout.

**Fix**

- Confirmed the `public` subnet used the route table with `0.0.0.0/0 -> IGW`.
- Launched EC2 in the `public` subnet with a public IP.
- Restricted SSH access to home public IP.
- Connected with the PEM key and validated the private IP inside the correct subnet.

---

## Command cheat-sheet

```bash
# VyOS (on rtr1 / rtr2)
install image
configure
set system host-name rtr1
set interfaces ethernet eth0 address '10.0.0.50/24'
set interfaces ethernet eth1 address '10.10.10.1/24'
set interfaces ethernet eth2 address '10.10.20.1/24'
commit
save
show interfaces
show ip route
show configuration commands
exit

# Base Ubuntu packages
sudo apt update && sudo apt upgrade -y
sudo apt install -y net-tools iproute2 openssh-server curl wget vim traceroute

# Inspect
ip a
ip route
nmcli device status

# Desktop route (test)
sudo ip route add 10.10.0.0/16 via 10.0.0.50

# Netplan
sudo cat /etc/netplan/01-network-manager-all.yaml
sudo cat /etc/netplan/50-cloud-init.yaml
sudo netplan apply
sudo chmod 600 /etc/netplan/01-network-manager-all.yaml

# Connectivity tests
ping -c3 10.10.10.10
ping -c3 10.10.20.10
ping -c3 10.10.30.10
ping -c3 10.10.40.10
ssh <user>@10.10.20.10

# Check home public IP
curl ifconfig.me
curl https://api.ipify.org

# SSH to AWS EC2 jump host
chmod 400 ~/.ssh/EC2_1.pem
ssh -i ~/.ssh/EC2_1.pem ec2-user@100.58.191.114

# AWS-side validation on the EC2 instance
ip a
ip route
curl https://api.ipify.org
```

---

## Status

- [x] VMware VMs created  
- [x] VyOS installed and saving config  
- [x] Internal routing between lab VLANs working  
- [x] Desktop internet via DHCP  
- [x] Desktop route to `10.10.0.0/16` via `10.0.0.50`  
- [x] AWS VPC `HN_LAB` created  
- [x] Public, private, and private management AWS subnets created  
- [x] Internet Gateway attached and public route configured  
- [x] Public EC2 jump host launched and reachable by SSH  
- [ ] Create Virtual Private Gateway  
- [ ] Create Customer Gateway for the VyOS edge router  
- [ ] Build Site-to-Site VPN between AWS and on-prem  
- [ ] Update private AWS route tables for hybrid routing  
- [ ] Validate end-to-end hybrid connectivity  

---

## Next phase

1. Create and attach a **Virtual Private Gateway** to `HN_LAB`.  
2. Create a **Customer Gateway** using the public IP of the on-prem VyOS edge router.  
3. Build the **Site-to-Site VPN**.  
4. Add private route-table entries for on-prem networks such as `10.0.0.0/24` and `10.10.0.0/16`.  
5. Validate that AWS private resources can reach the VMware/VyOS environment and vice versa.
