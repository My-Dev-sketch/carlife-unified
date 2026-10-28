# CarLife Unified 60fps Wireless Suite (`POCO Android` & `iPhone 15 Pro Max` → `BYD Qin Plus` & `Toyota Corolla Hybrid`)

A Feature-First monorepo that ports the wireless **Baidu CarLife 6-Channel TCP/UDP/Crypto protocol** from [`OneAboveAll1964/ft-app`](https://github.com/OneAboveAll1964/ft-app) into two simple apps that work together **100% Wirelessly (Zero Cables)**:

1. **The Car Screen Receiver APK (`byd-qin-plus-carlife-receiver-v1.0.0.apk`)**: Installed on your **BYD Qin Plus DiLink screen** (note: your Chinese Toyota Corolla already has Baidu CarLife built into its factory screen).
2. **The Cross-Platform Phone Sender App (`carlife-sender-android-v1.0.0.apk` for Android / TestFlight IPA for iPhone 15 Pro Max)**: Installed on your **POCO Android phone** or **iPhone 15 Pro Max**. It streams the 60fps CarPlay-style Dashboard (or full phone screen mirroring) to the car screen and receives your car touchscreen taps back.

---

## Direct APK Downloads (GitHub Release `v1.0.0`)

- **Release Page**: [`https://github.com/My-Dev-sketch/carlife-unified/releases/tag/v1.0.0`](https://github.com/My-Dev-sketch/carlife-unified/releases/tag/v1.0.0)
- **1. Car Screen APK (Install on BYD Qin Plus)**: [`byd-qin-plus-carlife-receiver-v1.0.0.apk`](https://github.com/My-Dev-sketch/carlife-unified/releases/download/v1.0.0/byd-qin-plus-carlife-receiver-v1.0.0.apk)
- **2. Phone Sender APK (Install on POCO Android Phone)**: [`carlife-sender-android-v1.0.0.apk`](https://github.com/My-Dev-sketch/carlife-unified/releases/download/v1.0.0/carlife-sender-android-v1.0.0.apk)
- **3. Original `ft-app` Android APK (Optional for POCO)**: [`ft-app-sender-v1.0.0.apk`](https://github.com/My-Dev-sketch/carlife-unified/releases/download/v1.0.0/ft-app-sender-v1.0.0.apk)

---

## Full Step-by-Step Testing Guide

### Part 1: Test First with Your POCO Android Phone + BYD Qin Plus (Zero Cables)

#### Step 1 — Install the 2 APKs
1. **On your BYD Qin Plus car screen**:
   - Download and install **[`byd-qin-plus-carlife-receiver-v1.0.0.apk`](https://github.com/My-Dev-sketch/carlife-unified/releases/download/v1.0.0/byd-qin-plus-carlife-receiver-v1.0.0.apk)** (via the BYD browser from your GitHub Release link, or via a USB flash drive plugged into the BYD data port).
2. **On your POCO Android phone**:
   - Download and install **[`carlife-sender-android-v1.0.0.apk`](https://github.com/My-Dev-sketch/carlife-unified/releases/download/v1.0.0/carlife-sender-android-v1.0.0.apk)** (and optionally **[`ft-app-sender-v1.0.0.apk`](https://github.com/My-Dev-sketch/carlife-unified/releases/download/v1.0.0/ft-app-sender-v1.0.0.apk)** if you also want to compare the original `ft-app` on the BYD screen).

#### Step 2 — Connect Hotspot & Bluetooth
1. On your **POCO phone**, turn ON **Personal Hotspot (Wi-Fi Hotspot)**.
2. On your **BYD Qin Plus screen**, connect the car's **Wi-Fi** to your **POCO phone's Hotspot**.
3. Pair your **POCO phone's Bluetooth** to the **BYD Qin Plus Bluetooth** (this handles crystal-clear car speaker audio & calls automatically).

#### Step 3 — Start Streaming at 60fps
1. Open **CarLife 60fps Phone Sender** on your **POCO phone**:
   - Make sure the top vehicle selector is set to **`BYD Qin Plus (1920x1080 @ 60fps)`**.
   - The POCO phone immediately opens the 6 CarLife TCP ports (`7240`, `8240`, `9240`, `9241`, `9242`, `9340`) and broadcasts `"CarlifeHost"` on UDP port `7999`.
2. Open **BYD CarLife 60fps Receiver** on your **BYD Qin Plus screen**:
   - The BYD screen automatically detects the `"CarlifeHost"` UDP broadcast from your POCO phone and connects within 1–2 seconds!
   - *(Tip: If Xiaomi/HyperOS Hotspot isolates UDP broadcast on your POCO phone, simply type your POCO's hotspot gateway IP—usually `192.168.43.1` or `192.168.232.1`, or check Wi-Fi Gateway details on the BYD screen—into the IP box on the BYD screen and tap **Connect Now**).*
3. **Test Features on the BYD Screen**:
   - **Touch Control**: Tap **Map**, **Dialer**, **Split Dashboard**, or search any destination on the BYD touchscreen—your touches are sent back to the POCO phone in real time.
   - **Full Phone Screen Mirroring**: Tap **Mirror Phone** on the left sidebar and accept the Android screen capture prompt on your POCO to mirror your entire POCO screen (YouTube, Waze, Google Maps, any app) at 60fps!
   - **Waze Split-Screen on BYD**: Tap **"Open BYD Waze Split-Screen"** at the top of the BYD receiver screen to run BYD's native Waze side-by-side with your phone stream.

---

### Part 2: Test Your POCO Android Phone on the Toyota Corolla Hybrid

1. Keep **Personal Hotspot** ON on your **POCO phone**, and connect the **Toyota Corolla's Wi-Fi** to your POCO Hotspot (and connect Bluetooth).
2. Open **CarLife 60fps Phone Sender** on your POCO phone and tap the top selector to switch to **`Toyota Corolla Hybrid (1280x720 @ 60fps)`** (or open `ft-app-sender-v1.0.0.apk`).
3. Tap **Baidu CarLife (百度CarLife)** on the Toyota Corolla's factory screen—it will discover your POCO phone on UDP `7999` / `8999` and project wirelessly!

---

### Part 3: Test Second with Your iPhone 15 Pro Max (on Both BYD Qin Plus & Toyota Corolla)

#### Step 1 — Install on iPhone 15 Pro Max via Codemagic / TestFlight
1. Log in to [Codemagic](https://codemagic.io/) and add your GitHub repository **[`My-Dev-sketch/carlife-unified`](https://github.com/My-Dev-sketch/carlife-unified)**.
2. Connect your **App Store Connect API Key** (`codemagic`) under Integrations and run the **`ios-carlife-sender-testflight`** workflow from [`codemagic.yaml`](file:///c:/Users/MohammedYousif/apps/carlife_unified/codemagic.yaml).
3. Install **CarLife 60fps** from **TestFlight** onto your **iPhone 15 Pro Max**.

#### Step 2 — Connect Wirelessly to BYD Qin Plus or Toyota Corolla
1. Turn ON **Personal Hotspot** on your **iPhone 15 Pro Max** (`Settings → Personal Hotspot → Allow Others to Join`, with **Maximize Compatibility** enabled).
2. Connect your **BYD Qin Plus** (or **Toyota Corolla**) Wi-Fi to your iPhone's Hotspot, and connect Bluetooth.
3. Open **CarLife 60fps** on your **iPhone 15 Pro Max**:
   - When asked by iOS *"Allow CarLife 60fps to find and connect to devices on your local network"*, tap **Allow**.
   - Select **`BYD Qin Plus (1920x1080 @ 60fps)`** or **`Toyota Corolla Hybrid (1280x720 @ 60fps)`**.
4. **On BYD Qin Plus**: Open **BYD CarLife 60fps Receiver**—it automatically connects to your iPhone's Hotspot IP (`172.20.10.1`)!
5. **On Toyota Corolla**: Tap **Baidu CarLife (百度CarLife)** on the factory screen—our iPhone app spoofs `os="Android"` in `CMD_MD_INFO` so the Corolla's DesaySV head unit accepts your iPhone 15 Pro Max wirelessly!
