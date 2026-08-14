package com.policedog.recognition.backend.api

import java.util.UUID

public data class BackendConfig(
    val maxBatchSize: Int = 50,
    val persistResults: Boolean = true,
)

public enum class BackendLifecycle {
    UNINITIALIZED,
    INITIALIZING,
    READY,
    FAILED,
    RELEASING,
    RELEASED,
}

public data class BackendState(
    val lifecycle: BackendLifecycle,
    val error: BackendError? = null,
)

public enum class ErrorCode {
    BACKEND_NOT_INITIALIZED,
    BACKEND_ALREADY_INITIALIZED,
    BACKEND_RELEASED,
    MODEL_FILE_MISSING,
    MODEL_HASH_MISMATCH,
    MODEL_LOAD_FAILED,
    UNSUPPORTED_DEVICE,
    INPUT_OPEN_FAILED,
    UNSUPPORTED_IMAGE_FORMAT,
    IMAGE_TOO_LARGE,
    NO_DOG_DETECTED,
    MULTIPLE_DOGS_DETECTED,
    INFERENCE_FAILED,
    STORAGE_FULL,
    QUEUE_FULL,
    BATCH_TOO_LARGE,
    INVALID_REQUEST,
    TASK_NOT_FOUND,
    BATCH_NOT_FOUND,
    TASK_CANCELLED,
    REPORT_EXPORT_FAILED,
    INTERNAL_ERROR,
}

public data class BackendError(
    val code: ErrorCode,
    val message: String,
    val retryable: Boolean = false,
    val diagnostic: String? = null,
)

public sealed interface BackendResult<out T> {
    public data class Success<T>(val value: T) : BackendResult<T>

    public data class Failure(val error: BackendError) : BackendResult<Nothing>
}

public data class TaskId(val value: String) {
    public companion object {
        public fun create(): TaskId = TaskId(UUID.randomUUID().toString())
    }
}

public data class BatchId(val value: String) {
    public companion object {
        public fun create(): BatchId = BatchId(UUID.randomUUID().toString())
    }
}

public enum class TaskPriority {
    INTERACTIVE,
    BATCH,
}

public data class RecognitionRequest(
    val source: String,
    val clientRequestId: String? = null,
    val saveOriginal: Boolean = false,
    val saveOverlay: Boolean = true,
    val priority: TaskPriority = TaskPriority.INTERACTIVE,
    val metadata: Map<String, String> = emptyMap(),
)

public data class BatchRecognitionRequest(
    val requests: List<RecognitionRequest>,
)

public enum class TaskState {
    QUEUED,
    RUNNING,
    CANCEL_REQUESTED,
    COMPLETED,
    FAILED,
    CANCELLED,
}

public enum class TaskStage {
    QUEUED,
    OPENING_INPUT,
    DECODING,
    DETECTING,
    ESTIMATING_POSE,
    CLASSIFYING,
    RENDERING,
    PERSISTING,
    FINISHED,
}

public data class TaskEvent(
    val taskId: TaskId,
    val state: TaskState,
    val stage: TaskStage,
    val progressPercent: Int,
    val result: RecognitionResult? = null,
    val error: BackendError? = null,
    val updatedAtEpochMillis: Long = System.currentTimeMillis(),
) {
    public val isTerminal: Boolean
        get() = state == TaskState.COMPLETED || state == TaskState.FAILED || state == TaskState.CANCELLED
}

public enum class BatchState {
    QUEUED,
    RUNNING,
    COMPLETED,
    CANCELLED,
    FAILED,
}

public data class BatchEvent(
    val batchId: BatchId,
    val state: BatchState,
    val total: Int,
    val completed: Int,
    val failed: Int,
    val cancelled: Int,
    val taskIds: List<TaskId>,
    val error: BackendError? = null,
    val updatedAtEpochMillis: Long = System.currentTimeMillis(),
) {
    public val finished: Int
        get() = completed + failed + cancelled

    public val progressPercent: Int
        get() = if (total == 0) 100 else (finished * 100 / total)
}

public enum class CancelResult {
    CANCELLED,
    REQUESTED,
    ALREADY_FINISHED,
    NOT_FOUND,
}

public enum class ActionLabel {
    STANDING,
    SITTING,
    LYING,
    UNKNOWN,
}

public data class BoundingBox(
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float,
    val confidence: Float,
)

public data class Keypoint(
    val index: Int,
    val name: String,
    val x: Float,
    val y: Float,
    val confidence: Float,
)

public enum class QualityStatus {
    ACCEPTED,
    LOW_CONFIDENCE,
    INSUFFICIENT_KEYPOINTS,
    UNKNOWN_POSE,
}

public enum class RecognitionWarning {
    LOW_DETECTION_CONFIDENCE,
    LOW_KEYPOINT_CONFIDENCE,
    LOW_ACTION_CONFIDENCE,
    PARTIAL_BODY_VISIBLE,
}

public data class InferenceTiming(
    val totalMillis: Long,
    val detectionMillis: Long,
    val poseMillis: Long,
    val classificationMillis: Long,
)

public data class ModelInfo(
    val detectorName: String,
    val poseModelName: String,
    val actionModelName: String,
    val version: String,
)

public data class RecognitionResult(
    val recordId: String,
    val taskId: TaskId,
    val source: String,
    val action: ActionLabel,
    val actionScores: Map<ActionLabel, Float>,
    val dogBox: BoundingBox?,
    val keypoints: List<Keypoint>,
    val quality: QualityStatus,
    val warnings: List<RecognitionWarning>,
    val originalLocation: String? = null,
    val overlayLocation: String? = null,
    val timing: InferenceTiming,
    val modelInfo: ModelInfo,
    val createdAtEpochMillis: Long = System.currentTimeMillis(),
)

public data class RecognitionRecord(
    val result: RecognitionResult,
)

public data class HistoryQuery(
    val offset: Int = 0,
    val limit: Int = 50,
)

public data class Page<T>(
    val items: List<T>,
    val offset: Int,
    val limit: Int,
    val total: Int,
)

public enum class ReportFormat {
    JSON,
    CSV,
    PDF,
}

public data class ReportRequest(
    val recordIds: List<String>,
    val format: ReportFormat,
)

public data class ReportResult(
    val location: String,
    val mimeType: String,
    val recordCount: Int,
)

