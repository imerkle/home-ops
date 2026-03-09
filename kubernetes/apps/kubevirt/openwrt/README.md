# OpenWrt Router-On-A-Stick

This app assumes a managed switch and a single Kubernetes node acting as the physical router uplink.

## Topology

- `MGMT VLAN`: node management, cluster access, switch management
- `WAN VLAN`: switch trunk to the router node, bridged to the ISP modem/router in bridge mode
- `LAN VLAN`: switch trunk to the router node, access ports for downstream clients

The OpenWrt VM consumes:

- `wan-net` on `${OPENWRT_WAN_LINK}`
- `lan-net` on `${OPENWRT_LAN_LINK}`

Do not attach `lan-net` to the raw parent NIC. Keep node management on a separate VLAN/interface so OpenWrt and the node are not competing on the same L2 segment.

## Repo Defaults

The Flux kustomization sets conservative defaults in [ks.yaml](./ks.yaml):

- router node: `k8s-0`
- WAN link: `enp5s0.100`
- LAN link: `enp5s0.200`
- OpenWrt LAN IP: `192.168.10.1/24`

Adjust those values before cutover if your trunk, VLAN IDs, or router node differ.

## Talos Example

Create VLAN subinterfaces on the router node before applying the VM. This follows the same resource style already commented in [talos/machineconfig.yaml.j2](/home/slim/repos/home-ops/talos/machineconfig.yaml.j2).

```yaml
# ---
# apiVersion: v1alpha1
# kind: VLANConfig
# name: enp5s0.100
# vlanID: 100
# parent: enp5s0
# ---
# apiVersion: v1alpha1
# kind: VLANConfig
# name: enp5s0.200
# vlanID: 200
# parent: enp5s0
```

Recommended switch layout:

- ISP modem/bridge port: access VLAN `100`
- router node port: trunk VLANs `10,100,200`
- downstream client ports: access VLAN `200`
- one admin port: access VLAN `10`

## Cutover Sequence

1. Confirm the router node has the VLAN subinterfaces present.
2. Confirm the switch trunk and access ports are in place.
3. Deploy OpenWrt and verify LAN-side DHCP/admin access from a single test port on the `LAN VLAN`.
4. Put the ISP device into bridge mode and verify PPPoE from OpenWrt.
5. Move the remaining client ports to the `LAN VLAN`.

## Rollback

Rollback is primarily a switch and ISP-router action, not a Kubernetes action.

1. Restore the switch profile that points client ports back to the ISP router path.
2. Disable bridge mode on the ISP router.
3. Only then use [gateway-switch.sh](./gateway-switch.sh) if the router node itself also needs its host route changed.

The attached `openwrt-state` PVC gives the VM a persistent disk, but OpenWrt still needs guest-side storage configuration if you want to migrate runtime state fully off the container disk.
