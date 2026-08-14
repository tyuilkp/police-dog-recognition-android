package com.policedog.recognition.backend.mock

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
import kotlinx.coroutines.delay

public data class MockEngineConfig(
    val stageDelayMillis: Long = 10,
)

public class MockRecognitionEngine(
    private val mockConfig: MockEngineConfig = MockEngineConfig(),
) : RecognitionEngine {
    private var initialized: Boolean = false

    override suspend fun initialize(config: BackendConfig): Unit {
        initialized = true
    }

    override suspend fun infer(
        taskId: TaskId,
        request: RecognitionRequest,
        onProgress: suspend (stage: TaskStage, progressPercent: Int) -> Unit,
    ): RecognitionResult {
        check(initialized) { "Mock engine is not initialized" }
        val source = request.source.lowercase()
        emitStage(onProgress, TaskStage.OPENING_INPUT, 5)
        if ("broken" in source) {
            throw BackendOperationException(
                BackendError(ErrorCode.INPUT_OPEN_FAILED, "Mock input could not be opened"),
            )
        }
        emitStage(onProgress, TaskStage.DECODING, 15)
        emitStage(onProgress, TaskStage.DETECTING, 40)
        if ("nodog" in source) {
            throw BackendOperationException(
                BackendError(ErrorCode.NO_DOG_DETECTED, "No dog was detected in the image"),
            )
        }
        if ("multidog" in source) {
            throw BackendOperationException(
                BackendError(ErrorCode.MULTIPLE_DOGS_DETECTED, "Multiple dogs were detected"),
            )
        }
        emitStage(onProgress, TaskStage.ESTIMATING_POSE, 70)
        emitStage(onProgress, TaskStage.CLASSIFYING, 85)

        val action = when {
            "stand" in source || "standing" in source -> ActionLabel.STANDING
            "sit" in source || "sitting" in source -> ActionLabel.SITTING
            "lie" in source || "lying" in source -> ActionLabel.LYING
            else -> ActionLabel.UNKNOWN
        }
        val actionScores = scoresFor(action)
        emitStage(onProgress, TaskStage.RENDERING, 95)
        return RecognitionResult(
            recordId = taskId.value,
            taskId = taskId,
            source = request.source,
            action = action,
            actionScores = actionScores,
            dogBox = BoundingBox(0.15f, 0.12f, 0.85f, 0.88f, 0.94f),
            keypoints = mockKeypoints(),
            quality = if (action == ActionLabel.UNKNOWN) QualityStatus.UNKNOWN_POSE else QualityStatus.ACCEPTED,
            warnings = if (action == ActionLabel.UNKNOWN) {
                listOf(RecognitionWarning.LOW_ACTION_CONFIDENCE)
            } else {
                emptyList()
            },
            originalLocation = if (request.saveOriginal) request.source else null,
            overlayLocation = if (request.saveOverlay) "memory://overlay/${taskId.value}.jpg" else null,
            timing = InferenceTiming(
                totalMillis = mockConfig.stageDelayMillis * 6,
                detectionMillis = mockConfig.stageDelayMillis,
                poseMillis = mockConfig.stageDelayMillis,
                classificationMillis = mockConfig.stageDelayMillis,
            ),
            modelInfo = ModelInfo(
                detectorName = "superanimal_quadruped_ssdlite",
                poseModelName = "superanimal_quadruped_rtmpose_s",
                actionModelName = "mock-action-classifier",
                version = "mock-0.1.0",
            ),
        )
    }

    override suspend fun release(): Unit {
        initialized = false
    }

    private suspend fun emitStage(
        callback: suspend (TaskStage, Int) -> Unit,
        stage: TaskStage,
        progress: Int,
    ): Unit {
        if (mockConfig.stageDelayMillis > 0) delay(mockConfig.stageDelayMillis)
        callback(stage, progress)
    }

    private fun scoresFor(action: ActionLabel): Map<ActionLabel, Float> {
        val labels = ActionLabel.entries
        return labels.associateWith { label ->
            when {
                action == ActionLabel.UNKNOWN -> 0.25f
                label == action -> 0.91f
                label == ActionLabel.UNKNOWN -> 0.03f
                else -> 0.02f
            }
        }
    }

    private fun mockKeypoints(): List<Keypoint> = List(39) { index ->
        Keypoint(
            index = index,
            name = "quadruped_keypoint_$index",
            x = 0.2f + (index % 8) * 0.075f,
            y = 0.2f + (index / 8) * 0.12f,
            confidence = 0.9f,
        )
    }
}

