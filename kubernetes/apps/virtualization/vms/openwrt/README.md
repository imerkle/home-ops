# Staged OpenWrt router

This workload prepares OpenWrt without changing the physical connection to the
old router or ONT.

## Network contract

The existing LAN stays unchanged throughout staging:

- LAN: `10.0.0.0/24`
- existing router: `10.0.0.1`
- Talos node: `10.0.0.99`
- staging OpenWrt LAN address: `10.0.0.254`

Talos places `10.0.0.99` on `br-openwrt-lan`, a host bridge over `enp5s0`.
The bridge preserves the existing physical LAN connection while allowing the
OpenWrt VM LAN interface to join the same Layer-2 segment.

During staging, the VM's `wan` interface uses Kubernetes pod networking. The
Mellanox SFP interface and its `192.168.1.2` management address are not
attached to the VM or otherwise changed. This makes it safe to boot and
configure OpenWrt while the old router remains connected.

OpenWrt is not given `10.0.0.1` and does not run DHCP during staging: those
would conflict with the old router.

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

## Staging acceptance checks

1. Apply the Talos configuration in `try` mode first. It must show
   `br-openwrt-lan` with `10.0.0.99/24`, and the node must remain Ready.
2. Apply the OpenWrt manifests, seed the disk, and start the VM.
3. From the VM console, identify its LAN device (`ip link`), assign it
   `10.0.0.254/24`, and explicitly disable its LAN DHCP server. Do not alter
   the old router or use `10.0.0.1` yet.
4. From an existing LAN client, verify that `10.0.0.254` answers and that the
   old router remains the DHCP server and default gateway.
5. Shut the VM down again before the SFP cutover. It must not be attached to
   the physical WAN until its actual ISP requirements have been verified.

## Physical cutover (not part of staging)

Only begin cutover after all acceptance checks pass.

1. Capture the ISP WAN details: VLAN ID, DHCP versus PPPoE, MTU, and any
   required MAC address or PPPoE credentials.
2. Change the VM `wan` from its temporary pod network to a host bridge over
   the Mellanox SFP interface. Preserve a path for the existing xPON proxy to
   reach its `192.168.x.x` management network.
3. In OpenWrt, set the LAN address to `10.0.0.1/24`, configure the current
   DHCP reservations/range/DNS, and keep DHCP disabled until the old router is
   disconnected.
4. Disconnect the old router, attach the WAN to the SFP path, enable OpenWrt
   DHCP, and test Internet access from Talos and one LAN client.

## Recovery

If anything fails before the physical cutover, stop the OpenWrt VM; the old
router continues to own `10.0.0.1` and DHCP. If it fails during cutover, power
off OpenWrt and restore the old router's WAN connection; the LAN addressing
returns to its previous state.
