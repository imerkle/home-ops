# Windows XP on KubeVirt

This app declares a stopped KubeVirt VM for Windows XP under the `kubevirt` namespace.

## Compatibility Choices

Windows XP needs a few legacy-oriented settings to boot reliably on KubeVirt:

- `kubevirt.io/disablePCIHole64: "true"` on the VM template, per the KubeVirt legacy Windows guidance
- BIOS boot instead of UEFI
- a `scsi` system disk, because KubeVirt does not expose an IDE hard-disk bus and stock XP setup usually fails against AHCI/SATA with `STOP 0x0000007B`
- SATA CD-ROM devices for the installer and virtio driver media
- an `e1000` NIC model instead of a virtio NIC

The VM is created with `running: false` so Flux can reconcile it before the PVC contents are staged.

## Preferred Workflow

Use a preinstalled Windows XP image instead of a stock XP installer ISO. A stock ISO usually fails on KubeVirt with `STOP 0x0000007B` during setup because XP text-mode setup does not have the needed storage driver.

If your preinstalled image is an OVA, extract and import its VMDK into the system PVC:

```bash
./kubernetes/apps/kubevirt/windows-xp/import-ova.sh /path/to/windows-xp.ova
```

Then start the VM:

```bash
kubectl -n kubevirt patch vm windows-xp --type merge -p '{"spec":{"running":true}}'
virtctl vnc -n kubevirt windows-xp
```

## Required Media

Because this cluster does not currently use CDI `DataVolume` uploads, the system PVC must be prepared manually before the first boot:

- `windows-xp-systemdisk` must contain a raw disk at `/disk.img`

KubeVirt expects filesystem PVC-backed disk content at the root of the volume with the filename `disk.img`.

## Important Limitation

KubeVirt does not provide a legacy IDE/ATAPI hard-disk mode for this VM. For disks it supports `virtio` and `scsi`, while optical media is exposed as `sata`.

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