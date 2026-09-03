# VolSync Component

This component provides standardized, automated persistent volume claim (PVC) backup and recovery across the cluster using [VolSync](https://github.com/backube/volsync) with [Kopia](https://kopia.io).

---

## Architecture & Storage Design

Backups are synchronized using a two-tier strategy:
1. **Local Tier (MinIO)**: High-frequency hourly backups (`0 * * * *`) kept within the local cluster network for fast restores.
2. **Offsite Tier (Cloudflare R2)**: Offsite disaster recovery snapshots (`30 * * * *`) sent to S3-compatible cloud object storage.

```
+-------------------------------------------------------------------------------+
|                               Kubernetes Workload                             |
|                                       |                                       |
|                                (VolumeSnapshot)                               |
|                                       v                                       |
|                            VolSync Mover (Kopia)                              |
|                             /               \                                 |
|               (Local Hourly)                 (Offsite Disaster Recovery)      |
|                     v                                     v                   |
|       MinIO (In-Cluster S3)                     Cloudflare R2 (Offsite)       |
|    Bucket: volsync                               Bucket: homeops-volsync-67   |
|    Prefix: /${APP}                               Prefix: /${APP}              |
+-------------------------------------------------------------------------------+
```

---

## Single Shared Bucket vs. Dedicated Per-App Buckets

The cluster uses a **single shared bucket with application prefixes** (`volsync/${APP}`) for both local and offsite repositories:
* **Local**: `s3:http://minio.storage.svc.cluster.local:9000/volsync/${APP}`
* **Offsite**: `s3:https://${S3_ENDPOINT}/homeops-volsync-67/${APP}`

### Why a Single Bucket is Preferred in MinIO / Static S3 Setups

1. **Zero-Touch GitOps Provisioning**: Kopia automatically creates repository subpaths/prefixes under an existing bucket. When a new application is deployed, backups work immediately without requiring manual `mc mb` commands or updating `minio-bucket-job.yaml`.
2. **Consistency**: Local and offsite storage follow the exact same URL pattern (`bucket/app-name`).
3. **No `NoSuchBucket` Failures**: Prevents mover pods from failing when initializing repositories for new services.
4. **Cloud Provider Limits**: Cloud providers (Cloudflare R2, AWS S3, Backblaze B2) impose soft or hard account bucket limits; managing dozens of individual buckets adds administrative and billing overhead.

---

## When Dedicated Buckets are Better (e.g., Rook-Ceph with OBC)

While a single bucket is ideal for self-hosted MinIO and cloud object storage, **dedicated per-application buckets are significantly better when using Rook-Ceph with `ObjectBucketClaim` (OBC)**:

### 1. Dynamic Automated Provisioning (`ObjectBucketClaim`)
With Rook-Ceph, Kubernetes supports the `objectbucket.io` API. An application includes an `ObjectBucketClaim`:
```yaml
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  name: ${APP}-volsync
spec:
  bucketName: ${APP}-volsync
  storageClassName: ceph-bucket-retain
```
The Ceph bucket controller automatically provisions the bucket in Ceph RadosGW (RGW), generates dedicated access and secret keys, and injects them directly into a namespace-local Secret. This completely eliminates the manual creation issue present in basic MinIO deployments.

### 2. Strict Tenant Isolation & Least-Privilege Security
* In a shared bucket setup, all applications use credentials that grant access to the entire bucket (and therefore other apps' backup data).
* With Ceph OBC, each application receives dedicated credentials that **only grant read/write access to its own bucket**. If an application or its mover container is compromised, the attacker cannot read, tamper with, or delete backup snapshots of other services.

### 3. Granular Quotas & Resource Governance
* Ceph allows setting maximum storage capacity and object count limits per bucket.
* A runaway application or backup loop cannot exhaust the entire object storage pool, protecting other critical services.

### 4. Custom Lifecycle & Retention Policies
* Different applications have varying compliance and retention requirements (e.g., databases requiring 1-year retention vs. temporary caches requiring 7 days).
* Individual buckets allow applying Ceph RGW lifecycle rules (expiration, non-current version expiration, and tiering) per application without complex prefix matching.

### 5. Ceph Performance & Bucket Index Scaling
* Ceph RGW stores bucket metadata in an index pool (OMAP objects). Very large single buckets with millions of objects can experience bucket index lock contention during heavy concurrent write/sync cycles.
* Distributing workloads across separate buckets spreads the index objects across multiple OSDs, improving overall cluster I/O throughput.

---

## Summary Comparison

| Requirement | Single Bucket + Prefix (`volsync/${APP}`) | Dedicated Buckets via Ceph OBC (`${APP}-volsync`) |
| :--- | :--- | :--- |
| **Target Storage Backend** | **MinIO, Cloudflare R2, AWS S3** | **Rook-Ceph (RGW with `lib-bucket-provisioner`)** |
| **New App Provisioning** | Automatic (handled by Kopia prefix) | Automatic (handled by Ceph OBC Controller) |
| **Credential Scoping** | Shared backup credentials | Per-app isolated credentials |
| **Storage Quotas** | Cluster/bucket level only | Granular per-app bucket quotas |
| **Lifecycle Policies** | Global bucket policy | Granular per-app lifecycle rules |
| **Operational Overhead** | Lowest for MinIO & Cloud Object Storage | Requires Rook-Ceph Operator + RGW setup |
