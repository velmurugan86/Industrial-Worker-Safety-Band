# WorkBand — Industrial Worker Safety & Telemetry System
## Complete Architecture, Hardware Wiring & Deployment Guide

> **Production-Ready IoT Stack**: ESP32 Dual-Core (FreeRTOS) + Mosquitto MQTT + InfluxDB Time-Series + SQLite Relational + FastAPI Backend + React Real-Time Dashboard.

[![FastAPI](https://img.shields.io/badge/FastAPI-0.115+-009688.svg?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![React](https://img.shields.io/badge/React-18.0+-61DAFB.svg?logo=react&logoColor=black)](https://react.dev)
[![ESP32](https://img.shields.io/badge/Hardware-ESP32-E7352C.svg?logo=espressif&logoColor=white)](https://www.espressif.com/)
[![MQTT](https://img.shields.io/badge/Protocol-MQTT%20QoS%200%2F1-660066.svg?logo=eclipse-mosquitto&logoColor=white)](https://mosquitto.org/)
[![InfluxDB](https://img.shields.io/badge/Database-InfluxDB%20v2-22ADF6.svg?logo=influxdb&logoColor=white)](https://www.influxdata.com/)

---

## ⚡ Quick Setup & Configuration (Action Required Before Running)

Because this repository is public, all network credentials, IP addresses, and database tokens have been replaced with placeholders. Follow these **3 quick steps** to configure your setup:

### 1. Configure the ESP32 Firmware (`arduino/IndustrialWorkerSafetyBand/IndustrialWorkerSafetyBand.ino`)
Open `arduino/IndustrialWorkerSafetyBand/IndustrialWorkerSafetyBand.ino` and update the Wi-Fi and MQTT configuration around line 26:
```cpp
// ======================== CONFIGURATION (ACTION REQUIRED) ========================
#define WIFI_SSID        "YOUR_WIFI_SSID"          // Wi-Fi network SSID (must be 2.4 GHz)
#define WIFI_PASSWORD    "YOUR_WIFI_PASSWORD"      // Wi-Fi network password
#define MQTT_SERVER      "192.168.1.100"           // Local IPv4 address of PC running Mosquitto
#define MQTT_PORT        1883                      // Standard MQTT broker port
#define DEVICE_ID        "ESP32-001"               // Unique identifier for this safety band
```
> **How to find your PC's IP address**:
> - **Windows**: Run `ipconfig` in PowerShell and look for your Wi-Fi adapter's **IPv4 Address** (e.g., `192.168.1.50`).
> - **Linux / macOS**: Run `ip a` or `ifconfig`.
> - **Note**: Do **NOT** use `localhost` or `127.0.0.1` in the Arduino sketch. The ESP32 is a separate physical device and cannot reach your PC's loopback interface.
> - **Firewall**: Make sure inbound TCP port `1883` is open on your PC so the ESP32 can connect to Mosquitto (run `./setup_services.ps1` as Administrator or run `New-NetFirewallRule -DisplayName "Mosquitto" -Direction Inbound -LocalPort 1883 -Protocol TCP -Action Allow`).

### 2. Configure the Backend (`backend/.env`)
Copy `backend/.env.example` to `backend/.env` (or edit `backend/.env` directly):
```env
PORT=8001
HOST=0.0.0.0

# SQLite Relational Database
SAFETY_DB_PATH=safety_band.db
DEVICE_STALE_SECONDS=15

# MQTT Broker (Mosquitto)
MQTT_HOST=localhost
MQTT_PORT=1883

# InfluxDB Time-Series Database (Optional - system degrades to SQLite if omitted)
INFLUX_URL=http://localhost:8086
INFLUX_TOKEN=YOUR_INFLUXDB_API_TOKEN_HERE
INFLUX_ORG=your-organization-name
INFLUX_BUCKET=safety_telemetry

# Physiological Alert Thresholds
HEART_MIN=45
HEART_MAX=130
SPO2_MIN=90
TEMP_MAX=38
```
> **InfluxDB Setup**: Open `http://localhost:8086`, complete the initial setup wizard, create an Organization and Bucket, and generate an All-Access API Token under **Data > API Tokens**. Paste that token into `INFLUX_TOKEN`.
> *Note: If InfluxDB is not running, the backend automatically degrades to storing all readings in SQLite without crashing.*

### 3. Configure the Frontend (`frontend/.env`)
The frontend is pre-configured to talk to the backend on `http://127.0.0.1:8001`:
```env
VITE_API_URL=http://127.0.0.1:8001
```

---

## Table of Contents

1. [System Architecture](#1-system-architecture)
2. [Hardware — What's on the ESP32](#2-hardware--whats-on-the-esp32)
3. [Software Components & What Each Does](#3-software-components--what-each-does)
4. [Step-by-Step: Flash the ESP32](#4-step-by-step-flash-the-esp32)
5. [Step-by-Step: Start the Full Stack](#5-step-by-step-start-the-full-stack)
6. [Running Without Physical Hardware (Simulation Mode)](#6-running-without-physical-hardware-simulation-mode)
7. [Verifying Real IoT Data Flow](#7-verifying-real-iot-data-flow)
8. [Dashboard Walkthrough — All Pages & Features](#8-dashboard-walkthrough--all-pages--features)
9. [Understanding the Alert Engine](#9-understanding-the-alert-engine)
10. [Fall Detection — 3-Stage Kinematic Algorithm](#10-fall-detection--3-stage-kinematic-algorithm)
11. [Troubleshooting & FAQs](#11-troubleshooting--faqs)
12. [Quick Reference Cheatsheet](#12-quick-reference-cheatsheet)

---

## 1. System Architecture

```
+------------------------------------------------------------------+
|                  ESP32 (Device ID: ESP32-001)                    |
|                                                                  |
|  Core 1 (loop)                    Core 0 (mqttTask)             |
|  -----------------                -----------------             |
|  MPU6050  -> 200 Hz fall detect   WiFi & MQTT client            |
|  MAX30102 -> HR + SpO2            Dequeues TelemetryPackets      |
|  DS18B20  -> Skin temperature     Publishes to Mosquitto         |
|  MQ-135   -> Air Quality ADC      Handles LWT (auto-offline)    |
|               |                              |                  |
|         FreeRTOS Queue (thread-safe)         |                  |
|               +------------------------------+                  |
+----------------------------------+-------------------------------+
                                   | MQTT (TCP port 1883)
                                   v
+------------------------------------------------------------------+
|          Mosquitto MQTT Broker (Local Service / Daemon)          |
|          Topics subscribed by backend:                           |
|          workband/telemetry/ESP32-001  (QoS 0 - vitals)         |
|          workband/critical/ESP32-001   (QoS 1 - falls)          |
|          workband/status/ESP32-001     (QoS 1 - LWT)            |
+----------------------------------+-------------------------------+
                                   | aiomqtt (async subscriber)
                                   v
+------------------------------------------------------------------+
|          FastAPI Backend  (http://0.0.0.0:8001)                  |
|                                                                  |
|  process_reading()                                               |
|  +-- Writes to SQLite  (workers, alerts, falls, devices)         |
|  +-- Writes to InfluxDB  (sensor_readings, time-series)          |
|  +-- Runs alert engine  (HR / SpO2 / Temp / Fall rules)         |
|  +-- Broadcasts via WebSocket to all connected dashboards        |
|                                                                  |
|  REST API  /api/*         WebSocket  /ws/monitoring              |
+----------------------------------+-------------------------------+
                                   | HTTP + WebSocket
                                   v
+------------------------------------------------------------------+
|       React Dashboard  (http://localhost:5173 / :5174)           |
|       Pages: Overview / Workers / Alerts / Analytics / Registry  |
+------------------------------------------------------------------+
```

### Data Flow Timing

| Stage | Frequency | Protocol |
|---|---|---|
| MPU6050 fall detection | **200 Hz** (every 5 ms) | I2C on Core 1 |
| Periodic vitals publish | Every **1 second** | MQTT QoS 0 |
| Fall event publish | **Immediately** on detection | MQTT QoS 1 |
| Backend to Dashboard push | On every reading received | WebSocket |
| Dashboard fallback poll | Every **15 seconds** | HTTP GET |

---

## 2. Hardware — What's on the ESP32

### Sensors

| Sensor | GPIO Pins | What it measures | Sample Rate |
|---|---|---|---|
| **MPU6050** (IMU) | SDA=22, SCL=23 (I2C) | X/Y/Z acceleration (±8g range) for fall detection | 200 Hz |
| **MAX30102** (PPG) | SDA=22, SCL=23 (I2C) | Heart rate (BPM) + SpO2 (%) | ~25 Hz (100-sample buffer) |
| **DS18B20** (Temp) | GPIO 4 (1-Wire) | Body/skin temperature in Celsius | ~4 Hz (async conversion) |
| **MQ-135** (Gas) | GPIO 34 (ADC1_CH6) | Toxic gas & air quality — raw ADC (0-4095) + voltage (0-3.3V) | 4 Hz |

### Actuators (Local Haptic & Audible Feedback)

| Actuator | GPIO Pin | Trigger Condition |
|---|---|---|
| LED (alert) | GPIO 27 | Any confirmed alert (HR, SpO2, Fall, High Temp) |
| Vibration motor | GPIO 26 | Same as LED |
| Buzzer (active low) | GPIO 25 | Same as LED, buzzes for 2 seconds |

### Critical Wiring Notes

- **Shared I2C Bus**: MPU6050 and MAX30102 share SDA (GPIO 22) and SCL (GPIO 23). They use distinct I2C addresses (`0x68` and `0x57`), so no multiplexer is required.
- **1-Wire Pull-Up**: The DS18B20 requires a **4.7kΩ pull-up resistor** between the data line (GPIO 4) and 3.3V.
- **ADC Pin Selection**: MQ-135 analog output connects to **GPIO 34** (ADC1_CH6). Only **ADC1** pins function reliably when the ESP32 Wi-Fi radio is active (ADC2 is shared with Wi-Fi).
- **Power Delivery**: Supply the ESP32 and sensors with a stable 5V (USB or LiPo through a 3.3V regulator). Ensure the MQ-135 heater receives 5V (VIN) for reliable gas sensing.

---

## 3. Software Components & What Each Does

### 3a. Arduino Firmware (`arduino/IndustrialWorkerSafetyBand/IndustrialWorkerSafetyBand.ino`)

**FreeRTOS Dual-Core Architecture:**
- **Core 1 (`loop()`)**: 100% dedicated to high-frequency sensor acquisition. Never sleeps longer than 5 ms. Completely immune to network lag or MQTT disconnections.
- **Core 0 (`mqttTask`)**: Dedicated to Wi-Fi connectivity, MQTT packet transmission, reconnect loops, and Last Will & Testament (LWT) management.
- **Thread-Safe IPC**: Cores communicate via a `QueueHandle_t telemetryQueue` and a mutex `telemetryMutex`. Critical fall packets bypass the queue using `xQueueSendToFront`.

### 3b. Backend Server (`backend/main.py`)

- **FastAPI Core**: Asynchronous REST API + WebSocket broadcasting at `/ws/monitoring`.
- **Dual-Storage Engine**:
  - **SQLite**: Stores relational entities (workers roster, alert state transitions, fall incident forensic proof dossiers, device registry).
  - **InfluxDB v2**: High-throughput time-series engine storing raw telemetry at sub-second resolution for waveform plotting.
- **Automated Graceful Degradation**: If InfluxDB or Mosquitto is absent, the backend seamlessly falls back to SQLite storage and HTTP endpoints.
- **Forensic Verification Engine**: Analyzes fall kinematics against physical criteria before marking incidents as verified.

### 3c. React Dashboard (`frontend/src/main.jsx`)

- **Live Overview**: Real-time gauge dials, live signal orb, instantaneous threshold indicator, and recent incident feed.
- **Worker Directory**: Personnel profiles, department sorting, individual fall count tracking, and full worker safety detail modal.
- **Alerts Hub**: Interactive triage system with acknowledge, resolve, and direct link to forensic proof.
- **Signal Analytics**: Multi-worker comparative waveforms and zoomable time-series charts (1h / 6h / 24h).
- **Forensic Dossier Modal**: Interactive 3-stage kinematic acceleration curve (<0.45G drop, >2.0G peak impact, <0.35G rest immobility) and vitals at moment of impact.
- **Hardware Registry**: Pin-level diagnostic diagram for ESP32 and attached sensors.

---

## 4. Step-by-Step: Flash the ESP32

### Step 1: Install Arduino Libraries
In Arduino IDE, open **Tools > Manage Libraries...** and install:
- `PubSubClient` by Nick O'Leary
- `MAX30105` by SparkFun
- `DallasTemperature` by Miles Burton
- `OneWire` by Jim Studt

Install **ESP32 Board Support** via **Tools > Board > Boards Manager...** (search `esp32` by Espressif Systems).

### Step 2: Edit Network Configuration
Open `arduino/IndustrialWorkerSafetyBand/IndustrialWorkerSafetyBand.ino` and set:
```cpp
#define WIFI_SSID     "YourNetworkName"
#define WIFI_PASSWORD "YourNetworkPassword"
#define MQTT_SERVER   "192.168.1.100"   // Your PC's Wi-Fi IPv4 address
```

### Step 3: Flash to ESP32
1. Select **Tools > Board > ESP32 Dev Module**
2. Select your device port under **Tools > Port**
3. Set Upload Speed to **921600**
4. Click **Upload**
5. Open **Serial Monitor** at **115200 baud**

Expected output:
```
=====================================================
   WORKER SAFETY BAND - MQTT + FreeRTOS ARCHITECTURE
=====================================================
[Core 0] Connecting Wi-Fi.....
[Core 0] Wi-Fi connected! IP: 192.168.1.57
[Core 0] Connecting MQTT to 192.168.1.100:1883...
[Core 0] MQTT CONNECTED!
[Core 0] Published online status (retained, QoS 0).
```

---

## 5. Step-by-Step: Start the Full Stack

Run each component in a separate terminal window:

### Window 1 — Mosquitto MQTT Broker
```powershell
# Windows Service:
net start mosquitto
# OR run standalone:
mosquitto -v
```
*(On Linux/macOS: `sudo systemctl start mosquitto` or `mosquitto -v`)*

### Window 2 — InfluxDB Time-Series Engine (Optional)
```powershell
influxd
```
*(If you do not have InfluxDB installed, skip this step. The backend will automatically store all history in SQLite).*

### Window 3 — Backend API
```powershell
cd backend
python -m venv .venv
# Windows:
.venv\Scripts\activate
# Linux/macOS:
# source .venv/bin/activate

pip install -r requirements.txt
python main.py
```
Expected output:
```
INFO  Loaded environment from .../backend/.env
INFO  InfluxDB connected (http://localhost:8086) - bucket: safety_telemetry
INFO  WorkBand backend started (MQTT=True, InfluxDB=True)
INFO  MQTT connected! Subscribing to workband/# ...
INFO  Uvicorn running on http://0.0.0.0:8001
```

### Window 4 — React Dashboard
```powershell
cd frontend
npm install
npm run dev
```
Open **http://localhost:5173** (or the port displayed in your terminal).

---

## 6. Running Without Physical Hardware (Simulation Mode)

You can explore the full application without having an ESP32 or sensors connected!

### Method 1: Web Dashboard Simulation Toggle
1. Open the dashboard in your browser.
2. Click the **DEMO MODE / LIVE STREAM** toggle button in the top header.
3. The dashboard will automatically simulate live vital signs, fluctuations, and realistic telemetry.
4. Click the **Simulate Fall Incident** button in the header to trigger a verified 3-stage fall with a complete kinematic proof dossier!

### Method 2: Manual API Injection (HTTP Fallback)
Inject a normal reading:
```powershell
Invoke-RestMethod -Method POST -Uri "http://127.0.0.1:8001/api/readings" `
  -ContentType "application/json" `
  -Body '{"device_id":"ESP32-001","heart_rate":82.5,"spo2":98.0,"temperature":36.7,"air_quality_adc":310,"air_quality_voltage":0.82}'
```

Inject a critical fall incident with kinematic proof:
```powershell
Invoke-RestMethod -Method POST -Uri "http://127.0.0.1:8001/api/incidents/simulate-fall" `
  -ContentType "application/json" `
  -Body '{"device_id":"ESP32-001","peak_impact_g":3.85,"free_fall_duration_ms":250,"heart_rate":122,"spo2":96,"temperature":37.1}'
```

---

## 7. Verifying Real IoT Data Flow

### 1. ESP32 Serial Monitor (115200 baud)
```
Heart Rate: 74.2 BPM | SpO2: 98.0%
Temperature: 36.85 C
MQ-135 ADC: 295 | Voltage: 0.81V
[Core 0] MQTT PUB workband/telemetry/ESP32-001 (128 bytes)
```

### 2. Backend Health Check
```powershell
curl http://127.0.0.1:8001/api/health
```
Response:
```json
{
  "status": "ok",
  "mqtt_enabled": true,
  "influxdb_connected": true,
  "influxdb_url": "http://localhost:8086",
  "architecture": "MQTT + InfluxDB + SQLite + FastAPI + WebSocket"
}
```

### 3. Wire-Level MQTT Inspection
```powershell
mosquitto_sub -h localhost -t "workband/#" -v
```

---

## 8. Dashboard Walkthrough — All Pages & Features

| Page | Key Capabilities |
|---|---|
| **Overview** | Live vital sign gauges, real-time PPG stream status, overall safety score, system zoom controls, and emergency fall banner. |
| **Workers** | Monitored personnel roster, online status, emergency contacts, blood type, shift info, and cumulative fall incident count. |
| **Alerts** | Comprehensive log of Active, Acknowledged, and Resolved events with severity indicators and immediate triage actions. |
| **Analytics** | Interactive multi-signal waveforms over customizable time windows (1h, 6h, 24h) with worker-by-worker comparison. |
| **Registry** | ESP32 hardware specification, pinout diagrams, I2C bus address map, and sensor operational parameters. |

---

## 9. Understanding the Alert Engine

### Threshold Rules

| Metric | Normal Range | Trigger Condition | Severity |
|---|---|---|---|
| **Heart Rate** | 60 – 100 BPM | `< 45 BPM` or `> 130 BPM` | **CRITICAL** |
| **Blood Oxygen (SpO2)**| 95 – 100 % | `< 90 %` | **CRITICAL** |
| **Temperature** | 35.5 – 37.5 °C | `> 38.0 °C` | **WARNING** |
| **Toxic Gas / Air** | Clean baseline | Delta > 600 ADC or ADC > 1800 | **WARNING / CRITICAL** |
| **Worker Fall** | Upright motion | Confirmed 3-phase kinematic pattern | **CRITICAL** |

### Lifecycle of an Alert
1. **Trigger**: An incoming packet crosses a safety threshold or reports a confirmed fall.
2. **Dispatch**: Alert is saved to SQLite and broadcast across WebSocket in `< 20ms`.
3. **Banner**: Dashboard displays a red high-priority emergency banner with audio/visual pulse.
4. **Action**: The operator can click **Inspect Forensic Proof**, **Acknowledge**, or **Resolve**.
5. **Auto-Recovery**: Physiological alerts automatically resolve when subsequent readings return to normal ranges.

---

## 10. Fall Detection — 3-Stage Kinematic Algorithm

The fall detection algorithm executes on **Core 1 at 200 Hz (every 5 ms)** using the MPU6050 accelerometer configured to a **±8g range** to prevent clipping:

```
+-------------+      Free-fall G < 0.45g       +-------------+
|   NORMAL    | -----------------------------> |  FREE FALL  |
+-------------+                                +-------------+
       ^                                              |
       | Timeout > 600ms (False alarm rejected)       | Impact G >= 2.0g
       +----------------------------------------------+
                                                      v
                                               +-------------+
                                               |   IMPACT    |
                                               +-------------+
                                                      |
                                                      | Rest window (1500 ms)
                                                      | 20 stable samples (0.7g - 1.35g)
                                                      | Max variation <= 0.35g
                                                      v
                                        [ CONFIRMED FALL INCIDENT ]
                                                      |
                                   +------------------+------------------+
                                   |                                     |
                          Activate Local Haptics                Enqueue to Front of
                         (Buzzer + Vibration + LED)            MQTT Core 0 Queue (QoS 1)
```

---

## 11. Troubleshooting & FAQs

### Q1: ESP32 fails to connect to MQTT (`rc=-2` in Serial Monitor)
- **Cause**: The ESP32 cannot reach the PC's IP address.
- **Fix**: Check `MQTT_SERVER` in the `.ino` file. Verify you did not use `localhost`. Run `./setup_services.ps1` as Administrator to open Windows Firewall port 1883.

### Q2: Mosquitto refuses connection (`rc=-4` or connection refused)
- **Cause**: Mosquitto 2.0+ defaults to localhost-only without anonymous access.
- **Fix**: Add the following two lines to your `mosquitto.conf`:
  ```
  listener 1883 0.0.0.0
  allow_anonymous true
  ```
  Then restart Mosquitto: `net stop mosquitto` and `net start mosquitto`.

### Q3: InfluxDB shows "Unauthorized" (401)
- **Cause**: The API token in `backend/.env` is missing or expired.
- **Fix**: Generate a new all-access token in the InfluxDB Web UI under **Data > API Tokens** and paste it into `INFLUX_TOKEN`.

### Q4: MAX30102 reports BPM = 0 or NAN
- **Cause**: The sensor needs firm, direct skin contact for ~4 seconds to collect 100 consecutive samples and run the SpO2 algorithm.
- **Fix**: Place your finger firmly over the red and IR LEDs. Ensure the green LED on the sensor lights up.

---

## 12. Quick Reference Cheatsheet

### Starting Services

```powershell
# 1. Start MQTT Broker (Admin)
net start mosquitto

# 2. Start InfluxDB (Optional)
influxd

# 3. Start Backend
cd backend
python main.py

# 4. Start Frontend
cd frontend
npm run dev
```

### Essential API Routes

| Endpoint | Method | Description |
|---|---|---|
| `/api/health` | GET | System architecture status (MQTT, InfluxDB, DB) |
| `/api/workers` | GET | Roster of workers and cumulative fall statistics |
| `/api/workers/{device_id}` | GET | Individual worker vitals and history |
| `/api/readings/latest` | GET | Latest sensor packet received |
| `/api/readings/history` | GET | Historical time-series query |
| `/api/alerts` | GET | List of active, acknowledged, or resolved alerts |
| `/api/alerts/{id}/acknowledge`| PATCH | Acknowledge active safety alert |
| `/api/alerts/{id}/resolve` | PATCH | Mark safety alert resolved |
| `/api/incidents/falls` | GET | Complete forensic fall dossiers |
| `/api/incidents/simulate-fall` | POST | Inject verified fall incident |
| `/ws/monitoring` | WS | Real-time bi-directional telemetry stream |

### MQTT Topic Hierarchy

```
workband/telemetry/ESP32-001   <- Normal periodic vitals (QoS 0)
workband/critical/ESP32-001    <- Confirmed falls & urgent physiological alerts (QoS 1)
workband/status/ESP32-001      <- Online/Offline Last Will & Testament (QoS 1, retained)
workband/command/ESP32-001     <- Remote buzzer/vibration cancel command from dashboard
```

---

## License

This project is licensed under the MIT License — feel free to use and adapt it for academic research, industrial prototypes, or commercial safety deployments.
