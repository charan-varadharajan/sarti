package app.sarti.sarti_mobile

import android.os.Build
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class MainActivity : FlutterFragmentActivity() {
    private val nativeAiScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.sarti/native_ai")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "availability" -> checkAvailability(result)
                    "generate" -> {
                        val prompt = call.argument<String>("prompt")
                        if (prompt.isNullOrBlank()) {
                            result.error("invalid_prompt", "A prompt is required.", null)
                        } else {
                            generateOnDevice(prompt, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun checkAvailability(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success("unsupported")
            return
        }
        nativeAiScope.launch {
            val model = Generation.getClient()
            try {
                result.success(statusName(model.checkStatus()))
            } catch (_: Exception) {
                result.success("unavailable")
            } finally {
                model.close()
            }
        }
    }

    private fun generateOnDevice(prompt: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error("unsupported", "On-device AI requires Android API 26 or newer.", null)
            return
        }
        nativeAiScope.launch {
            val model = Generation.getClient()
            try {
                if (model.checkStatus() != FeatureStatus.AVAILABLE) {
                    result.error("unavailable", "The on-device model is not ready.", null)
                    return@launch
                }
                val request =
                    generateContentRequest(
                        TextPart(prompt),
                    ) {
                        temperature = 0.0f
                        candidateCount = 1
                        maxOutputTokens = 256
                    }
                val response = model.generateContent(request)
                val content = response.candidates.firstOrNull()?.text
                if (content.isNullOrBlank()) {
                    result.error("empty_response", "The on-device model returned no content.", null)
                } else {
                    result.success(content)
                }
            } catch (_: Exception) {
                result.error("generation_failed", "On-device generation failed.", null)
            } finally {
                model.close()
            }
        }
    }

    private fun statusName(status: Int): String =
        when (status) {
            FeatureStatus.AVAILABLE -> "available"
            FeatureStatus.DOWNLOADABLE, FeatureStatus.DOWNLOADING -> "model_not_ready"
            FeatureStatus.UNAVAILABLE -> "unsupported"
            else -> "unavailable"
        }

    override fun onDestroy() {
        nativeAiScope.cancel()
        super.onDestroy()
    }
}
