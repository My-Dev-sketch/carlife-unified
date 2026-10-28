package com.mydevsketch.byd_qin_receiver

import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.graphics.SurfaceTexture
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.MediaCodec
import android.media.MediaFormat
import android.net.ConnectivityManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.util.Rational
import android.view.Surface
import android.view.View
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.concurrent.Executors

/**
 * BYD Qin Plus DiLink OS Hardware H.264 Receiver Engine (`MainActivity.kt`).
 * - Creates a zero-copy Flutter `SurfaceTextureEntry` backed by `MediaCodec.createDecoderByType("video/avc")`
 *   with low-latency decoding (`KEY_LOW_LATENCY`) at 60fps.
 * - Detects active Phone Hotspot Gateway IP (POCO F7 `10.x.x.x`, Android `192.168.43.1`, iPhone `172.20.10.1`)
 *   automatically via `ConnectivityManager` and `WifiManager.dhcpInfo`.
 * - Plays incoming 48kHz 16-bit Stereo PCM from CarLife Port 9240 via `AudioTrack` (`USAGE_MEDIA`).
 * - Launches BYD's native installed Waze APK (`com.waze`) in DiLink Split-Screen / Picture-in-Picture mode.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.mydevsketch.byd_qin_receiver/decoder"
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var decoderSurface: Surface? = null
    private var mediaCodec: MediaCodec? = null
    private var audioTrack: AudioTrack? = null
    @Volatile private var codecConfigured = false
    private var streamWidth = 1920
    private var streamHeight = 1080
    private val decodeExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        applyImmersiveFullScreen()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initHardwareSurface" -> {
                        val w = call.argument<Int>("width") ?: 1920
                        val h = call.argument<Int>("height") ?: 1080
                        val texId = initHardwareDecoder(flutterEngine, w, h)
                        result.success(texId)
                    }

                    "updateSurfaceSize" -> {
                        val w = (call.argument<Int>("width") ?: 1920).coerceAtLeast(320)
                        val h = (call.argument<Int>("height") ?: 1080).coerceAtLeast(240)
                        streamWidth = w
                        streamHeight = h
                        textureEntry?.surfaceTexture()?.setDefaultBufferSize(w, h)
                        result.success(null)
                    }

                    "feedH264Nal" -> {
                        val bytes = call.argument<ByteArray>("nal")
                        val ptsUs = call.argument<Number>("ptsUs")?.toLong() ?: (System.nanoTime() / 1000L)
                        if (bytes != null && bytes.isNotEmpty()) {
                            decodeExecutor.execute {
                                feedH264Sample(bytes, ptsUs)
                            }
                        }
                        result.success(null)
                    }

                    "feedPcmAudio" -> {
                        val pcm = call.argument<ByteArray>("pcm")
                        if (pcm != null && pcm.isNotEmpty()) {
                            decodeExecutor.execute {
                                playPcmChunk(pcm)
                            }
                        }
                        result.success(null)
                    }

                    "getWifiGatewayInfo" -> {
                        result.success(detectWifiGatewayInfo())
                    }

                    "launchBydWazeSplitScreen" -> {
                        val lat = call.argument<Double>("lat")
                        val lon = call.argument<Double>("lon")
                        val ok = openWazeOnByd(lat, lon)
                        result.success(ok)
                    }

                    "enterPipMode" -> {
                        val ok = enterBydPictureInPicture()
                        result.success(ok)
                    }

                    "releaseDecoder" -> {
                        releaseResources()
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            applyImmersiveFullScreen()
        }
    }

    @Suppress("DEPRECATION")
    private fun applyImmersiveFullScreen() {
        try {
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                )
        } catch (_: Throwable) {}
    }

    private fun detectWifiGatewayInfo(): Map<String, String> {
        var gatewayIp = ""
        var localIp = ""
        var broadcastIp = "255.255.255.255"

        try {
            val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            val activeNet = cm?.activeNetwork
            val linkProps = if (activeNet != null) cm.getLinkProperties(activeNet) else null
            if (linkProps != null) {
                for (la in linkProps.linkAddresses) {
                    val addr = la.address
                    if (addr is Inet4Address && !addr.isLoopbackAddress) {
                        localIp = addr.hostAddress ?: ""
                        val parts = localIp.split(".")
                        if (parts.size == 4) {
                            broadcastIp = "${parts[0]}.${parts[1]}.${parts[2]}.255"
                        }
                    }
                }
                for (route in linkProps.routes) {
                    val gw = route.gateway
                    if (gw is Inet4Address && !gw.isLoopbackAddress && gw.hostAddress != "0.0.0.0") {
                        gatewayIp = gw.hostAddress ?: ""
                        break
                    }
                }
            }
        } catch (_: Throwable) {}

        if (gatewayIp.isEmpty()) {
            try {
                val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                @Suppress("DEPRECATION")
                val dhcp = wm?.dhcpInfo
                if (dhcp != null && dhcp.gateway != 0) {
                    val g = dhcp.gateway
                    gatewayIp = String.format(
                        "%d.%d.%d.%d",
                        g and 0xff,
                        g shr 8 and 0xff,
                        g shr 16 and 0xff,
                        g shr 24 and 0xff
                    )
                }
            } catch (_: Throwable) {}
        }

        if (localIp.isEmpty()) {
            try {
                val interfaces = NetworkInterface.getNetworkInterfaces()
                while (interfaces != null && interfaces.hasMoreElements()) {
                    val nif = interfaces.nextElement()
                    if (!nif.isUp || nif.isLoopback) continue
                    val addrs = nif.inetAddresses
                    while (addrs.hasMoreElements()) {
                        val a = addrs.nextElement()
                        if (a is Inet4Address && !a.isLoopbackAddress) {
                            val ip = a.hostAddress ?: continue
                            localIp = ip
                            val parts = ip.split(".")
                            if (parts.size == 4) {
                                broadcastIp = "${parts[0]}.${parts[1]}.${parts[2]}.255"
                                if (gatewayIp.isEmpty()) {
                                    gatewayIp = "${parts[0]}.${parts[1]}.${parts[2]}.1"
                                }
                            }
                            break
                        }
                    }
                    if (localIp.isNotEmpty()) break
                }
            } catch (_: Throwable) {}
        }

        return mapOf(
            "gatewayIp" to gatewayIp,
            "localIp" to localIp,
            "broadcastIp" to broadcastIp
        )
    }

    private fun initHardwareDecoder(
        flutterEngine: FlutterEngine,
        width: Int,
        height: Int
    ): Long {
        releaseResources()
        streamWidth = width.coerceAtLeast(320)
        streamHeight = height.coerceAtLeast(240)

        val entry = flutterEngine.renderer.createSurfaceTexture()
        val surfaceTexture: SurfaceTexture = entry.surfaceTexture()
        surfaceTexture.setDefaultBufferSize(streamWidth, streamHeight)
        val surface = Surface(surfaceTexture)

        textureEntry = entry
        decoderSurface = surface

        try {
            val codec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            val format = MediaFormat.createVideoFormat(
                MediaFormat.MIMETYPE_VIDEO_AVC,
                streamWidth,
                streamHeight
            ).apply {
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 4 * 1024 * 1024)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
                }
                setInteger(MediaFormat.KEY_PRIORITY, 0)
                setInteger(MediaFormat.KEY_OPERATING_RATE, Short.MAX_VALUE.toInt())
            }
            codec.configure(format, surface, null, 0)
            codec.start()
            mediaCodec = codec
            codecConfigured = true
        } catch (_: Throwable) {
            codecConfigured = false
        }

        return entry.id()
    }

    private fun feedH264Sample(nalBytes: ByteArray, ptsUs: Long) {
        val codec = mediaCodec ?: return
        if (!codecConfigured) return
        try {
            val inIndex = codec.dequeueInputBuffer(8000L)
            if (inIndex >= 0) {
                val inputBuffer = codec.getInputBuffer(inIndex)
                if (inputBuffer != null) {
                    inputBuffer.clear()
                    inputBuffer.put(nalBytes)
                    codec.queueInputBuffer(inIndex, 0, nalBytes.size, ptsUs, 0)
                }
            }

            val bufferInfo = MediaCodec.BufferInfo()
            var outIndex = codec.dequeueOutputBuffer(bufferInfo, 0L)
            while (outIndex >= 0 || outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    try {
                        val outFmt = codec.outputFormat
                        val w = outFmt.getInteger(MediaFormat.KEY_WIDTH)
                        val h = outFmt.getInteger(MediaFormat.KEY_HEIGHT)
                        if (w > 0 && h > 0) {
                            textureEntry?.surfaceTexture()?.setDefaultBufferSize(w, h)
                        }
                    } catch (_: Throwable) {}
                } else if (outIndex >= 0) {
                    codec.releaseOutputBuffer(outIndex, true)
                }
                outIndex = codec.dequeueOutputBuffer(bufferInfo, 0L)
            }
        } catch (_: Throwable) {
            // Recover automatically on next SPS/PPS IDR frame
        }
    }

    private fun playPcmChunk(pcmBytes: ByteArray) {
        try {
            if (audioTrack == null) {
                val minBuf = AudioTrack.getMinBufferSize(
                    48000,
                    AudioFormat.CHANNEL_OUT_STEREO,
                    AudioFormat.ENCODING_PCM_16BIT
                ).coerceAtLeast(8192)
                val track = AudioTrack.Builder()
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                            .build()
                    )
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(48000)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                            .build()
                    )
                    .setBufferSizeInBytes(minBuf * 2)
                    .setTransferMode(AudioTrack.MODE_STREAM)
                    .build()
                track.play()
                audioTrack = track
            }
            audioTrack?.write(pcmBytes, 0, pcmBytes.size)
        } catch (_: Throwable) {
        }
    }

    private fun openWazeOnByd(lat: Double?, lon: Double?): Boolean {
        return try {
            val uriStr = if (lat != null && lon != null) {
                "waze://?ll=$lat,$lon&navigate=yes"
            } else {
                "waze://?ul"
            }
            val wazeIntent = Intent(Intent.ACTION_VIEW, Uri.parse(uriStr)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT)
            }
            if (wazeIntent.resolveActivity(packageManager) != null) {
                enterBydPictureInPicture()
                startActivity(wazeIntent)
                true
            } else {
                val launchPkg = packageManager.getLaunchIntentForPackage("com.waze")
                if (launchPkg != null) {
                    launchPkg.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT)
                    enterBydPictureInPicture()
                    startActivity(launchPkg)
                    true
                } else {
                    false
                }
            }
        } catch (_: Throwable) {
            false
        }
    }

    private fun enterBydPictureInPicture(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(16, 9))
                    .build()
                enterPictureInPictureMode(params)
                true
            } else {
                false
            }
        } catch (_: Throwable) {
            false
        }
    }

    private fun releaseResources() {
        codecConfigured = false
        try {
            mediaCodec?.stop()
        } catch (_: Throwable) {}
        try {
            mediaCodec?.release()
        } catch (_: Throwable) {}
        mediaCodec = null

        try {
            decoderSurface?.release()
        } catch (_: Throwable) {}
        decoderSurface = null

        try {
            textureEntry?.release()
        } catch (_: Throwable) {}
        textureEntry = null

        try {
            audioTrack?.stop()
            audioTrack?.release()
        } catch (_: Throwable) {}
        audioTrack = null
    }

    override fun onDestroy() {
        releaseResources()
        super.onDestroy()
    }
}
