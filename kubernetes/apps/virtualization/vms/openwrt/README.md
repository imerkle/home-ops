# OpenWrt Router (KubeVirt VM)

This workload runs OpenWrt as a KubeVirt VM acting as the primary home router.

> [!NOTE]
> For the complete step-by-step physical cabling, in-guest UCI commands, validation checklist, and rollback procedures, see the **[Airtel Migration & Cutover Guide](./CUTOVER-GUIDE.md)**.

## Network Architecture

```
Airtel Fiber → ODI SFP Stick (192.168.1.1)
                    │
                    ▼ (enp1s0f1np1)
              br-openwrt-wan ──→ OpenWrt VM eth0
                                  ├─ eth0.100 (VLAN 100 PPPoE WAN)
                                  └─ eth0 raw (192.168.1.2 SFP mgmt)
                                  │
                                  ▼ eth1 (LAN)
              br-openwrt-lan ──→ enp5s0 → Switch → All Clients
                    │
              Talos Node (10.0.0.99)
```

- LAN: `10.0.0.0/24`
- OpenWrt LAN IP: `10.0.0.1` (after cutover) / `10.0.0.254` (staging)
- Talos node: `10.0.0.99` (on `br-openwrt-lan`, same L2 as all LAN clients)
- ODI SFP stick: `192.168.1.1` (WAN side, **do not change** — accessed via
  OpenWrt NAT from LAN)

### ODI SFP Stick IP

The ODI stick stays at `192.168.1.1/24` on its own isolated subnet on the WAN
bridge. Do **not** change it to a `10.0.0.x` address. OpenWrt creates a
`sfp_mgmt` interface (`192.168.1.2/24`) on raw `eth0` and NATs LAN traffic to
it, so any LAN client can reach `http://192.168.1.1` transparently.

## Root disk seeding

The VM boots from the persistent PVC `openwrt-state`. Seed it once before
starting the VM:

```bash
kubectl -n kubevirt patch vm openwrt --type merge -p '{"spec":{"running":false}}'
./kubernetes/apps/virtualization/vms/openwrt/seed-rootdisk.sh
kubectl -n kubevirt patch vm openwrt --type merge -p '{"spec":{"running":true}}'
```

The seeder converts the image disk to `/disk.img` on the PVC. Guest-side UCI
configuration is retained across VM restarts.

## OpenWrt In-Guest Configuration (UCI Commands)

Connect to the OpenWrt VM console:
```bash
virtctl console -n kubevirt openwrt
# Or check serial logs if console is detached:
./kubernetes/apps/virtualization/vms/openwrt/check-serial-console.sh
```

### 1. WAN Configuration (Airtel PPPoE on VLAN 100)
Airtel Fiber requires 802.1Q VLAN tag 100 on the incoming fiber SFP (`eth0`):

```bash
# Create 802.1Q VLAN 100 device on eth0 (WAN SFP link)
uci set network.wan_dev=device
uci set network.wan_dev.name='eth0.100'
uci set network.wan_dev.type='8021q'
uci set network.wan_dev.ifname='eth0'
uci set network.wan_dev.vid='100'

# Configure PPPoE WAN interface on VLAN 100
uci set network.wan=interface
uci set network.wan.device='eth0.100'
uci set network.wan.proto='pppoe'
uci set network.wan.username='<your_airtel_username>_dsl@airtelbroadband.in'
uci set network.wan.password='<your_airtel_password>'
uci set network.wan.ipv6='auto'
```

### 2. SFP Stick Management (Access 192.168.1.1 from LAN)
Allow any LAN client (`10.0.0.x`) to access the ODI GPON stick web UI (`http://192.168.1.1`):

```bash
# Create static IP alias on raw eth0
uci set network.sfp_mgmt=interface
uci set network.sfp_mgmt.device='eth0'
uci set network.sfp_mgmt.proto='static'
uci set network.sfp_mgmt.ipaddr='192.168.1.2'
uci set network.sfp_mgmt.netmask='255.255.255.0'

# Assign sfp_mgmt to WAN firewall zone to enable NAT from LAN
uci add_list firewall.@zone[1].network='sfp_mgmt'
```

### 3. LAN Configuration

#### Staging Mode (While Old Router is still active):
```bash
# Keep DHCP disabled to prevent conflicts with old router
uci set network.lan.ipaddr='10.0.0.254'
uci set network.lan.netmask='255.255.255.0'
uci set dhcp.lan.ignore='1'

uci commit
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/dnsmasq restart
```

#### Final Cutover Mode (Promoting OpenWrt to Primary Router):
```bash
# Set primary router IP and enable DHCP server
uci set network.lan.ipaddr='10.0.0.1'
uci set network.lan.netmask='255.255.255.0'
uci set dhcp.lan.ignore='0'
uci set dhcp.lan.start='100'
uci set dhcp.lan.limit='150'
uci set dhcp.lan.leasetime='12h'

# Set upstream DNS
uci set network.lan.dns='1.1.1.1 1.0.0.1'

uci commit
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/dnsmasq restart
```

## Physical Cutover Sequence

1. Disconnect the old ISP router from the switch.
2. Run the **Final Cutover Mode** commands inside OpenWrt to claim `10.0.0.1` and enable DHCP.
3. Update the Talos machineconfig default gateway from `10.0.0.4` (old router)
   to `10.0.0.1` (OpenWrt) in `talos/machineconfig.yaml.j2` and apply:
   ```bash
   # In machineconfig.yaml.j2, change gateway: 10.0.0.4 → gateway: 10.0.0.1
   just talos apply-node talos-0d4c1
   ```
4. Verify PPPoE connects: `ifstatus wan` (inside OpenWrt console)
5. Test internet from client: `ping 1.1.1.1`
6. Test SFP stick access from client: Open `http://192.168.1.1` in browser.
7. Verify Talos node: `kubectl get nodes` (must show `Ready`)

## Recovery

If anything fails during cutover:
1. Power off OpenWrt VM: `kubectl -n kubevirt patch vm openwrt --type merge -p '{"spec":{"running":false}}'`
2. Reconnect the old router to the switch. The LAN immediately returns to its previous state.



old gpon default
XPON21117096
ODI
vlan pvid 41

airtel gpon
GNXS927028D8
SCOM

ppoe
03310237744_dsl@airtelbroadband.in
20000489261