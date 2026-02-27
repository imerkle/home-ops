# Rook-Ceph Incident Report and Recovery Runbook (2026-02-27)

## Summary

- Cluster was degraded with `HEALTH_ERR` and stuck around OSD bring-up.
- User requirement: recover Ceph **without deleting the cluster** and **without data loss**.
- Recovery outcome: cluster restored to serving state and moved from `HEALTH_ERR` to `HEALTH_WARN` with all PGs `active+clean`.

## Impact Observed

- Ceph was reporting:
  - `Configuring Ceph OSDs`
  - OSD instability (`osd.0` down/intermittent)
  - CephFS unavailable (`MDS_ALL_DOWN`)
  - `Reduced data availability` and inactive PGs
- `CephFilesystem` custom resource was missing in Kubernetes while the Ceph FS pools/data still existed in Ceph.

## Findings (Root Causes)

## 1) OSD startup deadlock/lock contention during recovery

- `rook-ceph-osd-0` init path was unstable during recovery.
- A temporary manual OSD recovery pod was required to bring `osd.0` up, but once the managed OSD pod returned, both could contend for the same device/OSD lock if run together.
- `expand-bluefs` failed while manual pod was still holding the OSD lock (`Device or resource busy` / lock errors).

## 2) Missing `CephFilesystem` CR object in Kubernetes

- Ceph still had filesystem pools (`ceph-filesystem-metadata`, `ceph-filesystem-data0`) and filesystem state, but Kubernetes no longer had the `CephFilesystem` object.
- This prevented normal Rook orchestration for MDS and left CephFS degraded/offline.

## 3) Inactive PGs from `default.rgw.log` pool size mismatch

- Pool `default.rgw.log` had `size=3`/`min_size=2` in a 1-OSD cluster.
- This caused 32 PGs to remain `undersized+peered` and inactive until pool size was aligned to available OSD count.

## Actions Taken (Non-Destructive)

## A) Restored managed OSD ownership

1. Confirmed managed OSD pod status and init failures.
2. Used temporary manual recovery pod only to bootstrap OSD availability.
3. Removed manual pod and restarted managed `rook-ceph-osd-0` so Rook-owned pod is authoritative.
4. Verified managed OSD pod stable (`2/2 Running`) and `ceph -s` sees `1 osd: 1 up, 1 in`.

Important: running both manual and managed OSD pods for same OSD causes lock contention and startup failures.

## B) Recreated missing CephFilesystem CR safely

1. Recreated `CephFilesystem` named `ceph-filesystem` in namespace `rook-ceph`.
2. Used existing pool names:
   - metadata: `ceph-filesystem-metadata`
   - data: `ceph-filesystem-data0`
3. Set `preserveFilesystemOnDelete: true`.
4. Verified MDS came back (`1/1 up` with standby) and CephFS volume health recovered.

## C) Cleared inactive PG outage condition

1. Identified all inactive PGs belonging to pool `default.rgw.log` (pool 12).
2. Set:
   - `size=1` (with `--yes-i-really-mean-it` because this is single replica)
   - `min_size=1`
3. Verified PG state moved to `200 active+clean`.

## D) Restored Helm/Flux ownership metadata on recreated resource

- Added labels/annotations to `CephFilesystem` so Helm/Flux reconciliation recognizes it as managed by `rook-ceph-cluster`.

## Final State at Recovery Completion

- `ceph -s`: `HEALTH_WARN` (no longer `HEALTH_ERR`)
- Services:
  - `mon`: healthy
  - `mgr`: healthy
  - `osd`: `1 up, 1 in`
  - `mds`: `1/1 up` + standby
  - `rgw`: active
- Data:
  - `200 active+clean` PGs
  - CephFS and object store recovered to Ready

Remaining warnings are expected for current single-OSD topology (no replica redundancy and default-size warning patterns).

## Recovery Procedure (If This Happens Again)

Use this order and do not run destructive operations:

1. Baseline health and pod state
   - `kubectl -n rook-ceph get cephcluster rook-ceph -o wide`
   - `kubectl -n rook-ceph get pods -o wide`
   - `kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph -s`

2. If `osd.0` is down and managed pod is stuck:
   - Inspect init container logs (`activate`, `expand-bluefs`).
   - If manual recovery pod is used temporarily, remove it before handing back to managed OSD.
   - Ensure only one process owns OSD device/lock.

3. Verify `CephFilesystem` CR exists
   - `kubectl -n rook-ceph get cephfilesystem`
   - If missing, recreate `ceph-filesystem` using existing pools and `preserveFilesystemOnDelete: true`.

4. Verify MDS recovery
   - `kubectl -n rook-ceph get pods | rg mds`
   - `kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph fs status ceph-filesystem`

5. If PGs remain inactive due to pool replication > available OSDs:
   - Identify offending pool via `ceph health detail`.
   - For single-OSD emergency setup, temporarily align that pool to `size=1` and `min_size=1`.

6. Validate completion
   - `kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph -s`
   - Confirm target: no `PG_AVAILABILITY`, no MDS down, OSD managed pod running, PGs `active+clean`.

## Safety Guardrails Followed

- No `CephCluster` deletion.
- No disk wipe/OSD zap.
- No data path cleanup jobs.
- No destructive reset actions.

## Follow-up Recommendations

1. Add more OSDs/nodes to enable real replication and eliminate single-point failure behavior.
2. Align default pool size/min_size with actual topology if staying single-node.
3. Keep this runbook with cluster ops docs and version-control any recovery manifest used.
