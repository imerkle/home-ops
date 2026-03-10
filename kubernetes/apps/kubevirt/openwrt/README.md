# OpenWrt Router-On-A-Stick

This app implements the first cutover with native management on the Talos node and two tagged VLANs for OpenWrt WAN/LAN.

## Repo Defaults

The Flux kustomization in [ks.yaml](./ks.yaml) now targets the live router node:

- router node: `talos-0d4c1`
- native management: untagged `enp5s0` on `10.0.0.99`
- WAN link: `enp5s0.100`
- LAN link: `enp5s0.200`
- OpenWrt LAN IP: `192.168.10.1/24`

The OpenWrt VM consumes:

- `wan-net` on `${OPENWRT_WAN_LINK}`
- `lan-net` on `${OPENWRT_LAN_LINK}`

The VM bootstrap explicitly configures:

- PPPoE on OpenWrt `eth1`
- static LAN on OpenWrt `eth2`
- DHCP service on the LAN interface

## Switch VLANs

Use these VLANs for the first migration:

- `VLAN 1`: native management
- `VLAN 100`: WAN
- `VLAN 200`: OpenWrt LAN

Physical ports for the first staged cutover:

- `Port 2`: ISP router/modem
- `Port 6`: Talos node uplink
- `Port 8`: admin port, stays on native management
- `Port 1`: isolated OpenWrt test client
- `Ports 3,4,5,7`: remain on the old native network until OpenWrt is proven stable

Membership:

- `VLAN 1`
  - `Port 6` = `Untagged`
  - `Port 8` = `Untagged`
  - `Ports 3,4,5,7` = `Untagged`
  - `Port 2` = `Not Member`
  - `Port 1` = `Not Member`
- `VLAN 100`
  - `Port 6` = `Tagged`
  - `Port 2` = `Untagged`
  - `Ports 1,3,4,5,7,8` = `Not Member`
- `VLAN 200`
  - `Port 6` = `Tagged`
  - `Port 1` = `Untagged`
  - `Port 2` = `Not Member`
  - `Ports 3,4,5,7,8` = `Not Member`

If the switch has per-port PVID settings, use:

- `Port 6` PVID = `1`
- `Port 2` PVID = `100`
- `Port 1` PVID = `200`
- `Port 8` PVID = `1`
- `Ports 3,4,5,7` PVID = `1`

## Cutover Sequence

1. Confirm the Talos node still has native management on `10.0.0.99`.
2. Confirm the Talos node exposes `enp5s0.100` and `enp5s0.200` before moving the switch.
3. Apply the OpenWrt manifests and wait for the VM to land on `talos-0d4c1`.
4. Program the switch VLANs exactly as above, but leave the ISP router/modem in router mode first.
5. Keep your admin laptop on `Port 8` so the switch UI and native management network remain reachable.
6. Put one test device on `Port 1` in `VLAN 200`.
7. Verify the test device receives `192.168.10.x` from OpenWrt and reaches `192.168.10.1`.
8. Verify Talos and cluster access still work over the native management path on `10.0.0.99`.
9. Put the ISP router/modem on `Port 2` into bridge mode.
10. Verify OpenWrt establishes PPPoE on `WAN`.
11. Move the remaining client devices from `Ports 3,4,5,7` onto `VLAN 200` one by one.

## Rollback

Rollback is switch- and ISP-side:

1. Disable bridge mode on the ISP router/modem.
2. Restore `Port 1` and any migrated client ports back to the old native network.
3. Remove `Port 6` from `VLAN 100` and `VLAN 200` if you want the node fully out of the router path.
4. Leave Talos on native management at `10.0.0.99`.
5. Stop or scale down the OpenWrt VM after traffic is back on the ISP router path.

## Verification Notes

The current repo expects the Talos node to provide `enp5s0.100` and `enp5s0.200`, but you should confirm those links are visible on the live node before changing the switch. Do not move the switch ports until the node-side VLAN interfaces exist.
