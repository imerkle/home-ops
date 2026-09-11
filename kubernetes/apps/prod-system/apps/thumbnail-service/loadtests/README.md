# Thumbnail Service Load Testing Suite

This directory contains a declarative k6 load test suite for `thumbnail-service`.

## Scenarios

1. **`api_batch_resolve`** (Ramps up to 20 VUs): Tests `POST /api/thumbnail/batch` with arrays of URLs to benchmark Redis MGET and gRPC-gateway serialization.
2. **`cache_hits`** (Ramps up to 30 VUs): Tests `GET /thumb/{hash}_small.jpg` expecting `X-Cache: HIT` to benchmark S3/MinIO byte delivery.
3. **`cache_miss_resize`** (Constant 2 req/s): Tests uncached image generation, exercising the full pipeline: origin download, image decode, resize, S3 upload, and Redis caching.
4. **`thundering_herd`** (15 concurrent VUs): Concurrently requests the exact same uncached URL to verify `singleflight.Group` deduplication.

## Execution

### Run declaratively in Kubernetes (via k6-operator)

```bash
# Launch test run
kubectl apply -k ./kubernetes/apps/prod-system/apps/thumbnail-service/loadtests/

# Check status
kubectl get testrun -n prod-system thumbnail-service-loadtest

# Watch logs of runners
kubectl logs -n prod-system -l k6_cr=thumbnail-service-loadtest --tail=50

# Cleanup after completion
kubectl delete -k ./kubernetes/apps/prod-system/apps/thumbnail-service/loadtests/
```

### Run locally via k6 CLI

```bash
TARGET_URL="https://thumb.x3y.space" \
K6_PROMETHEUS_RW_SERVER_URL="https://prometheus.x3y.space/api/v1/write" \
k6 run -o experimental-prometheus-rw test.js
```

## Monitoring

Metrics stream in real-time to the cluster Prometheus and are visualized on the Grafana dashboard:
[https://grafana.x3y.space/d/ccbb2351-2ae2-462f-ae0e-f2c893ad1028/k6-prometheus](https://grafana.x3y.space/d/ccbb2351-2ae2-462f-ae0e-f2c893ad1028/k6-prometheus?var-testrun=thumbnail-service-loadtest)
