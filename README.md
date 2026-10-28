# CarLife Unified 60fps Wireless Suite (`iPhone 15 Pro Max` → `Toyota Corolla Hybrid` & `BYD Qin Plus`)

A Feature-First monorepo that ports the wireless **Baidu CarLife 6-Channel TCP/UDP/Crypto protocol** from [`OneAboveAll1964/ft-app`](https://github.com/OneAboveAll1964/ft-app) to **iOS (Flutter + Swift `VideoToolbox` / `ReplayKit`)** and **Android Automotive (`BYD Qin Plus` DiLink OS `MediaCodec` SurfaceTexture Receiver)**.

Built for **100% wireless operation (Zero Cables)** via iPhone Personal Hotspot, Car Wi-Fi, UDP Discovery (`7999` / `8999`), and Bluetooth A2DP/HFP, with **100% Free Navigation (Zero Map API Keys)**.

---

## Monorepo Architecture

```text
carlife_unified/
├── packages/
│   └── carlife_protocol/          # Pure Dart port of ft-app's 6-channel CarLife protocol
│       ├── lib/src/
│       │   ├── carlife_protocol_constants.dart  # Channels 1..6 (7240, 8240, 9240, 9241, 9242, 9340) + Service IDs
│       │   ├── carlife_framing.dart             # 8B Command/Touch & 12B Video/Audio framing ([Len][TS][ServiceId])
│       │   ├── carlife_crypto.dart              # RSA-2048 X.509 SPKI + AES-128-ECB session encryption
│       │   ├── car_discovery.dart               # UDP 7999 "CarlifeHost" Beacon + UDP 8999 JSON Responder + ICCOA BLE
│       │   ├── carlife_link.dart                # Dual-Role TCP Server (Hotspot) & TCP Client (Car Wi-Fi)
│       │   ├── carlife_session.dart             # Phone Sender state machine (spoofs os="Android" for Toyota DesaySV)
│       │   ├── carlife_receiver_session.dart    # BYD Qin Plus Head Unit Receiver state machine
│       │   ├── video_feed.dart                  # Annex-B H.264 SPS/PPS cache + IDR keyframe prepend + FPS gate
│       │   ├── video_plan.dart                  # Vehicle profiles (Toyota Corolla 1280x720@60, BYD Qin Plus 1920x1080@60)
│       │   └── media_and_navigation.dart        # CarLife PCM Audio, Media Metadata (0x00010035), HUD Turn Info (0x00010030)
│       └── test/
│           └── carlife_protocol_test.dart       # Full 6-channel TCP loopback handshake, H.264 framing, AES-128, & touch tests
│
├── apps/
│   ├── ios_carlife_sender/        # iPhone 15 Pro Max Sender App (Flutter + Swift VideoToolbox / ReplayKit)
│   │   ├── ios/Runner/AppDelegate.swift         # Hardware VTCompressionSession H.264 (Baseline, 0 B-frames), ReplayKit, MediaPlayer
│   │   └── lib/features/
│   │       ├── carplay_dashboard/               # iOS 18 CarPlay Split Dashboard + Full Map + Dialer + 3-Tier Mirroring
│   │       ├── navigation/                      # Zero-Key OSRM Turn-by-Turn + OpenStreetMap + Waze Deep-Link / Embed
│   │       ├── touch_dispatcher/                # Normalizes car touches -> WidgetsBinding.instance.handlePointerEvent
│   │       └── video_pipeline/                  # RepaintBoundary 60fps capture + VideoToolbox Method/EventChannel bridge
│   │
│   └── byd_qin_receiver/          # BYD Qin Plus DiLink OS Receiver APK (Flutter + Kotlin MediaCodec SurfaceTexture)
│       ├── android/app/src/main/kotlin/.../MainActivity.kt  # Low-latency MediaCodec video/avc + AudioTrack + Waze Split-Screen
│       └── lib/main.dart                        # Auto-discovery UDP listener, 60fps zero-copy Texture view, Touch injector
│
└── codemagic.yaml                 # CI/CD for iOS App Store Connect / TestFlight IPA & BYD Qin Plus Release APK
```

---

## How Wireless Connection Works (No Cable Required)

### 1. Chinese-Spec Toyota Corolla Hybrid (Built-in Baidu CarLife Receiver)
1. Enable **Personal Hotspot** on your **iPhone 15 Pro Max** (and connect your Corolla's Wi-Fi to your iPhone's Hotspot, just like the Android workflow in `ft-app`).
2. Keep your iPhone connected to the Corolla's **Bluetooth** for crystal-clear native A2DP music & hands-free calls (`Bluetooth Audio Mode` is ON by default).
3. Open **CarLife 60fps (`ios_carlife_sender`)** on your iPhone 15 Pro Max and select **Toyota Corolla Hybrid (1280x720 @ 60fps)**.
4. The iPhone opens the 6 CarLife TCP listeners (`7240`, `8240`, `9240`, `9241`, `9242`, `9340`) and broadcasts `"CarlifeHost"` on UDP port `7999` while answering discovery probes on UDP `8999`.
5. Tap **Baidu CarLife (百度CarLife)** on the Toyota Corolla screen:
   - The iPhone answers `CMD_PROTOCOL_VERSION_MATCH_STATUS` and sends `CMD_MD_INFO` with `os="Android"` so the Toyota DesaySV head unit accepts the iPhone immediately.
   - Hardware H.264 60fps video (`0x00020001`), turn-by-turn instrument cluster HUD (`0x00010030`), and song metadata (`0x00010035`) stream wirelessly, and every tap/drag on the Corolla touchscreen dispatches into the CarPlay UI.

### 2. BYD Qin Plus (DiLink Android OS)
1. Install the **`byd_qin_receiver` APK** (`apps/byd_qin_receiver/build/app/outputs/flutter-apk/app-release.apk`) onto the BYD Qin Plus DiLink screen.
2. Connect the BYD Qin Plus Wi-Fi to your **iPhone 15 Pro Max Personal Hotspot** (or connect both to the same Wi-Fi hotspot).
3. Open **BYD CarLife 60fps Receiver** on the BYD screen and **CarLife 60fps** on your iPhone (set to **BYD Qin Plus 1920x1080 @ 60fps**).
4. The BYD screen automatically hears the iPhone's UDP `7999` `"CarlifeHost"` broadcast (or connects to `172.20.10.1`) and renders the 60fps hardware `MediaCodec` stream with full multi-touch feedback.
5. **Running Waze Side-by-Side on BYD Qin Plus**: Tap **"Open BYD Waze Split-Screen"** in the top HUD bar on the BYD screen to launch the BYD's native Waze app (`com.waze`) in Android Split-Screen (`FLAG_ACTIVITY_LAUNCH_ADJACENT`) or Picture-in-Picture mode alongside your iPhone CarPlay dashboard!

---

## 3-Tier Projection & Touch Fallback System

| Tier | Mode | Description | Car Touchscreen Support |
| :--- | :--- | :--- | :--- |
| **Tier 1 (Primary)** | **Hybrid 60fps CarPlay Dashboard + ReplayKit** | Streams the interactive CarPlay Split-Screen Dashboard (Maps, Waze, Music, Phone, HUD) at 60fps and provides one-tap `RPSystemBroadcastPickerView` / `RPScreenRecorder` mirroring. | **100% Live Touch** in Dashboard |
| **Tier 2 (Fallback 1)** | **Pure In-App CarPlay UI** | Automatically stays in the 60fps CarPlay Dashboard if iOS ReplayKit system recording is declined or unavailable. | **100% Live Touch** |
| **Tier 3 (Fallback 2)** | **Full-Screen iPhone Mirroring** | Captures full iOS frames via `RPScreenRecorder.shared().startCapture` -> `VTCompressionSession` H.264 Annex-B -> Car screen. | View-Only Mirroring (iOS security sandbox) |

---

## Deploying `ios_carlife_sender` to TestFlight via Codemagic

1. Log in to [Codemagic](https://codemagic.io/) and connect the **`My-Dev-Sketch/carlife-unified`** GitHub repository.
2. In Codemagic **Teams / Integrations → Developer Portal**, connect your **App Store Connect API Key** (named `codemagic` as referenced in `codemagic.yaml`).
3. Ensure the Bundle ID `com.mydevsketch.iosCarlifeSender` is registered in your Apple Developer Portal and an App record exists in App Store Connect.
4. Trigger the **`ios-carlife-sender-testflight`** workflow in Codemagic:
   - Runs `dart test` on `packages/carlife_protocol`
   - Runs `flutter analyze` and `flutter test` on `apps/ios_carlife_sender`
   - Automatically provisions certificates, increments the TestFlight build number, builds the signed `.ipa`, and uploads it directly to **App Store Connect / TestFlight** for installation on your **iPhone 15 Pro Max**.
