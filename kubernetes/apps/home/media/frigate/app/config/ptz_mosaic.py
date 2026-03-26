#!/usr/bin/env python3
"""Experimental PTZ mosaic stream for Frigate.

Builds a pseudo-birdseye canvas for a single PTZ camera:
- Current pan/tilt tile is always live.
- Other tiles are the last unique frame seen for those angles.

Uniqueness is determined by both:
- Angle proximity derived from configured pan/tilt ranges and base step.
- Visual similarity via a perceptual hash (dHash) distance threshold.
"""

from __future__ import annotations

import json
import math
import os
import threading
import time
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Dict, Optional, Tuple
from urllib.error import URLError
from urllib.request import urlopen

import cv2
import numpy as np


def env_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def env_int(name: str, default: int) -> int:
    value = os.getenv(name)
    if value is None:
        return default
    try:
        return int(value)
    except ValueError:
        return default


def env_float(name: str, default: float) -> float:
    value = os.getenv(name)
    if value is None:
        return default
    try:
        return float(value)
    except ValueError:
        return default


@dataclass
class Config:
    camera_name: str
    rtsp_url: str
    frigate_api: str
    bind_host: str
    bind_port: int
    request_timeout_sec: float
    sample_interval_sec: float
    stream_fps: int
    pan_range_deg: float
    tilt_range_deg: float
    base_step_deg: float
    pan_unique_factor: float
    tilt_unique_factor: float
    hash_distance_threshold: int
    tile_width: int
    tile_height: int
    jpeg_quality: int
    tilt_invert: bool
    max_cells: int

    pan_bins: int
    tilt_bins: int
    pan_step_deg: float
    tilt_step_deg: float
    pan_unique_deg: float
    tilt_unique_deg: float

    @staticmethod
    def load() -> "Config":
        pan_range = env_float("PTZ_MOSAIC_PAN_RANGE_DEG", 360.0)
        tilt_range = env_float("PTZ_MOSAIC_TILT_RANGE_DEG", 114.0)
        base_step = max(env_float("PTZ_MOSAIC_BASE_STEP_DEG", 10.0), 0.1)

        pan_bins = max(1, int(math.ceil(pan_range / base_step)))
        tilt_bins = max(1, int(math.ceil(tilt_range / base_step)))

        pan_step = pan_range / pan_bins
        tilt_step = tilt_range / tilt_bins

        pan_unique_factor = env_float("PTZ_MOSAIC_PAN_UNIQUE_FACTOR", 0.70)
        tilt_unique_factor = env_float("PTZ_MOSAIC_TILT_UNIQUE_FACTOR", 0.70)

        max_cells_default = pan_bins * tilt_bins

        return Config(
            camera_name=os.getenv("PTZ_MOSAIC_CAMERA_NAME", "garage"),
            rtsp_url=os.getenv("PTZ_MOSAIC_RTSP_URL", "rtsp://127.0.0.1:8554/garage_main"),
            frigate_api=os.getenv("PTZ_MOSAIC_FRIGATE_API", "http://127.0.0.1:5000").rstrip("/"),
            bind_host=os.getenv("PTZ_MOSAIC_BIND_HOST", "0.0.0.0"),
            bind_port=env_int("PTZ_MOSAIC_BIND_PORT", 8090),
            request_timeout_sec=env_float("PTZ_MOSAIC_REQUEST_TIMEOUT_SEC", 2.0),
            sample_interval_sec=env_float("PTZ_MOSAIC_SAMPLE_INTERVAL_SEC", 1.0),
            stream_fps=max(1, env_int("PTZ_MOSAIC_STREAM_FPS", 1)),
            pan_range_deg=pan_range,
            tilt_range_deg=tilt_range,
            base_step_deg=base_step,
            pan_unique_factor=pan_unique_factor,
            tilt_unique_factor=tilt_unique_factor,
            hash_distance_threshold=max(1, env_int("PTZ_MOSAIC_HASH_DISTANCE", 10)),
            tile_width=max(48, env_int("PTZ_MOSAIC_TILE_WIDTH", 80)),
            tile_height=max(27, env_int("PTZ_MOSAIC_TILE_HEIGHT", 45)),
            jpeg_quality=max(50, min(100, env_int("PTZ_MOSAIC_JPEG_QUALITY", 80))),
            tilt_invert=env_bool("PTZ_MOSAIC_TILT_INVERT", False),
            max_cells=max(1, env_int("PTZ_MOSAIC_MAX_CELLS", max_cells_default)),
            pan_bins=pan_bins,
            tilt_bins=tilt_bins,
            pan_step_deg=pan_step,
            tilt_step_deg=tilt_step,
            pan_unique_deg=max(0.5, pan_step * pan_unique_factor),
            tilt_unique_deg=max(0.5, tilt_step * tilt_unique_factor),
        )


@dataclass
class MosaicCell:
    pan_deg: float
    tilt_deg: float
    hash_value: int
    thumb: np.ndarray
    last_seen: float
    hits: int = 1


class State:
    def __init__(self, cfg: Config) -> None:
        self.cfg = cfg
        self.lock = threading.Lock()
        self.frame_lock = threading.Lock()

        self.cells: Dict[int, MosaicCell] = {}
        self.next_cell_id = 1

        self.latest_frame: Optional[np.ndarray] = None
        self.latest_frame_ts = 0.0

        self.live_pan_deg: Optional[float] = None
        self.live_tilt_deg: Optional[float] = None
        self.live_thumb: Optional[np.ndarray] = None

        self.latest_jpeg = self._blank_mosaic_jpeg("Waiting for first PTZ frame")
        self.last_error: Optional[str] = None

        self.stop_event = threading.Event()

    def _blank_mosaic_jpeg(self, message: str) -> bytes:
        img = np.full(
            (self.cfg.tilt_bins * self.cfg.tile_height, self.cfg.pan_bins * self.cfg.tile_width, 3),
            20,
            dtype=np.uint8,
        )
        cv2.putText(
            img,
            message,
            (10, 28),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.8,
            (200, 200, 200),
            2,
            cv2.LINE_AA,
        )
        ok, encoded = cv2.imencode(
            ".jpg", img, [int(cv2.IMWRITE_JPEG_QUALITY), self.cfg.jpeg_quality]
        )
        return encoded.tobytes() if ok else b""


def angle_delta_wrapped(a_deg: float, b_deg: float, period_deg: float) -> float:
    raw = abs(a_deg - b_deg)
    return min(raw, period_deg - raw)


def circular_blend_deg(current_deg: float, new_deg: float, alpha: float) -> float:
    a = math.radians(current_deg)
    b = math.radians(new_deg)
    x = (1 - alpha) * math.cos(a) + alpha * math.cos(b)
    y = (1 - alpha) * math.sin(a) + alpha * math.sin(b)
    return (math.degrees(math.atan2(y, x)) + 360.0) % 360.0


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def dhash_64(image_bgr: np.ndarray) -> int:
    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    resized = cv2.resize(gray, (9, 8), interpolation=cv2.INTER_AREA)
    diff = resized[:, 1:] > resized[:, :-1]

    value = 0
    for bit in diff.flatten():
        value = (value << 1) | int(bit)
    return value


def hamming_distance(a: int, b: int) -> int:
    return (a ^ b).bit_count()


def parse_pan_tilt_norm(payload: object) -> Optional[Tuple[float, float]]:
    queue = [payload]
    while queue:
        node = queue.pop(0)

        if isinstance(node, dict):
            pantilt = node.get("PanTilt") or node.get("panTilt") or node.get("pantilt")
            if isinstance(pantilt, dict):
                x = pantilt.get("x")
                y = pantilt.get("y")
                if x is not None and y is not None:
                    try:
                        return float(x), float(y)
                    except (TypeError, ValueError):
                        pass

            pan = node.get("pan")
            tilt = node.get("tilt")
            if pan is not None and tilt is not None:
                try:
                    return float(pan), float(tilt)
                except (TypeError, ValueError):
                    pass

            for value in node.values():
                if isinstance(value, (dict, list)):
                    queue.append(value)

        elif isinstance(node, list):
            for item in node:
                if isinstance(item, (dict, list)):
                    queue.append(item)

    return None


def fetch_ptz_position_deg(cfg: Config) -> Optional[Tuple[float, float]]:
    endpoints = [
        f"{cfg.frigate_api}/api/{cfg.camera_name}/ptz/info",
        f"{cfg.frigate_api}/{cfg.camera_name}/ptz/info",
    ]

    payload = None
    for endpoint in endpoints:
        try:
            with urlopen(endpoint, timeout=cfg.request_timeout_sec) as response:
                if response.status != 200:
                    continue
                payload = json.loads(response.read().decode("utf-8"))
                break
        except (URLError, TimeoutError, json.JSONDecodeError):
            continue

    if payload is None:
        return None

    norm = parse_pan_tilt_norm(payload)
    if norm is None:
        return None

    pan_value, tilt_value = norm

    # Most cameras report normalized ONVIF coordinates in [-1, 1].
    if -1.0 <= pan_value <= 1.0 and -1.0 <= tilt_value <= 1.0:
        pan_norm = clamp(pan_value, -1.0, 1.0)
        tilt_norm = clamp(tilt_value, -1.0, 1.0)

        pan_deg = ((pan_norm + 1.0) / 2.0) * cfg.pan_range_deg
        pan_deg = pan_deg % cfg.pan_range_deg

        tilt_ratio = (tilt_norm + 1.0) / 2.0
        if cfg.tilt_invert:
            tilt_ratio = 1.0 - tilt_ratio
        tilt_deg = clamp(tilt_ratio * cfg.tilt_range_deg, 0.0, cfg.tilt_range_deg)

        return pan_deg, tilt_deg

    # Some integrations expose direct angle degrees.
    if 0.0 <= pan_value <= cfg.pan_range_deg and 0.0 <= tilt_value <= cfg.tilt_range_deg:
        return pan_value % cfg.pan_range_deg, tilt_value

    return None


def frame_capture_loop(state: State) -> None:
    cfg = state.cfg
    capture: Optional[cv2.VideoCapture] = None

    while not state.stop_event.is_set():
        if capture is None or not capture.isOpened():
            # Avoid forcing a backend; container builds vary in OpenCV backend support.
            capture = cv2.VideoCapture(cfg.rtsp_url)
            if not capture.isOpened():
                with state.lock:
                    state.last_error = f"Unable to open RTSP source: {cfg.rtsp_url}"
                time.sleep(2.0)
                continue

        ok, frame = capture.read()
        if not ok or frame is None:
            capture.release()
            capture = None
            with state.lock:
                state.last_error = "RTSP stream read failed, reconnecting"
            time.sleep(1.0)
            continue

        with state.frame_lock:
            state.latest_frame = frame
            state.latest_frame_ts = time.time()

        time.sleep(0.02)

    if capture is not None:
        capture.release()


def choose_matching_cell_id(
    cells: Dict[int, MosaicCell], pan_deg: float, tilt_deg: float, frame_hash: int, cfg: Config
) -> Optional[int]:
    best_id: Optional[int] = None
    best_score = 1e9

    for cell_id, cell in cells.items():
        pan_delta = angle_delta_wrapped(cell.pan_deg, pan_deg, cfg.pan_range_deg)
        tilt_delta = abs(cell.tilt_deg - tilt_deg)

        if pan_delta > cfg.pan_unique_deg or tilt_delta > cfg.tilt_unique_deg:
            continue

        hash_delta = hamming_distance(cell.hash_value, frame_hash)
        if hash_delta > cfg.hash_distance_threshold:
            continue

        score = (
            pan_delta / cfg.pan_unique_deg
            + tilt_delta / cfg.tilt_unique_deg
            + hash_delta / cfg.hash_distance_threshold
        )
        if score < best_score:
            best_id = cell_id
            best_score = score

    return best_id


def upsert_cell(state: State, pan_deg: float, tilt_deg: float, frame: np.ndarray) -> None:
    cfg = state.cfg
    thumb = cv2.resize(frame, (cfg.tile_width, cfg.tile_height), interpolation=cv2.INTER_AREA)
    frame_hash = dhash_64(thumb)
    now = time.time()

    cell_id = choose_matching_cell_id(state.cells, pan_deg, tilt_deg, frame_hash, cfg)

    if cell_id is not None:
        cell = state.cells[cell_id]
        alpha = 0.35
        cell.pan_deg = circular_blend_deg(cell.pan_deg, pan_deg, alpha)
        cell.tilt_deg = (1.0 - alpha) * cell.tilt_deg + alpha * tilt_deg
        cell.hash_value = frame_hash
        cell.thumb = thumb
        cell.last_seen = now
        cell.hits += 1
    else:
        if len(state.cells) >= cfg.max_cells:
            oldest_id = min(state.cells, key=lambda cid: state.cells[cid].last_seen)
            state.cells.pop(oldest_id, None)

        state.cells[state.next_cell_id] = MosaicCell(
            pan_deg=pan_deg,
            tilt_deg=tilt_deg,
            hash_value=frame_hash,
            thumb=thumb,
            last_seen=now,
        )
        state.next_cell_id += 1

    state.live_pan_deg = pan_deg
    state.live_tilt_deg = tilt_deg
    state.live_thumb = thumb


def draw_grid(canvas: np.ndarray, cfg: Config) -> None:
    h, w = canvas.shape[:2]
    line_color = (42, 42, 42)

    for col in range(1, cfg.pan_bins):
        x = col * cfg.tile_width
        cv2.line(canvas, (x, 0), (x, h), line_color, 1)

    for row in range(1, cfg.tilt_bins):
        y = row * cfg.tile_height
        cv2.line(canvas, (0, y), (w, y), line_color, 1)


def render_mosaic(state: State) -> bytes:
    cfg = state.cfg
    canvas = np.full(
        (cfg.tilt_bins * cfg.tile_height, cfg.pan_bins * cfg.tile_width, 3),
        16,
        dtype=np.uint8,
    )

    draw_grid(canvas, cfg)

    freshest_by_bin: Dict[Tuple[int, int], MosaicCell] = {}
    for cell in state.cells.values():
        pan_idx = int(cell.pan_deg / cfg.pan_step_deg) % cfg.pan_bins
        tilt_idx = min(cfg.tilt_bins - 1, int(cell.tilt_deg / cfg.tilt_step_deg))

        key = (pan_idx, tilt_idx)
        existing = freshest_by_bin.get(key)
        if existing is None or cell.last_seen > existing.last_seen:
            freshest_by_bin[key] = cell

    for (pan_idx, tilt_idx), cell in freshest_by_bin.items():
        x = pan_idx * cfg.tile_width
        y = tilt_idx * cfg.tile_height
        canvas[y : y + cfg.tile_height, x : x + cfg.tile_width] = cell.thumb

    if state.live_pan_deg is not None and state.live_tilt_deg is not None and state.live_thumb is not None:
        pan_idx = int(state.live_pan_deg / cfg.pan_step_deg) % cfg.pan_bins
        tilt_idx = min(cfg.tilt_bins - 1, int(state.live_tilt_deg / cfg.tilt_step_deg))

        x = pan_idx * cfg.tile_width
        y = tilt_idx * cfg.tile_height
        canvas[y : y + cfg.tile_height, x : x + cfg.tile_width] = state.live_thumb

        cv2.rectangle(
            canvas,
            (x + 1, y + 1),
            (x + cfg.tile_width - 2, y + cfg.tile_height - 2),
            (0, 255, 0),
            2,
        )
        cv2.putText(
            canvas,
            "LIVE",
            (x + 4, y + 16),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.45,
            (0, 255, 0),
            1,
            cv2.LINE_AA,
        )

    status = f"unique={len(state.cells)} pan={cfg.pan_range_deg:.0f} tilt={cfg.tilt_range_deg:.0f}"
    cv2.putText(
        canvas,
        status,
        (10, 18),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.5,
        (220, 220, 220),
        1,
        cv2.LINE_AA,
    )

    ok, encoded = cv2.imencode(
        ".jpg", canvas, [int(cv2.IMWRITE_JPEG_QUALITY), cfg.jpeg_quality]
    )
    if not ok:
        return b""
    return encoded.tobytes()


def processing_loop(state: State) -> None:
    cfg = state.cfg

    while not state.stop_event.is_set():
        started = time.time()

        with state.frame_lock:
            frame = None if state.latest_frame is None else state.latest_frame.copy()

        if frame is None:
            time.sleep(0.5)
            continue

        ptz = fetch_ptz_position_deg(cfg)
        if ptz is None:
            with state.lock:
                state.last_error = "Unable to read PTZ info from Frigate API"
            time.sleep(max(0.2, cfg.sample_interval_sec))
            continue

        pan_deg, tilt_deg = ptz

        with state.lock:
            upsert_cell(state, pan_deg, tilt_deg, frame)
            state.latest_jpeg = render_mosaic(state)
            state.last_error = None

        elapsed = time.time() - started
        sleep_for = max(0.0, cfg.sample_interval_sec - elapsed)
        time.sleep(sleep_for)


class MosaicRequestHandler(BaseHTTPRequestHandler):
    state: State = None  # type: ignore[assignment]

    def log_message(self, fmt: str, *args: object) -> None:  # noqa: A003
        return

    def do_GET(self) -> None:  # noqa: N802
        if self.path in {"/", "/healthz"}:
            with self.state.lock:
                payload = {
                    "status": "ok",
                    "unique_cells": len(self.state.cells),
                    "last_error": self.state.last_error,
                }
            body = json.dumps(payload).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if self.path == "/mosaic.jpg":
            with self.state.lock:
                frame = self.state.latest_jpeg
            self.send_response(200)
            self.send_header("Content-Type", "image/jpeg")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(frame)))
            self.end_headers()
            self.wfile.write(frame)
            return

        if self.path == "/mosaic.mjpg":
            self.send_response(200)
            self.send_header("Age", "0")
            self.send_header("Cache-Control", "no-cache, private")
            self.send_header("Pragma", "no-cache")
            self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
            self.end_headers()

            interval = 1.0 / max(1, self.state.cfg.stream_fps)
            try:
                while not self.state.stop_event.is_set():
                    with self.state.lock:
                        frame = self.state.latest_jpeg

                    self.wfile.write(b"--frame\r\n")
                    self.wfile.write(b"Content-Type: image/jpeg\r\n")
                    self.wfile.write(f"Content-Length: {len(frame)}\r\n\r\n".encode("utf-8"))
                    self.wfile.write(frame)
                    self.wfile.write(b"\r\n")
                    self.wfile.flush()

                    time.sleep(interval)
            except (BrokenPipeError, ConnectionResetError):
                return
            return

        self.send_response(404)
        self.end_headers()


def run_server(state: State) -> None:
    handler = MosaicRequestHandler
    handler.state = state

    server = ThreadingHTTPServer((state.cfg.bind_host, state.cfg.bind_port), handler)

    try:
        server.serve_forever(poll_interval=0.5)
    finally:
        state.stop_event.set()
        server.server_close()


def main() -> None:
    cfg = Config.load()
    state = State(cfg)

    capture_thread = threading.Thread(target=frame_capture_loop, args=(state,), daemon=True)
    process_thread = threading.Thread(target=processing_loop, args=(state,), daemon=True)

    capture_thread.start()
    process_thread.start()

    run_server(state)


if __name__ == "__main__":
    main()
