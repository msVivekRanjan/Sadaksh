# Sparsh CCTV Camera Integration Guide (RTSP → SemanticEdge / SADAKSH Pipeline)

## Purpose

This document describes how to connect a physical Sparsh IP CCTV camera to the SemanticEdge / SADAKSH AI pipeline for real-time traffic analysis, using a live RTSP stream instead of a webcam or a pre-recorded video file. This is the same approach used in production surveillance systems, so understanding it properly will help you on any future project that ingests live camera feeds.

Read this document top to bottom before touching any hardware. Each step depends on the one before it.

---

## 1. System Architecture

```
Sparsh IP Camera (Ethernet)
        |
        v
    RTSP Stream
        |
        v
OpenCV VideoCapture (FFmpeg backend)
        |
        v
   YOLOv8 Detection
        |
        v
  ByteTrack Tracking
        |
        v
 CSV Logging / Database
```

---

## 2. Discovering the Camera's IP Address (Direct Ethernet Connection)

Use this method when the camera is connected directly to your laptop with an RJ45 cable and no router is involved (e.g. lab bench setup).

### 2.1 Physical Setup

1. Connect the camera to your laptop using an RJ45 cable through a USB-C to Ethernet adapter/dock.
2. Power on the camera and confirm the Ethernet port LED is lit (link established).

### 2.2 Identify the Active Ethernet Interface

Open **Terminal** on your laptop and run:

```bash
ifconfig
networksetup -listallhardwareports
```

Look for the interface that shows `status: active` and has just come up after you plugged in the cable. Example:

```
interface: en5
status: active
inet 192.168.1.10
```

Note this interface name (e.g. `en5`) — you will use it in step 2.4.

### 2.3 Assign a Manual IP to Your Laptop

Go to **System Settings → Network → [your Ethernet adapter] → Details → TCP/IP**, set **Configure IPv4** to **Manually**, and enter:

```
IP Address: 192.168.1.10
Subnet Mask: 255.255.255.0
```

Click **OK / Apply**.

### 2.4 Capture ARP Traffic to Find the Camera's IP

In Terminal, run (replace `en5` with the interface name found in step 2.2):

```bash
sudo tcpdump -i en5 arp
```

Enter your laptop password when prompted. With the capture running, physically unplug and replug the camera's Ethernet cable. The camera will broadcast an ARP announcement that tcpdump will print, e.g.:

```
ARP, Announcement 192.168.128.10
```

The IP shown here is the **camera's IP address**. Press `Ctrl + C` to stop the capture once you have it.

### 2.5 Match Your Laptop to the Camera's Subnet

Go back to **System Settings → Network → [your Ethernet adapter] → Details → TCP/IP** and change the manual IP to match the camera's subnet (same first three octets, different last octet):

```
IP Address: 192.168.128.20
Subnet Mask: 255.255.255.0
```

Click **Apply**.

### 2.6 Verify Connectivity

```bash
ping 192.168.128.10
```

You should see replies with no packet loss. If you get "Request timeout," re-check steps 2.3–2.5.

### 2.7 Open the Camera's Web UI

In a browser, go to:

```
http://192.168.128.10
```

You will typically be redirected to a dashboard page such as:

```
http://192.168.128.10/doc/page/main.html
```

Log in with the camera's admin credentials (default credentials are usually printed on the camera body or in the product manual).

---

## 3. Understanding the Camera's Web Interface

The dashboard at `/doc/page/main.html` is **not a video stream** — it is a browser UI that decodes video internally using WebSocket + WASM. This UI cannot be consumed by OpenCV or any RTSP client. Its only purpose here is to let you access the camera's **configuration menus**, which is what step 4 uses it for.

---

## 4. Enabling and Extracting the RTSP Stream

Inside the camera's web dashboard (from step 2.7), navigate to:

```
Config → Network → Net Service → RTSP
```

Confirm the following is set:

```
RTSP: Enabled
Port: 554
```

If RTSP is disabled, enable it and click **Save/Apply**. The camera may reboot after this change — wait until it comes back online before proceeding.

### RTSP URL Format

```
rtsp://<camera-ip>:<port>/avstream/channel=<channel-number>/stream=<0-mainstream;1-substream>.sdp
```

### Resulting URLs for This Camera

Main stream (high quality, higher bandwidth):
```
rtsp://192.168.128.10:554/avstream/channel=1/stream=0.sdp
```

Sub stream (recommended for AI inference — lower resolution, lower latency):
```
rtsp://192.168.128.10:554/avstream/channel=1/stream=1.sdp
```

### With Authentication (if the camera requires login on the stream)

```
rtsp://<username>:<password>@192.168.128.10:554/avstream/channel=1/stream=1.sdp
```

Example:
```
rtsp://admin:admin123@192.168.128.10:554/avstream/channel=1/stream=1.sdp
```

Do not commit real camera credentials to version control. Store them in a local `.env` file or pass them as a runtime argument, as shown in section 7.

---

## 5. Testing the Stream in VLC (Do This Before Writing Any Code)

This step confirms the RTSP URL is valid before you spend time debugging your Python pipeline.

1. Open **VLC**.
2. Go to **Media → Open Network Stream**.
3. Paste the sub-stream URL with credentials:
   ```
   rtsp://admin:password@192.168.128.10:554/avstream/channel=1/stream=1.sdp
   ```
4. Click **Play**.

If the video plays smoothly, the camera, network, and RTSP configuration are all correct and the problem (if any arises later) is in the code, not the camera. If the video does not play, do not proceed to section 6 — recheck sections 2 and 4 first.

---

## 6. Fixing Codec Issues (Required for Real-Time Performance)

By default, the camera encodes video in **H.265 (HEVC)**. This causes lag, frame drops, and decode errors such as:

```
Could not find ref with POC
```

### Fix

In the camera's web dashboard, go to:

```
Config → Encode
```

Change the video codec from **H.265** to **H.264**, then click **Save/Apply**.

---

## 7. Recommended Camera Settings for Real-Time AI Inference

Set these in the same **Config → Encode** menu:

| Setting    | Value                 |
|------------|------------------------|
| Stream     | Substream (`stream=1`) |
| Resolution | 640×360 or 1280×720    |
| Frame rate | 15–20 fps              |
| Codec      | H.264                  |

Lower resolution and frame rate reduce network load and give the YOLOv8 pipeline more headroom to run in real time.

---

## 8. Code Changes Required in the Project

All changes below are made in `src/main.py` (or wherever your project initializes `cv2.VideoCapture`).

### 8.1 Use the FFmpeg Backend Explicitly

```python
cap = cv2.VideoCapture(source, cv2.CAP_FFMPEG)
```

Without specifying `cv2.CAP_FFMPEG`, OpenCV may fall back to a backend that does not support RTSP reliably on macOS.

### 8.2 Reduce Internal Buffer Lag

```python
cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
```

Add this line immediately after creating `cap`. Without it, OpenCV buffers multiple frames internally, causing the pipeline to display stale (delayed) footage over time.

### 8.3 Force TCP Transport (More Stable Than UDP for This Camera)

Add this **before** `cv2.VideoCapture` is called, at the top of `src/main.py` (before any camera-related imports execute):

```python
import os
os.environ["OPENCV_FFMPEG_CAPTURE_OPTIONS"] = "rtsp_transport;tcp"
```

### 8.4 Skip Frames to Maintain Real-Time Playback

If your processing loop falls behind the live feed, discard queued frames before reading the one you will actually process:

```python
ret, frame = cap.read()

for _ in range(2):
    cap.grab()
```

Place this inside your main capture loop, not just once at startup.

### 8.5 Resize Before Running Inference

```python
frame = cv2.resize(frame, (640, 360))
```

Resize immediately after reading the frame and before passing it to the YOLOv8 model, to match the inference resolution the model expects and to reduce compute cost.

---

## 9. Running the Pipeline

Open Terminal, navigate to the project root, and activate the virtual environment:

```bash
cd /path/to/project
source .venv/bin/activate
```

Run the pipeline, passing the RTSP URL as the `--source` argument:

```bash
python src/main.py \
  --source "rtsp://admin:admin123@192.168.128.10:554/avstream/channel=1/stream=1.sdp" \
  --conf 0.5
```

`--conf 0.5` sets the YOLOv8 detection confidence threshold; adjust as needed for your use case.

---

## 10. Expected Output

* A live window showing real-time detection and tracking overlays.
* Detection logs written continuously to:
  ```
  output/logs/detection_log.csv
  ```

If no window appears or the CSV file is not being written, confirm step 5 (VLC test) still passes — if VLC fails, the issue is upstream of the code.

---

## 11. Key Takeaways

**Does not work:**
* The camera's browser dashboard URL (`/doc/page/main.html`) — this is a UI, not a stream.
* Raw WebSocket connections from OpenCV.
* H.265/HEVC streams without hardware decoding support.

**Works (industry standard):**
```
RTSP + H.264 + OpenCV (FFmpeg backend) + YOLOv8
```

---

## 12. Production Context

This same pattern scales to multi-camera deployments:

```
Multiple IP Cameras
        |
        v
   RTSP Streams
        |
        v
Parallel Processing Pipelines
        |
        v
Central Database / Dashboard
```

Using a real camera instead of a static video file moves this project from an academic demo to a system architecture that is directly applicable to smart cities, traffic monitoring, surveillance analytics, and industrial safety monitoring.

---

## 13. Future Scope

* Multi-camera ingestion with a shared processing queue.
* Asynchronous frame pipelines (avoid blocking reads).
* Edge deployment on Jetson or Radxa hardware.
* Real-time web dashboard for live monitoring.
* Event-based alerting (e.g. congestion or incident detection).