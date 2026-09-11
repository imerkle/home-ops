import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';
import crypto from 'k6/crypto';

// Custom Prometheus metrics
export const cacheHitRate = new Rate('k6_thumbnail_cache_hit_rate');
export const singleFlightSuccess = new Rate('k6_thumbnail_singleflight_success');
export const batchLatency = new Trend('k6_thumbnail_batch_duration', true);
export const cacheHitLatency = new Trend('k6_thumbnail_cache_hit_duration', true);
export const cacheMissLatency = new Trend('k6_thumbnail_cache_miss_duration', true);
export const totalImagesProcessed = new Counter('k6_thumbnail_images_processed_total');

const TARGET_URL = (__ENV.TARGET_URL || 'http://thumbnail-service:3000').replace(/\/$/, '');
const CATALOG_SIZE = 120; // 120 deterministic images in cache pool
const BATCH_SIZE_MIN = 20;
const BATCH_SIZE_MAX = 50;

const DIMENSIONS = [
  { w: 200, h: 200, size: 'small' },
  { w: 300, h: 300, size: 'small' },
  { w: 400, h: 300, size: 'medium' },
  { w: 600, h: 600, size: 'medium' },
  { w: 800, h: 600, size: 'large' },
  { w: 1200, h: 800, size: 'large' },
];

const CATEGORIES = [
  'architecture', 'nature', 'technology', 'cityscape', 
  'astronomy', 'portraits', 'cuisine', 'textures',
  'animals', 'automotive', 'interiors', 'landscapes'
];

// Helper to hash URLs to SHA-256 hex string
function hashUrl(url) {
  return crypto.sha256(url, 'hex');
}

// 1. Programmatic deterministic catalog item (for cache hits)
function generateCatalogItem(index) {
  const dim = DIMENSIONS[index % DIMENSIONS.length];
  const cat = CATEGORIES[index % CATEGORIES.length];
  const url = (index % 2 === 0)
    ? `https://placehold.co/${dim.w}x${dim.h}.jpg?text=catalog_${cat}_${index}`
    : `https://picsum.photos/seed/cat_${cat}_${index}/${dim.w}/${dim.h}`;
  const hash = hashUrl(url);
  return { url, hash, size: dim.size, dim };
}

// 2. Programmatic dynamic item (for cache misses)
function generateDynamicItem(vu, iter, salt) {
  const seed = `${vu}_${iter}_${salt}_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
  const dim = DIMENSIONS[(vu + iter + salt) % DIMENSIONS.length];
  const url = (iter % 2 === 0)
    ? `https://placehold.co/${dim.w}x${dim.h}.jpg?text=dyn_${seed}`
    : `https://picsum.photos/seed/dyn_${seed}/${dim.w}/${dim.h}`;
  const hash = hashUrl(url);
  return { url, hash, size: dim.size, dim };
}

// Pre-build the programmatic catalog in memory for all VUs
const CATALOG = [];
for (let i = 0; i < CATALOG_SIZE; i++) {
  CATALOG.push(generateCatalogItem(i));
}

const BUILD_ID = __ENV.BUILD_ID || 'latest';

export const options = {
  tags: {
    testid: 'thumbnail-service',
    app: 'thumbnail-service',
    build: BUILD_ID,
  },
  scenarios: {
    // Scenario 1: API Batch Resolution (Ramping to 40 VUs, 20-50 URLs per batch)
    api_batch_resolve: {
      executor: 'ramping-vus',
      startVUs: 2,
      stages: [
        { duration: '15s', target: 20 },
        { duration: '30s', target: 40 },
        { duration: '15s', target: 0 },
      ],
      gracefulStop: '5s',
      exec: 'testBatchApi',
    },

    // Scenario 2: Cache HIT Fast Path (High Concurrency S3 Streaming, up to 80 VUs)
    cache_hits: {
      executor: 'ramping-vus',
      startVUs: 5,
      stages: [
        { duration: '15s', target: 40 },
        { duration: '30s', target: 80 },
        { duration: '15s', target: 0 },
      ],
      gracefulStop: '5s',
      exec: 'testCacheHits',
    },

    // Scenario 3: Cache MISS & On-demand Resize (5 new resizes/sec for 50s = ~250 image resizes)
    cache_miss_resize: {
      executor: 'constant-arrival-rate',
      rate: 5,
      timeUnit: '1s',
      duration: '50s',
      preAllocatedVUs: 8,
      maxVUs: 25,
      gracefulStop: '5s',
      exec: 'testCacheMiss',
    },

    // Scenario 4: Thundering Herd Stampede (30 simultaneous VUs on exact same uncached URL)
    thundering_herd: {
      executor: 'shared-iterations',
      vus: 30,
      iterations: 30,
      startTime: '20s',
      maxDuration: '15s',
      gracefulStop: '5s',
      exec: 'testThunderingHerd',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],
    'http_req_duration{scenario:cache_hits}': ['p(95)<1000'],
    'http_req_duration{scenario:api_batch_resolve}': ['p(95)<2000'],
    'http_req_duration{scenario:cache_miss_resize}': ['p(95)<5000'],
  },
};

// Setup: Pre-warm a portion of the catalog into S3/MinIO
export function setup() {
  for (let i = 0; i < Math.min(CATALOG.length, 30); i++) {
    const item = CATALOG[i];
    const thumbUrl = `${TARGET_URL}/thumb/${item.hash}_${item.size}.jpg?url=${encodeURIComponent(item.url)}`;
    http.get(thumbUrl, { timeout: '15s' });
  }
}

// 1. Test POST /api/thumbnail/batch with programmatic batch payloads
export function testBatchApi() {
  const batchSize = Math.floor(Math.random() * (BATCH_SIZE_MAX - BATCH_SIZE_MIN + 1)) + BATCH_SIZE_MIN;
  const imageUrls = [];

  // Mix 60% catalog items (cache hits) and 40% dynamic items
  for (let i = 0; i < batchSize; i++) {
    if (Math.random() < 0.6) {
      const catItem = CATALOG[Math.floor(Math.random() * CATALOG.length)];
      imageUrls.push(catItem.url);
    } else {
      const dynItem = generateDynamicItem(__VU, __ITER, i);
      imageUrls.push(dynItem.url);
    }
  }

  const payload = JSON.stringify({ image_urls: imageUrls });
  const params = {
    headers: { 'Content-Type': 'application/json' },
    tags: { name: 'POST /api/thumbnail/batch' },
  };

  const start = Date.now();
  const res = http.post(`${TARGET_URL}/api/thumbnail/batch`, payload, params);
  batchLatency.add(Date.now() - start);
  totalImagesProcessed.add(imageUrls.length);

  check(res, {
    'batch status is 200': (r) => r.status === 200,
    'batch has results': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body && body.results && Object.keys(body.results).length > 0;
      } catch (e) {
        return false;
      }
    },
  });

  sleep(0.08);
}

// 2. Test GET /thumb/{hash}_{size}.jpg (High-throughput Cache HIT Fast Path)
export function testCacheHits() {
  const item = CATALOG[Math.floor(Math.random() * CATALOG.length)];
  const thumbUrl = `${TARGET_URL}/thumb/${item.hash}_${item.size}.jpg?url=${encodeURIComponent(item.url)}`;

  const params = {
    tags: { name: 'GET /thumb/{hash}_{size}.jpg [HIT]' },
  };

  const start = Date.now();
  const res = http.get(thumbUrl, params);
  cacheHitLatency.add(Date.now() - start);

  const isHit = res.headers['X-Cache'] === 'HIT';
  cacheHitRate.add(isHit ? 1 : 0);

  check(res, {
    'hit status is 200': (r) => r.status === 200,
    'hit content-type is image/jpeg': (r) => r.headers['Content-Type'] === 'image/jpeg',
  });

  sleep(0.02);
}

// 3. Test GET /thumb/{hash}_{size}.jpg (Programmatic Uncached Image Resize)
export function testCacheMiss() {
  const item = generateDynamicItem(__VU, __ITER, Math.floor(Math.random() * 10000));
  const thumbUrl = `${TARGET_URL}/thumb/${item.hash}_${item.size}.jpg?url=${encodeURIComponent(item.url)}`;

  const params = {
    timeout: '15s',
    tags: { name: 'GET /thumb/{hash}_{size}.jpg [MISS]' },
  };

  const start = Date.now();
  const res = http.get(thumbUrl, params);
  cacheMissLatency.add(Date.now() - start);

  const isMiss = res.headers['X-Cache'] === 'MISS';
  cacheHitRate.add(isMiss ? 0 : 1);

  check(res, {
    'miss status is 200': (r) => r.status === 200,
    'miss content-type is image/jpeg': (r) => r.headers['Content-Type'] === 'image/jpeg',
    'miss returns image bytes': (r) => r.body && r.body.length > 0,
  });
}

// 4. Test Thundering Herd Stampede (30 VUs hitting the exact same uncached URL)
export function testThunderingHerd() {
  const windowBucket = Math.floor(Date.now() / 15000);
  const stampedeUrl = `https://placehold.co/450x450.jpg?text=stampede_${windowBucket}`;
  const hash = hashUrl(stampedeUrl);
  const thumbUrl = `${TARGET_URL}/thumb/${hash}_small.jpg?url=${encodeURIComponent(stampedeUrl)}`;

  const params = {
    timeout: '15s',
    tags: { name: 'GET /thumb/stampede [SINGLEFLIGHT]' },
  };

  const res = http.get(thumbUrl, params);
  const ok = res.status === 200;
  singleFlightSuccess.add(ok ? 1 : 0);

  check(res, {
    'stampede status is 200': (r) => r.status === 200,
    'stampede returns valid jpeg': (r) => r.headers['Content-Type'] === 'image/jpeg',
  });
}

// Default fallback function when CLI overrides scenarios with --duration or --vus
export default function () {
  testCacheHits();
  testBatchApi();
}

