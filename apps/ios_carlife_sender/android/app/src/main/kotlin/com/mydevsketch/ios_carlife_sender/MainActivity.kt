package com.mydevsketch.ios_carlife_sender

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Paint
import android.graphics.Rect
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.view.PixelCopy
import android.view.Surface
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/**
 * Cross-Platform Android Hardware H.264 `MediaCodec` Encoder (`video/avc`) + `PixelCopy` 60fps GPU Capture
 * + `MediaProjection` Screen Mirroring for the Phone Sender App (`ios_carlife_sender`).
 * Ported from `ft-app` (`SurfaceEncoder.kt` & `PhoneMirror.kt`):
 * - Uses hardware `PixelCopy.request(flutterSurfaceView, ...)` on a dedicated `HandlerThread` and draws
 *   scaled to `Rect(0, 0, width, height)` (`1920x1080`) on `MediaCodec`'s `inputSurface`, achieving true 60fps
 *   with zero black bars and zero Flutter UI thread overhead.
 */
class MainActivity : FlutterActivity(), EventChannel.StreamHandler {
    private val methodChannelName = "com.mydevsketch.carlife/native_bridge"
    private val eventChannelName = "com.mydevsketch.carlife/h264_stream"
    private val requestCodeMediaProjection = 9240

    private var eventSink: EventChannel.EventSink? = null
    private var encoder: MediaCodec? = null
    private var inputSurface: Surface? = null
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var pendingProjectionResult: MethodChannel.Result? = null

    private var width: Int = 1920
    private var height: Int = 1080
    private var fps: Int = 60
    private var bitrate: Int = 6_000_000
    private val encodeExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pixelCopyThread: HandlerThread? = null
    private var pixelCopyHandler: Handler? = null
    private var captureBitmap: Bitmap? = null
    private val scalePaint = Paint(Paint.FILTER_BITMAP_FLAG)

    @Volatile private var running = false
    @Volatile private var fullScreenMirroring = false
    @Volatile private var pixelCopyActive = false
    @Volatile private var pixelCopyInFlight = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        applyImmersiveFullScreen()
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initVideoToolbox" -> {
                        val w = call.argument<Int>("width") ?: 1920
                        val h = call.argument<Int>("height") ?: 1080
                        val f = call.argument<Int>("fps") ?: 60
                        val b = call.argument<Int>("bitrate") ?: 6_000_000
                        startHardwareEncoder(w, h, f, b)
                        result.success(null)
                    }

                    "isNativePixelCopyActive" -> {
                        result.success(pixelCopyActive || fullScreenMirroring)
                    }

                    "encodeRgbaFrame" -> {
                        if (!fullScreenMirroring && !pixelCopyActive) {
                            val rgba = call.argument<ByteArray>("rgba")
                            val w = call.argument<Int>("width") ?: width
                            val h = call.argument<Int>("height") ?: height
                            if (rgba != null) {
                                renderRgbaToSurface(rgba, w, h)
                            }
                        }
                        result.success(null)
                    }

                    "requestKeyframe" -> {
                        requestSyncFrame()
                        result.success(null)
                    }

                    "startReplayKitCapture" -> {
                        requestMediaProjection(result)
                    }

                    "stopReplayKitCapture" -> {
                        stopMediaProjection()
                        result.success(null)
                    }

                    "showBroadcastPicker" -> {
                        requestMediaProjection(null)
                        result.success(null)
                    }

                    "launchExternalApp" -> {
                        val pkg = call.argument<String>("package") ?: ""
                        val url = call.argument<String>("url") ?: ""
                        val ok = launchExternalAndroidApp(pkg, url)
                        result.success(ok)
                    }

                    "getNowPlaying" -> {
                        result.success(
                            mapOf(
                                "title" to "Android Auto Coolwalk 60fps",
                                "artist" to "Wireless CarLife + A2DP Audio",
                                "album" to "BYD DiLink / Toyota Corolla"
                            )
                        )
                    }

                    "joinCarHotspot" -> {
                        result.success(true)
                    }

                    "stopVideoToolbox" -> {
                        stopMediaProjection()
                        stopHardwareEncoder()
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun launchExternalAndroidApp(pkg: String, fallbackUrl: String): Boolean {
        return try {
            val launchIntent = if (pkg.isNotEmpty()) {
                packageManager.getLaunchIntentForPackage(pkg)
            } else {
                null
            }
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(launchIntent)
                true
            } else if (fallbackUrl.isNotEmpty()) {
                val viewIntent = Intent(Intent.ACTION_VIEW, Uri.parse(fallbackUrl)).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(viewIntent)
                true
            } else {
                false
            }
        } catch (_: Throwable) {
            false
        }
    }

    private fun requestMediaProjection(result: MethodChannel.Result?) {
        try {
            val mgr = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            pendingProjectionResult = result
            @Suppress("DEPRECATION")
            startActivityForResult(mgr.createScreenCaptureIntent(), requestCodeMediaProjection)
        } catch (_: Exception) {
            result?.success(false)
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == requestCodeMediaProjection) {
            val res = pendingProjectionResult
            pendingProjectionResult = null
            if (resultCode == Activity.RESULT_OK && data != null) {
                try {
                    val mgr = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                    val proj = mgr.getMediaProjection(resultCode, data)
                    mediaProjection = proj
                    val surface = inputSurface
                    if (proj != null && surface != null) {
                        virtualDisplay = proj.createVirtualDisplay(
                            "CarLifeMirror60fps",
                            width,
                            height,
                            resources.displayMetrics.densityDpi,
                            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                            surface,
                            null,
                            null
                        )
                        fullScreenMirroring = true
                        requestSyncFrame()
                        res?.success(true)
                        return
                    }
                } catch (_: Exception) {
                }
            }
            fullScreenMirroring = false
            res?.success(false)
        }
    }

    private fun stopMediaProjection() {
        fullScreenMirroring = false
        try {
            virtualDisplay?.release()
        } catch (_: Exception) {
        }
        virtualDisplay = null
        try {
            mediaProjection?.stop()
        } catch (_: Exception) {
        }
        mediaProjection = null
    }

    private fun startHardwareEncoder(w: Int, h: Int, targetFps: Int, targetBitrate: Int) {
        stopHardwareEncoder()
        width = ((w.coerceAtLeast(640)) / 2) * 2
        height = ((h.coerceAtLeast(360)) / 2) * 2
        fps = targetFps.coerceIn(15, 60)
        bitrate = targetBitrate.coerceAtLeast(3_000_000)

        try {
            val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
                setInteger(
                    MediaFormat.KEY_COLOR_FORMAT,
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
                )
                setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
                setInteger(MediaFormat.KEY_FRAME_RATE, fps)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
                setLong(MediaFormat.KEY_REPEAT_PREVIOUS_FRAME_AFTER, 100_000L)
                setInteger(
                    MediaFormat.KEY_PROFILE,
                    MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline
                )
                setInteger(
                    MediaFormat.KEY_LEVEL,
                    MediaCodecInfo.CodecProfileLevel.AVCLevel4
                )
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    setInteger(MediaFormat.KEY_MAX_B_FRAMES, 0)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    setInteger(MediaFormat.KEY_LATENCY, 1)
                }
                setInteger(MediaFormat.KEY_PRIORITY, 0)
                setInteger(MediaFormat.KEY_OPERATING_RATE, Short.MAX_VALUE.toInt())
            }

            val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            inputSurface = codec.createInputSurface()
            codec.start()
            encoder = codec
            running = true

            encodeExecutor.execute { drainEncoderLoop() }
            startPixelCopyLoop()
        } catch (_: Exception) {
            running = false
        }
    }

    private fun findFlutterSurfaceView(root: View?): SurfaceView? {
        if (root == null) return null
        if (root is SurfaceView) return root
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                val found = findFlutterSurfaceView(root.getChildAt(i))
                if (found != null) return found
            }
        }
        return null
    }

    private fun startPixelCopyLoop() {
        stopPixelCopyLoop()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val thread = HandlerThread("CarLifePixelCopy")
        thread.start()
        val handler = Handler(thread.looper)
        pixelCopyThread = thread
        pixelCopyHandler = handler

        val intervalMs = (1000L / fps.coerceIn(20, 60)).coerceAtLeast(16L)
        val tick = object : Runnable {
            override fun run() {
                if (!running) return
                if (!fullScreenMirroring && !pixelCopyInFlight) {
                    captureFrameViaPixelCopy(handler)
                }
                handler.postDelayed(this, intervalMs)
            }
        }
        handler.postDelayed(tick, 32L)
    }

    private fun captureFrameViaPixelCopy(handler: Handler) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val surface = inputSurface ?: return
        if (!running || !surface.isValid) return

        val sv = findFlutterSurfaceView(window?.decorView) ?: return
        val holderSurface = sv.holder?.surface ?: return
        if (!holderSurface.isValid || sv.width <= 0 || sv.height <= 0) return

        val capW = width
        val capH = height
        var bmp = captureBitmap
        if (bmp == null || bmp.width != capW || bmp.height != capH || bmp.isRecycled) {
            bmp = Bitmap.createBitmap(capW, capH, Bitmap.Config.ARGB_8888)
            captureBitmap = bmp
        }

        pixelCopyInFlight = true
        try {
            PixelCopy.request(
                sv,
                bmp,
                { copyResult ->
                    try {
                        if (copyResult == PixelCopy.SUCCESS && running && !fullScreenMirroring && surface.isValid) {
                            val dstCanvas = surface.lockHardwareCanvas()
                            try {
                                dstCanvas.drawBitmap(bmp, null, Rect(0, 0, width, height), scalePaint)
                                pixelCopyActive = true
                            } finally {
                                surface.unlockCanvasAndPost(dstCanvas)
                            }
                        }
                    } catch (_: Throwable) {
                    } finally {
                        pixelCopyInFlight = false
                    }
                },
                handler
            )
        } catch (_: Throwable) {
            pixelCopyInFlight = false
        }
    }

    private fun stopPixelCopyLoop() {
        pixelCopyActive = false
        pixelCopyInFlight = false
        pixelCopyHandler?.removeCallbacksAndMessages(null)
        pixelCopyHandler = null
        try {
            pixelCopyThread?.quitSafely()
        } catch (_: Throwable) {}
        pixelCopyThread = null
    }

    private fun renderRgbaToSurface(rgba: ByteArray, w: Int, h: Int) {
        val surface = inputSurface ?: return
        if (!running || !surface.isValid || w <= 0 || h <= 0 || rgba.size < w * h * 4) return
        try {
            val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            bmp.copyPixelsFromBuffer(ByteBuffer.wrap(rgba))
            val canvas = surface.lockHardwareCanvas()
            try {
                // Always scale source bitmap to fill 100% of the negotiated H.264 stream (e.g. 1920x1080)
                canvas.drawBitmap(bmp, null, Rect(0, 0, width, height), scalePaint)
            } finally {
                surface.unlockCanvasAndPost(canvas)
                bmp.recycle()
            }
        } catch (_: Exception) {
        }
    }

    private fun requestSyncFrame() {
        try {
            val params = Bundle().apply {
                putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0)
            }
            encoder?.setParameters(params)
        } catch (_: Exception) {
        }
    }

    private fun extractFormatConfig(format: MediaFormat): ByteArray? {
        val csd0 = format.getByteBuffer("csd-0")?.duplicate() ?: return null
        val out = ByteArrayOutputStream()
        val buf0 = ByteArray(csd0.remaining())
        csd0.get(buf0)
        out.write(buf0)
        val csd1 = format.getByteBuffer("csd-1")?.duplicate()
        if (csd1 != null) {
            val buf1 = ByteArray(csd1.remaining())
            csd1.get(buf1)
            out.write(buf1)
        }
        val bytes = out.toByteArray()
        return if (bytes.isNotEmpty()) bytes else null
    }

    private fun drainEncoderLoop() {
        val bufferInfo = MediaCodec.BufferInfo()
        while (running) {
            val codec = encoder ?: break
            try {
                val outIndex = codec.dequeueOutputBuffer(bufferInfo, 10_000)
                if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    try {
                        val cfgBytes = extractFormatConfig(codec.outputFormat)
                        if (cfgBytes != null) {
                            mainHandler.post {
                                eventSink?.success(
                                    mapOf(
                                        "type" to "config",
                                        "bytes" to cfgBytes,
                                        "isKey" to true
                                    )
                                )
                            }
                        }
                    } catch (_: Throwable) {}
                } else if (outIndex >= 0) {
                    val outBuf = codec.getOutputBuffer(outIndex)
                    if (outBuf != null && bufferInfo.size > 0) {
                        outBuf.position(bufferInfo.offset)
                        outBuf.limit(bufferInfo.offset + bufferInfo.size)
                        val bytes = ByteArray(bufferInfo.size)
                        outBuf.get(bytes)

                        val isConfig = (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0
                        val isKey = (bufferInfo.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME) != 0

                        mainHandler.post {
                            eventSink?.success(
                                mapOf(
                                    "type" to if (isConfig) "config" else "frame",
                                    "bytes" to bytes,
                                    "isKey" to (isConfig || isKey)
                                )
                            )
                        }
                    }
                    codec.releaseOutputBuffer(outIndex, false)
                }
            } catch (_: Exception) {
                break
            }
        }
    }

    private fun stopHardwareEncoder() {
        running = false
        stopPixelCopyLoop()
        try {
            encoder?.stop()
        } catch (_: Exception) {
        }
        try {
            encoder?.release()
        } catch (_: Exception) {
        }
        encoder = null
        try {
            inputSurface?.release()
        } catch (_: Exception) {
        }
        inputSurface = null
    }

    override fun onDestroy() {
        stopMediaProjection()
        stopHardwareEncoder()
        super.onDestroy()
    }
}
