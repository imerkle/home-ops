# OpenWrt Router-On-A-Stick

This app implements the first cutover with native management on the Talos node and two tagged VLANs for OpenWrt WAN/LAN.

## Repo Defaults

The Flux kustomization in [ks.yaml](./ks.yaml) now targets the live router node:

- router node: `talos-0d4c1`
- native management: untagged `enp5s0` on `10.0.0.99`
- WAN VLAN: `enp5s0.100` bridged into `br-openwrt-wan`
- LAN VLAN: `enp5s0.200` bridged into `br-openwrt-lan`
- OpenWrt LAN IP: `192.168.10.1/24`

The OpenWrt VM consumes:

- `wan-net` on host bridge `${OPENWRT_WAN_LINK}`
- `lan-net` on host bridge `${OPENWRT_LAN_LINK}`

The VM now boots from the persistent PVC `openwrt-state` instead of a transient `containerDisk`.
That means once you fix OpenWrt from inside the guest, the changes survive VM restarts.

This repo no longer relies on `cloudInitNoCloud` for OpenWrt bootstrap because the current
`containercraft/openwrt:24` image does not apply that config in KubeVirt.

## Why The Old Layout Failed

Talos/KubeVirt/Multus can attach extra VM NICs in several ways, but the combination matters.

The previous repo state mixed:

- Multus `macvlan` secondary networks
- KubeVirt VM secondary interfaces intended for VM exposure

According to the Sidero Multus guide and the linked KubeVirt behavior notes, that is the wrong
pattern for VMs you want to expose externally. For KubeVirt secondary interfaces, use a host
`bridge` network on the node and attach the VM with KubeVirt `bridge` interfaces.

This repo now follows that model:

- Talos creates VLAN links `enp5s0.100` and `enp5s0.200`
- Talos creates host bridges `br-openwrt-wan` and `br-openwrt-lan` over those VLAN links
- Multus NADs use CNI `type: bridge`
- OpenWrt uses KubeVirt `bridge` interfaces for `wan` and `lan`

## Root Disk Seeding

Because this cluster does not have CDI `DataVolume` support installed, seed the persistent
OpenWrt boot disk once before starting the VM from the PVC:

```bash
kubectl -n kubevirt patch vm openwrt --type merge -p '{"spec":{"running":false}}'
./kubernetes/apps/kubevirt/openwrt/seed-rootdisk.sh
kubectl -n kubevirt patch vm openwrt --type merge -p '{"spec":{"running":true}}'
```

The seeder stages `/disk/openwrt-24.qcow2` from the OpenWrt image, converts it to a raw disk,
and writes the result into `openwrt-state` as `/disk.img`, which KubeVirt can boot directly
from the filesystem PVC.

If you already seeded the PVC with the older copy-only workflow, reseed it now. A qcow2 payload
stored directly as `/disk.img` will show up in VNC as `No bootable device`.

After that, any UCI changes made inside OpenWrt are persistent.

## Console Access

KubeVirt auto-attaches a serial device to this VM, so `virtctl console -n kubevirt openwrt`
can connect even when the guest is not actually presenting a login prompt on `ttyS0`.

With the current `containercraft/openwrt:24` image, the common failure mode is:

- the VMI is `Running`
- `virtctl console` connects and then appears to hang
- the guest serial log stays empty because OpenWrt is not writing boot or login output to `ttyS0`

Check that condition directly with:

```bash
./kubernetes/apps/kubevirt/openwrt/check-serial-console.sh
```

If the reported serial log size is `0`, this is a guest-image problem, not a KubeVirt transport problem.

### Recovery Path

If `virtctl console` hangs, use VNC to recover the guest instead:

```bash
virtctl vnc -n kubevirt openwrt
```

Inside OpenWrt, enable serial console persistently:

- ensure the kernel command line includes `console=ttyS0`
- ensure a login service is enabled on `ttyS0`
- reboot the guest and confirm the serial log is no longer empty

Because this VM boots from the persistent PVC `openwrt-state`, those guest-side changes survive restarts.

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
3. Seed the OpenWrt root disk with [seed-rootdisk.sh](./seed-rootdisk.sh).
4. Apply the OpenWrt manifests and wait for the VM to land on `talos-0d4c1`.
5. Program the switch VLANs exactly as above, but leave the ISP router/modem in router mode first.
6. Keep your admin laptop on `Port 8` so the switch UI and native management network remain reachable.
7. Put one test device on `Port 1` in `VLAN 200`.
8. Verify the test device receives `192.168.10.x` from OpenWrt and reaches `192.168.10.1`.
9. Verify Talos and cluster access still work over the native management path on `10.0.0.99`.
10. Put the ISP router/modem on `Port 2` into bridge mode.
11. Verify OpenWrt establishes PPPoE on `WAN`.
12. Move the remaining client devices from `Ports 3,4,5,7` onto `VLAN 200` one by one.

## Rollback

Rollback is switch- and ISP-side:

1. Disable bridge mode on the ISP router/modem.
2. Restore `Port 1` and any migrated client ports back to the old native network.
3. Remove `Port 6` from `VLAN 100` and `VLAN 200` if you want the node fully out of the router path.
4. Leave Talos on native management at `10.0.0.99`.
5. Stop or scale down the OpenWrt VM after traffic is back on the ISP router path.

## Verification Notes

The current repo expects the Talos node to provide:

- `enp5s0.100`
- `enp5s0.200`
- `br-openwrt-wan`
- `br-openwrt-lan`

Do not move the switch ports until those links exist on the live node.
