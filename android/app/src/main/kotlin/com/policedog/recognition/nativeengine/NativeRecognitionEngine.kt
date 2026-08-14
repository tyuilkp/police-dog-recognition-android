package com.policedog.recognition.nativeengine

import android.content.Context
import com.policedog.recognition.backend.api.ActionLabel
import com.policedog.recognition.backend.api.BackendConfig
import com.policedog.recognition.backend.api.BackendError
import com.policedog.recognition.backend.api.BoundingBox
import com.policedog.recognition.backend.api.ErrorCode
import com.policedog.recognition.backend.api.InferenceTiming
import com.policedog.recognition.backend.api.Keypoint
import com.policedog.recognition.backend.api.ModelInfo
import com.policedog.recognition.backend.api.QualityStatus
import com.policedog.recognition.backend.api.RecognitionRequest
import com.policedog.recognition.backend.api.RecognitionResult
import com.policedog.recognition.backend.api.RecognitionWarning
import com.policedog.recognition.backend.api.TaskId
import com.policedog.recognition.backend.api.TaskStage
import com.policedog.recognition.backend.engine.BackendOperationException
import com.policedog.recognition.backend.engine.RecognitionEngine
import kotlinx.coroutines.CancellationException
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/** Android implementation of the backend engine backed by the C++ JNI library. */
internal class NativeRecognitionEngine(context: Context) : RecognitionEngine {
    private val applicationContext = context.applicationContext
    private var nativeHandle: Long = 0L

    override suspend fun initialize(config: BackendConfig) {
        if (nativeHandle != 0L) {
            throw nativeError(ErrorCode.BACKEND_ALREADY_INITIALIZED, "Native engine is already initialized")
        }

        try {
            val handle = NativeInferenceBridge.create()
            if (handle == 0L) {
                throw nativeError(ErrorCode.MODEL_LOAD_FAILED, "Could not allocate the native engine")
            }
            nativeHandle = handle
            requireSuccess(
                NativeInferenceBridge.initialize(handle, applicationContext.assets, MODEL_ROOT),
                ErrorCode.MODEL_LOAD_FAILED,
            )
        } catch (error: BackendOperationException) {
            release()
            throw error
        } catch (error: UnsatisfiedLinkError) {
            release()
            throw nativeError(ErrorCode.MODEL_LOAD_FAILED, "Native inference library could not be loaded", error)
        }
    }

    override suspend fun infer(
        taskId: TaskId,
        request: RecognitionRequest,
        onProgress: suspend (stage: TaskStage, progressPercent: Int) -> Unit,
    ): RecognitionResult {
        val handle = nativeHandle
        if (handle == 0L) {
            throw nativeError(ErrorCode.BACKEND_NOT_INITIALIZED, "Native engine is not initialized")
        }

        onProgress(TaskStage.OPENING_INPUT, 5)
        val input = AndroidInputResolver.resolve(applicationContext, request.source, taskId)
        var bitmap: android.graphics.Bitmap? = null
        try {
            onProgress(TaskStage.DECODING, 15)
            val decodedBitmap = AndroidImageDecoder.decode(input.path)
            bitmap = decodedBitmap
            onProgress(TaskStage.DETECTING, 40)
            val payload = requireSuccess(
                NativeInferenceBridge.infer(handle, decodedBitmap),
                ErrorCode.INFERENCE_FAILED,
            )
            onProgress(TaskStage.ESTIMATING_POSE, 70)
            onProgress(TaskStage.CLASSIFYING, 85)
            onProgress(TaskStage.RENDERING, 95)
            return payload.toRecognitionResult(taskId, request)
        } catch (error: BackendOperationException) {
            throw error
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw nativeError(ErrorCode.INFERENCE_FAILED, "Native inference failed", error)
        } finally {
            bitmap?.recycle()
            if (input.deleteAfterUse) runCatching { java.io.File(input.path).delete() }
        }
    }

    override suspend fun release() {
        val handle = nativeHandle
        nativeHandle = 0L
        NativeInferenceBridge.release(handle)
    }

    private fun requireSuccess(payload: String, fallbackCode: ErrorCode): JSONObject {
        val json = try {
            JSONObject(payload)
        } catch (error: JSONException) {
            throw nativeError(fallbackCode, "Native engine returned malformed JSON", error)
        }
        if (!json.optBoolean("ok", false)) {
            val code = enumValueOrDefault(json.optString("errorCode"), fallbackCode)
            throw nativeError(code, json.optString("message", "Native operation failed"))
        }
        return json
    }

    private fun JSONObject.toRecognitionResult(
        taskId: TaskId,
        request: RecognitionRequest,
    ): RecognitionResult {
        val action = enumValueOrDefault(optString("action"), ActionLabel.UNKNOWN)
        val scoreJson = optJSONObject("actionScores") ?: JSONObject()
        val scores = ActionLabel.entries.associateWith { label ->
            scoreJson.optDouble(label.name, if (label == ActionLabel.UNKNOWN) 1.0 else 0.0).toFloat()
        }
        val timingJson = optJSONObject("timing") ?: JSONObject()
        val modelJson = optJSONObject("modelInfo") ?: JSONObject()

        return RecognitionResult(
            recordId = taskId.value,
            taskId = taskId,
            source = request.source,
            action = action,
            actionScores = scores,
            dogBox = optJSONObject("dogBox")?.toBoundingBox(),
            keypoints = optJSONArray("keypoints").toKeypoints(),
            quality = enumValueOrDefault(optString("quality"), QualityStatus.UNKNOWN_POSE),
            warnings = optJSONArray("warnings").toWarnings(),
            originalLocation = request.source.takeIf { request.saveOriginal },
            overlayLocation = null,
            timing = InferenceTiming(
                totalMillis = timingJson.optLong("totalMillis"),
                detectionMillis = timingJson.optLong("detectionMillis"),
                poseMillis = timingJson.optLong("poseMillis"),
                classificationMillis = timingJson.optLong("classificationMillis"),
            ),
            modelInfo = ModelInfo(
                detectorName = modelJson.optString("detectorName", "not-loaded"),
                poseModelName = modelJson.optString("poseModelName", "not-loaded"),
                actionModelName = modelJson.optString("actionModelName", "not-loaded"),
                version = modelJson.optString("version", "native-scaffold-unknown"),
            ),
        )
    }

    private fun JSONObject.toBoundingBox(): BoundingBox = BoundingBox(
        left = optDouble("left").toFloat(),
        top = optDouble("top").toFloat(),
        right = optDouble("right").toFloat(),
        bottom = optDouble("bottom").toFloat(),
        confidence = optDouble("confidence").toFloat(),
    )

    private fun JSONArray?.toKeypoints(): List<Keypoint> = this?.let { array ->
        List(array.length()) { index ->
            val item = array.getJSONObject(index)
            Keypoint(
                index = item.optInt("index", index),
                name = item.optString("name", "quadruped_keypoint_$index"),
                x = item.optDouble("x").toFloat(),
                y = item.optDouble("y").toFloat(),
                confidence = item.optDouble("confidence").toFloat(),
            )
        }
    } ?: emptyList()

    private fun JSONArray?.toWarnings(): List<RecognitionWarning> = this?.let { array ->
        buildList {
            for (index in 0 until array.length()) {
                enumValueOrNull<RecognitionWarning>(array.optString(index))?.let(::add)
            }
        }
    } ?: emptyList()

    private fun nativeError(
        code: ErrorCode,
        message: String,
        cause: Throwable? = null,
    ): BackendOperationException = BackendOperationException(
        BackendError(
            code = code,
            message = message,
            retryable = code == ErrorCode.INFERENCE_FAILED,
            diagnostic = cause?.javaClass?.simpleName,
        ),
    )

    private inline fun <reified T : Enum<T>> enumValueOrDefault(value: String, fallback: T): T =
        enumValueOrNull<T>(value) ?: fallback

    private inline fun <reified T : Enum<T>> enumValueOrNull(value: String): T? =
        enumValues<T>().firstOrNull { it.name == value }

    private companion object {
        const val MODEL_ROOT = "models"
    }
}
