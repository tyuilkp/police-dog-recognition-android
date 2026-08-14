package com.policedog.recognition.backend.engine

import com.policedog.recognition.backend.api.BackendConfig
import com.policedog.recognition.backend.api.BackendError
import com.policedog.recognition.backend.api.RecognitionRequest
import com.policedog.recognition.backend.api.RecognitionResult
import com.policedog.recognition.backend.api.TaskId
import com.policedog.recognition.backend.api.TaskStage

public interface RecognitionEngine {
    public suspend fun initialize(config: BackendConfig)

    public suspend fun infer(
        taskId: TaskId,
        request: RecognitionRequest,
        onProgress: suspend (stage: TaskStage, progressPercent: Int) -> Unit,
    ): RecognitionResult

    public suspend fun release()
}

public class BackendOperationException(
    public val backendError: BackendError,
) : RuntimeException(backendError.message)

