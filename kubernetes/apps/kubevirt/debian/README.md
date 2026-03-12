# Debian Test VM on KubeVirt

This app is a clean Debian installer VM used to verify that KubeVirt guests boot correctly on this cluster without the legacy Windows XP complications.

## VM Shape

- exact supported machine type: `pc-q35-rhel9.6.0`
- BIOS boot
- 2 vCPU cores
- 2048 MiB RAM
- SATA CD-ROM for the Debian ISO
- SATA system disk
- `e1000` NIC on the default pod network

## ISO Install

1. Stage the Debian ISO into the install-media PVC:

```bash
./kubernetes/apps/kubevirt/debian/stage-install-media.sh /path/to/debian.iso
```

2. Start the VM:

```bash
kubectl -n kubevirt patch vm debian --type merge -p '{"spec":{"running":true}}'
```

3. Connect with VNC:

```bash
virtctl vnc -n kubevirt debian
```

After Debian is installed, either remove the install-media disk from the manifest or flip the boot order so the system disk boots first.
