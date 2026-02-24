# VyOS Migration & Killswitch Guide

This document outlines the steps to cutover your internet connection to the Kubernetes-hosted VyOS router, and how to rapidly revert (killswitch) in case of an emergency.

## 1. Migration (Cutover)

To switch from the ISP router to the Kubernetes VyOS router:

1. Connect to the admin portal of your ISP router.
2. Change the ISP router's operation mode from **Router** (PPPoE) to **Bridge Mode**.
3. Verify the VyOS HelmRelease in the cluster is active (it should automatically dial PPPoE once the ISP router bridges the connection).
   ```bash
   flux reconcile hr vyos -n network
   kubectl logs -n network -l app.kubernetes.io/name=vyos
   ```

## 2. Emergency Killswitch (Rollback)

If the Kubernetes VyOS pod fails, crashes, or the cluster goes down, you will lose internet. You can restore your original network instantly:

1. **Suspend the VyOS Pod**: Prevent IP conflicts by telling Flux to suspend the VyOS HelmRelease and scaling the deployment to 0.
   ```bash
   flux suspend hr vyos -n network
   kubectl scale statefulset vyos -n network --replicas=0
   ```
2. **Reconfigure ISP Router**: Connect to your ISP router's admin portal (or factory reset it if you cannot reach the portal) and change the operation mode back to **Router (PPPoE)**.
3. **Restore Connectivity**: Because the ISP router's IP and DHCP server match the settings used by the VyOS pod (e.g. `192.168.1.1`), the rest of your network (Homelab, Talos nodes, personal devices) will instantly reconnect to the internet. No configuration changes are required on any other device.
