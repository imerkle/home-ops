# Airtel Fiber to OpenWrt Migration & Cutover Guide

This guide details the complete step-by-step procedure to migrate your Airtel fiber connection to OpenWrt running as a KubeVirt VM on Talos Linux (`talos-0d4c1`), including physical cabling, software configuration, validation, and a 2-minute rollback plan.

---

## 1. Network & Hardware Overview

```
[ Airtel Fiber Line ]
         │
         ▼ (SFP Port: enp1s0f1np1)
┌───────────────────────────────────────────────────────────────┐
│ Talos Linux Node (talos-0d4c1)                                │
│                                                               │
│   Host WAN Bridge: br-openwrt-wan  ─── (linked to enp1s0f1np1)│
│                            │                                  │
│                            ▼ (Multus CNI: wan-net)            │
│   ┌───────────────────────────────────────────────────────┐   │
│   │ OpenWrt KubeVirt VM                                   │   │
│   │                                                       │   │
│   │  • WAN (eth0.100) ──> Airtel PPPoE / VLAN 100         │   │
│   │  • SFP Mgmt (eth0) ─> Static 192.168.1.2/24           │   │
│   │  • LAN (br-lan)   ──> 10.0.0.1/24 (DHCP/DNS/NAT)      │   │
│   └───────────────────────┬───────────────────────────────┘   │
│                            │                                  │
│                            ▼ (Multus CNI: lan-net)            │
│   Host LAN Bridge: br-openwrt-lan  ─── (linked to enp5s0)     │
│   (Talos Node IP: 10.0.0.99, Default Gateway: 10.0.0.1)       │
└────────────────────────────┼──────────────────────────────────┘
                             │ (Motherboard RJ45: enp5s0)
                             ▼
                ┌─────────────────────────┐
                │     Physical Switch     │ (Default untagged VLAN 1)
                └──────┬───────────┬──────┘
                       │           │
                       ▼           ▼
                   [ APs / PCs ]  [ Home Devices ]
```

### IP & Subnet Reference
* **LAN Subnet:** `10.0.0.0/24`
* **OpenWrt LAN IP (Final):** `10.0.0.1`
* **OpenWrt LAN IP (Staging):** `10.0.0.254`
* **Talos Node IP:** `10.0.0.99` (on `br-openwrt-lan`, same L2 segment as switch)
* **ODI SFP Stick Management IP:** `192.168.1.1` (*Do NOT change to 10.0.0.x; OpenWrt routes to it via NAT*)
* **Old Airtel Router IP:** `10.0.0.4` (or `10.0.0.1`)

---

## 2. Phase 1: Pre-requisites & ODI SFP Stick Configuration *(Zero Downtime)*

Before changing any cables or network configurations, ensure the ODI GPON stick is synced with Airtel's OLT.

### Step 1.1: Record Details from Airtel Stock Router
1. **GPON Serial Number (PON SN):** On the sticker underneath the Airtel router (e.g. `ALCLxxxxxxxx`, `SMBSxxxxxxxx`, `HWTCxxxxxxxx`, or `ZTEGxxxxxxxx`).
2. **PPPoE Username & Password:** (e.g., `011xxxxxx_dsl@airtelbroadband.in` and password from Airtel SMS/App).
3. **MAC Address:** On the router sticker.

### Step 1.2: Configure the SFP Stick
1. Open the stick's web UI in your browser: **`http://10.0.0.99:8080`** *(or SSH `ssh admin@10.0.0.99 -p 2222`)*.
2. Enter the cloned **GPON Serial Number (PON SN)**.
3. Set **OMCI / OLT Mode** (typically `1` for Huawei, `2` for ZTE, or matching your local OLT vendor).
4. Verify **PON Status**: Look for status **`O5` (Operation State)**. `O5` confirms the optical link and authentication with Airtel are active.

---

## 3. Phase 2: Apply Talos Machine Config & Kubernetes Manifests

Apply the host bridge networking and VM specifications to the cluster.

### Step 2.1: Apply Talos Machine Config
```bash
cd /home/slim/repos/personal/home-ops

# Apply machine config to node (Talos creates br-openwrt-wan and br-openwrt-lan):
just talos apply-node talos-0d4c1
```
*Verification:* Talos node remains `Ready` on `10.0.0.99`.

### Step 2.2: Apply Multus & OpenWrt Manifests
```bash
kubectl apply -f kubernetes/apps/virtualization/vms/openwrt/app/networks.yaml
kubectl apply -f kubernetes/apps/virtualization/vms/openwrt/app/vm.yaml
```

---

## 4. Phase 3: OpenWrt In-Guest Configuration *(Safe Staging)*

Configure OpenWrt inside the VM while the old router remains active.

### Step 3.1: Open the VM Console
```bash
virtctl console -n kubevirt openwrt
# Press Enter to activate the shell prompt
```

### Step 3.2: Run Staging Configuration Commands
Run the following commands inside OpenWrt:

```bash
# 1. Create 802.1Q VLAN 100 on eth0 (WAN SFP link)
uci set network.wan_dev=device
uci set network.wan_dev.name='eth0.100'
uci set network.wan_dev.type='8021q'
uci set network.wan_dev.ifname='eth0'
uci set network.wan_dev.vid='100'

# 2. Configure PPPoE WAN interface
uci set network.wan=interface
uci set network.wan.device='eth0.100'
uci set network.wan.proto='pppoe'
uci set network.wan.username='<YOUR_AIRTEL_USERNAME>_dsl@airtelbroadband.in'
uci set network.wan.password='<YOUR_AIRTEL_PASSWORD>'
uci set network.wan.ipv6='auto'

# 3. Configure SFP Stick Management alias (192.168.1.1)
uci set network.sfp_mgmt=interface
uci set network.sfp_mgmt.device='eth0'
uci set network.sfp_mgmt.proto='static'
uci set network.sfp_mgmt.ipaddr='192.168.1.2'
uci set network.sfp_mgmt.netmask='255.255.255.0'
uci add_list firewall.@zone[1].network='sfp_mgmt'

# 4. Configure Staging LAN (DHCP disabled to prevent conflicts)
uci set network.lan.ipaddr='10.0.0.254'
uci set network.lan.netmask='255.255.255.0'
uci set dhcp.lan.ignore='1'

# 5. Commit and restart services
uci commit
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/dnsmasq restart
```

### Step 3.3: Verify WAN Link
Inside OpenWrt, check that PPPoE is connected:
```bash
ifstatus wan
```
*Look for `"up": true` and an assigned public IPv4 address.*

---

## 5. Phase 4: Physical Cutover Sequence

Now perform the actual switchover.

### Step 4.1: Physical Cable Disconnection
1. **Unplug the LAN Ethernet cable** connecting the old Airtel router to your physical network switch.
2. *(If the fiber patch cord is still in the old router, move it into the SFP stick cage on the node).*

### Step 4.2: Promote OpenWrt to Primary Router (`10.0.0.1`) & Enable DHCP
In the OpenWrt console (`virtctl console -n kubevirt openwrt`), run:

```bash
# Claim primary gateway IP
uci set network.lan.ipaddr='10.0.0.1'
uci set network.lan.netmask='255.255.255.0'

# Enable DHCP Server
uci set dhcp.lan.ignore='0'
uci set dhcp.lan.start='100'
uci set dhcp.lan.limit='150'
uci set dhcp.lan.leasetime='12h'

# Set DNS servers
uci set network.lan.dns='1.1.1.1 1.0.0.1'

uci commit
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/dnsmasq restart
```

### Step 4.3: Update Talos Node Default Gateway
In `talos/machineconfig.yaml.j2`, update the default gateway to OpenWrt:
```yaml
      - interface: br-openwrt-lan
        addresses:
          - 10.0.0.99/24
          - fe80::aaa1:59ff:fe53:1f41/64
        routes:
          - network: 0.0.0.0/0
            gateway: 10.0.0.1 # Changed from 10.0.0.4
        bridge:
          interfaces:
            - enp5s0
```
Apply the change:
```bash
just talos apply-node talos-0d4c1
```

### Step 4.4: Refresh Client Connections
On your client computers and mobile devices:
* Disconnect and reconnect Wi-Fi, or unplug and replug the Ethernet cable to receive a fresh DHCP lease from OpenWrt (`10.0.0.100`–`10.0.0.250`).

### Step 4.5: Validation Checklist
- [ ] Ping external IP: `ping 1.1.1.1`
- [ ] Ping domain name: `ping google.com`
- [ ] Access ODI stick GUI: Open `http://192.168.1.1` in browser (from any LAN device)
- [ ] Check Talos node: `kubectl get nodes` (shows `talos-0d4c1` as `Ready`)

---

## 6. Phase 5: Rollback Procedure *(Under 2 Minutes)*

If anything unexpected happens or internet does not come up, execute this rollback:

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Stop OpenWrt VM:                                         │
│    kubectl -n kubevirt patch vm openwrt --type merge \      │
│      -p '{"spec":{"running":false}}'                        │
├─────────────────────────────────────────────────────────────┤
│ 2. Physical Action:                                         │
│    Plug old Airtel router's LAN cable back into the switch. │
│    (Move fiber back if needed).                             │
├─────────────────────────────────────────────────────────────┤
│ 3. Revert Talos Gateway (if modified):                      │
│    Change gateway to 10.0.0.4 in machineconfig.yaml.j2      │
│    just talos apply-node talos-0d4c1                        │
├─────────────────────────────────────────────────────────────┤
│ 4. Reconnect Clients:                                       │
│    Toggle Wi-Fi/Ethernet on client devices to restore IP.   │
└─────────────────────────────────────────────────────────────┘
```
