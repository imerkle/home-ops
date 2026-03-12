# Windows XP on KubeVirt

This app declares a stopped KubeVirt VM for Windows XP under the `kubevirt` namespace.

## Compatibility Choices

Windows XP needs a few legacy-oriented settings to boot reliably on KubeVirt:

- `kubevirt.io/disablePCIHole64: "true"` on the VM template, per the KubeVirt legacy Windows guidance
- BIOS boot instead of UEFI
- a `sata` system disk to better match common VMware-origin XP appliances; if the imported image was built against a different controller, boot can still fail
- an `e1000` NIC model instead of a virtio NIC

The VM is created with `running: false` so Flux can reconcile it before the PVC contents are staged.

## Preferred Workflow

Use a preinstalled Windows XP image instead of a stock XP installer ISO if possible. A stock ISO can still fail on KubeVirt with `STOP 0x0000007B` during setup because XP text-mode setup may not have the needed storage driver.

If you want to try an ISO install anyway, stage the ISO into the install-media PVC and boot from that first:

```bash
./kubernetes/apps/kubevirt/windows-xp/stage-install-media.sh /home/slim/Downloads/Windows_XP_Professional_x64.iso
kubectl -n kubevirt patch vm windows-xp --type merge -p '{"spec":{"running":true}}'
virtctl vnc -n kubevirt windows-xp
```

The VM is currently sized to match the working QEMU test you described:

- 4 vCPU cores
- 4028 MiB RAM

The VM intentionally stays on a supported `q35` machine type in KubeVirt, because every `i440fx/pc` attempt on this cluster has failed before guest boot with a libvirt PCI-root mismatch.

If your preinstalled image is an OVA, VMDK, or VDI, import it into the system PVC:

```bash
./kubernetes/apps/kubevirt/windows-xp/import-ova.sh /path/to/windows-xp.ova
# or
./kubernetes/apps/kubevirt/windows-xp/import-ova.sh /path/to/windows-xp.vmdk
# or
./kubernetes/apps/kubevirt/windows-xp/import-ova.sh /path/to/windows-xp.vdi
```

Then start the VM:

```bash
kubectl -n kubevirt patch vm windows-xp --type merge -p '{"spec":{"running":true}}'
virtctl vnc -n kubevirt windows-xp
```

## Required Media

Because this cluster does not currently use CDI `DataVolume` uploads, the system PVC must be prepared manually before the first boot:

- `windows-xp-systemdisk` must contain a raw disk at `/disk.img`
- the PVC must be at least as large as the guest virtual disk; the current preinstalled image is `40 GiB`, so this repo now requests `50Gi`

KubeVirt expects filesystem PVC-backed disk content at the root of the volume with the filename `disk.img`.

## Important Limitation

KubeVirt does not provide a legacy IDE hard-disk mode for this VM. Current KubeVirt supports `virtio`, `sata`, and `scsi` disk buses.

That means a stock Windows XP SP3 installer ISO can still fail during setup unless you do one of these:

- use an XP image that already has the needed storage driver integrated
- rebuild the XP installer ISO with the required storage driver slipstreamed into setup
- install from a prebuilt XP disk image instead of a stock installer ISO

## Alternate Blank Disk Workflow

If you still want to seed a blank disk manually:

1. Create a blank raw disk on the system PVC:

```bash
./kubernetes/apps/kubevirt/windows-xp/seed-systemdisk.sh
```

The helper now defaults to a `40G` raw disk so it matches the imported XP image size.

2. Import a prepared disk image into the PVC or use a separately customized installer workflow.

## First Boot

1. Start the VM:

```bash
kubectl -n kubevirt patch vm windows-xp --type merge -p '{"spec":{"running":true}}'
```

2. Connect with VNC:

```bash
virtctl vnc -n kubevirt windows-xp
```
