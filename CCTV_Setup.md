
# 📡 Using Sparsh CCTV Camera in SemanticEdge (RTSP Integration Guide)

## Overview

This document explains how a **real Sparsh IP CCTV camera** is integrated into the **SemanticEdge / SADAKSH pipeline** for real-time AI-based traffic analysis.

Instead of using a webcam or video file, we use a **live RTSP stream from an industrial CCTV camera**, which is the standard approach in real-world surveillance systems.

---

# 🧠 System Architecture

```text
Sparsh IP Camera (Ethernet)
        │
        ▼
     RTSP Stream
        │
        ▼
OpenCV VideoCapture (FFmpeg backend)
        │
        ▼
YOLOv8 Detection
        │
        ▼
ByteTrack Tracking
        │
        ▼
CSV Logging / Database
````

---

# ⚙️ Step 1 — Discover Camera IP (Direct Ethernet Setup)

## CCTV IP Discovery via Direct Ethernet (Mac)

### Objective

Identify IP address of an IP camera connected directly to a laptop (no router).

---

### 1. Physical Setup

* Connect camera to laptop using RJ45 cable via Ethernet adapter/dock
* Power ON camera
* Verify Ethernet link (LED ON)

---

### 2. Identify Active Ethernet Interface

```bash
ifconfig
networksetup -listallhardwareports
```

Example:

```
interface: en5
status: active
inet 192.168.1.10
```

---

### 3. Assign Manual IP to Laptop

Set manually:

```
IP Address: 192.168.1.10
Subnet Mask: 255.255.255.0
```

---

### 4. Capture ARP Traffic

```bash
sudo tcpdump -i en5 arp
```

Reconnect cable.

---

### 5. Extract Camera IP

Example:

```
ARP, Announcement 192.168.128.10
```

👉 Camera IP = `192.168.128.10`

---

### 6. Match Subnet

Set laptop IP:

```
192.168.128.20
```

---

### 7. Verify

```bash
ping 192.168.128.10
```

---

### 8. Access Camera UI

```
http://192.168.128.10
```

Example:

```
http://192.168.128.10/doc/page/main.html
```

---

# 🔍 Step 2 — Understanding Camera Interface

The browser URL:

```
http://192.168.128.10/doc/page/main.html
```

⚠️ This is **NOT a video stream**

It is only a **web dashboard UI** that internally uses:

```text
WebSocket + WASM decoding
```

👉 Cannot be used directly in OpenCV.

---

# 📡 Step 3 — Enable and Extract RTSP Stream

Navigate:

```
Config → Network → Net Service → RTSP
```

### Observed Configuration

```
RTSP: Enabled
Port: 554
```

### URL Template

```
rtsp://<ip>:<port>/avstream/channel=<1>/stream=<0-mainstream;1-substream>.sdp
```

---

# 🎯 Final RTSP URLs

## Main Stream (High Quality)

```
rtsp://192.168.128.10:554/avstream/channel=1/stream=0.sdp
```

## Sub Stream (Recommended for AI)

```
rtsp://192.168.128.10:554/avstream/channel=1/stream=1.sdp
```

---

# 🔐 Authentication (if required)

```
rtsp://username:password@192.168.128.10:554/avstream/channel=1/stream=1.sdp
```

Example:

```
rtsp://admin:admin123@192.168.128.10:554/avstream/channel=1/stream=1.sdp
```

---

# 🧪 Step 4 — Test Stream in VLC

Before integrating:

```
VLC → Media → Open Network Stream
```

Paste:

```
rtsp://admin:password@192.168.128.10:554/avstream/channel=1/stream=1.sdp
```

👉 If video plays → pipeline is valid

---

# 🧠 Step 5 — Fix Codec for Performance (IMPORTANT)

By default, camera was using:

```
H.265 (HEVC)
```

This caused:

* Lag
* Frame drops
* Errors like:

  ```
  Could not find ref with POC
  ```

### ✅ Solution

Go to:

```
Config → Encode
```

Change:

```
H.265 → H.264
```

---

# ⚡ Step 6 — Optimize Camera Settings

For real-time AI:

| Setting    | Value                |
| ---------- | -------------------- |
| Stream     | Substream (stream=1) |
| Resolution | 640×360 / 720p       |
| FPS        | 15–20                |
| Codec      | H.264                |

---

# 💻 Step 7 — Integrate with Project

Run:

```bash
python src/main.py \
--source "rtsp://admin:admin123@192.168.128.10:554/avstream/channel=1/stream=1.sdp"
```

---

# ⚙️ Step 8 — Code Modifications (OpenCV Optimization)

## 1. Use FFmpeg backend

```python
cap = cv2.VideoCapture(source, cv2.CAP_FFMPEG)
```

---

## 2. Reduce buffer lag

```python
cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
```

---

## 3. Force TCP (stable streaming)

```python
import os
os.environ["OPENCV_FFMPEG_CAPTURE_OPTIONS"] = "rtsp_transport;tcp"
```

---

## 4. Frame skipping (real-time effect)

```python
ret, frame = cap.read()

for _ in range(2):
    cap.grab()
```

---

## 5. Resize before inference

```python
frame = cv2.resize(frame, (640, 360))
```

---

# 🚀 Step 9 — Run Pipeline

```bash
source .venv/bin/activate

python src/main.py \
--source "rtsp://admin:admin123@192.168.128.10:554/avstream/channel=1/stream=1.sdp" \
--conf 0.5
```

---

# 📊 Expected Output

* Real-time detection
* Smooth tracking
* CSV logs generated:

```
output/logs/detection_log.csv
```

---

# 🧠 Key Learnings

## ❌ What DOESN’T work

* Browser URL (`/main.html`)
* WebSocket streams
* HEVC without hardware decoding

---

## ✅ What WORKS (Industry Standard)

```text
RTSP + H.264 + OpenCV + YOLO
```

---

# 🧠 Production Insight

Real surveillance systems follow:

```text
Multiple IP Cameras
        │
        ▼
RTSP Streams
        │
        ▼
Parallel Processing Pipelines
        │
        ▼
Central Database / Dashboard
```

---

# 🔥 Final Conclusion

Using a **real Sparsh CCTV camera** transforms this project from:

```text
Academic Demo ❌
```

to:

```text
Real-World Edge AI System ✅
```

This setup is directly scalable to:

* Smart cities
* Traffic monitoring
* Surveillance analytics
* Industrial safety systems

---

# 🚀 Next Scope (Future Work)

* Multi-camera ingestion
* Async frame pipelines
* Edge deployment (Jetson / Radxa)
* Real-time dashboard (Web UI)
* Event-based alert system

---

**This document serves as a practical guide for integrating real-world CCTV infrastructure into AI-based video analytics systems.**

```
```
