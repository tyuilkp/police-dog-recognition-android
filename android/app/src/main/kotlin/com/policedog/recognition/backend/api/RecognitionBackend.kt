package com.policedog.recognition.backend.api

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow

public interface RecognitionBackend {
    public val backendState: StateFlow<BackendState>

    public suspend fun initialize(config: BackendConfig = BackendConfig()): BackendResult<Unit>

    public suspend fun submit(request: RecognitionRequest): BackendResult<TaskId>

    public suspend fun submitBatch(request: BatchRecognitionRequest): BackendResult<BatchId>

    public fun observeTask(taskId: TaskId): Flow<TaskEvent>

    public fun observeBatch(batchId: BatchId): Flow<BatchEvent>

    public suspend fun cancelTask(taskId: TaskId): CancelResult

    public suspend fun cancelBatch(batchId: BatchId): CancelResult

    public suspend fun getResult(taskId: TaskId): RecognitionResult?

    public suspend fun queryHistory(query: HistoryQuery = HistoryQuery()): Page<RecognitionRecord>

    public suspend fun deleteRecords(recordIds: List<String>): BackendResult<Unit>

    public suspend fun exportReport(request: ReportRequest): BackendResult<ReportResult>

    public suspend fun release(): BackendResult<Unit>
}

