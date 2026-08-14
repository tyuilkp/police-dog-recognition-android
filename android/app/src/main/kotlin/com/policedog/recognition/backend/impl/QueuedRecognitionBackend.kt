package com.policedog.recognition.backend.impl

import com.policedog.recognition.backend.api.BackendConfig
import com.policedog.recognition.backend.api.BackendError
import com.policedog.recognition.backend.api.BackendLifecycle
import com.policedog.recognition.backend.api.BackendResult
import com.policedog.recognition.backend.api.BackendState
import com.policedog.recognition.backend.api.BatchEvent
import com.policedog.recognition.backend.api.BatchId
import com.policedog.recognition.backend.api.BatchRecognitionRequest
import com.policedog.recognition.backend.api.BatchState
import com.policedog.recognition.backend.api.CancelResult
import com.policedog.recognition.backend.api.ErrorCode
import com.policedog.recognition.backend.api.HistoryQuery
import com.policedog.recognition.backend.api.Page
import com.policedog.recognition.backend.api.RecognitionBackend
import com.policedog.recognition.backend.api.RecognitionRecord
import com.policedog.recognition.backend.api.RecognitionRequest
import com.policedog.recognition.backend.api.RecognitionResult
import com.policedog.recognition.backend.api.ReportRequest
import com.policedog.recognition.backend.api.ReportResult
import com.policedog.recognition.backend.api.TaskEvent
import com.policedog.recognition.backend.api.TaskId
import com.policedog.recognition.backend.api.TaskStage
import com.policedog.recognition.backend.api.TaskState
import com.policedog.recognition.backend.engine.BackendOperationException
import com.policedog.recognition.backend.engine.RecognitionEngine
import com.policedog.recognition.backend.report.ReportExporter
import com.policedog.recognition.backend.storage.RecognitionStore
import java.util.ArrayDeque
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

public class QueuedRecognitionBackend(
    private val engine: RecognitionEngine,
    private val store: RecognitionStore,
    private val reportExporter: ReportExporter,
    private val queueCapacity: Int = 16,
    private val dispatchers: BackendDispatchers = BackendDispatchers.createDefault(),
) : RecognitionBackend {
    private val stateFlow: MutableStateFlow<BackendState> = MutableStateFlow(
        BackendState(BackendLifecycle.UNINITIALIZED),
    )
    override val backendState: StateFlow<BackendState> = stateFlow.asStateFlow()

    private val lifecycleMutex: Mutex = Mutex()
    private val queueMutex: Mutex = Mutex()
    private val queueSignal: Channel<Unit> = Channel(Channel.CONFLATED)
    private val queue: ArrayDeque<TaskControl> = ArrayDeque()
    private val tasks: ConcurrentHashMap<TaskId, TaskControl> = ConcurrentHashMap()
    private val batches: ConcurrentHashMap<BatchId, BatchControl> = ConcurrentHashMap()
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + dispatchers.coordinator)
    private val workerJob: Job

    @Volatile
    private var acceptingTasks: Boolean = false

    @Volatile
    private var config: BackendConfig = BackendConfig()

    init {
        require(queueCapacity > 0) { "queueCapacity must be positive" }
        workerJob = scope.launch { workerLoop() }
    }

    override suspend fun initialize(config: BackendConfig): BackendResult<Unit> = lifecycleMutex.withLock {
        when (stateFlow.value.lifecycle) {
            BackendLifecycle.READY,
            BackendLifecycle.INITIALIZING,
            -> return BackendResult.Failure(
                BackendError(ErrorCode.BACKEND_ALREADY_INITIALIZED, "Backend is already initialized"),
            )

            BackendLifecycle.RELEASING,
            BackendLifecycle.RELEASED,
            -> return BackendResult.Failure(
                BackendError(ErrorCode.BACKEND_RELEASED, "Backend has been released"),
            )

            else -> Unit
        }

        stateFlow.value = BackendState(BackendLifecycle.INITIALIZING)
        return try {
            withContext(dispatchers.inference) { engine.initialize(config) }
            this.config = config
            acceptingTasks = true
            stateFlow.value = BackendState(BackendLifecycle.READY)
            BackendResult.Success(Unit)
        } catch (exception: BackendOperationException) {
            stateFlow.value = BackendState(BackendLifecycle.FAILED, exception.backendError)
            BackendResult.Failure(exception.backendError)
        } catch (exception: Throwable) {
            val error = internalError("Failed to initialize backend", exception)
            stateFlow.value = BackendState(BackendLifecycle.FAILED, error)
            BackendResult.Failure(error)
        }
    }

    override suspend fun submit(request: RecognitionRequest): BackendResult<TaskId> {
        validateReady()?.let { return BackendResult.Failure(it) }
        if (request.source.isBlank()) {
            return BackendResult.Failure(
                BackendError(ErrorCode.INVALID_REQUEST, "Image source must not be blank"),
            )
        }

        val control = newTask(request, batchId = null)
        val accepted = queueMutex.withLock {
            if (!acceptingTasks || queue.size >= queueCapacity) {
                false
            } else {
                tasks[control.id] = control
                queue.addLast(control)
                true
            }
        }
        if (!accepted) {
            return BackendResult.Failure(queueRejectedError())
        }
        queueSignal.trySend(Unit)
        return BackendResult.Success(control.id)
    }

    override suspend fun submitBatch(request: BatchRecognitionRequest): BackendResult<BatchId> {
        validateReady()?.let { return BackendResult.Failure(it) }
        if (request.requests.isEmpty() || request.requests.any { it.source.isBlank() }) {
            return BackendResult.Failure(
                BackendError(ErrorCode.INVALID_REQUEST, "Batch must contain non-empty image sources"),
            )
        }
        if (request.requests.size > config.maxBatchSize) {
            return BackendResult.Failure(
                BackendError(
                    ErrorCode.BATCH_TOO_LARGE,
                    "Batch size ${request.requests.size} exceeds limit ${config.maxBatchSize}",
                ),
            )
        }

        val batchId = BatchId.create()
        val controls = request.requests.map { newTask(it, batchId) }
        val batchControl = BatchControl(batchId, controls.map { it.id })
        val accepted = queueMutex.withLock {
            if (!acceptingTasks || queue.size + controls.size > queueCapacity) {
                false
            } else {
                batches[batchId] = batchControl
                controls.forEach { control ->
                    tasks[control.id] = control
                    queue.addLast(control)
                }
                true
            }
        }
        if (!accepted) {
            return BackendResult.Failure(queueRejectedError())
        }
        queueSignal.trySend(Unit)
        return BackendResult.Success(batchId)
    }

    override fun observeTask(taskId: TaskId): Flow<TaskEvent> = tasks[taskId]?.events?.asStateFlow()
        ?: flowOf(
            TaskEvent(
                taskId = taskId,
                state = TaskState.FAILED,
                stage = TaskStage.FINISHED,
                progressPercent = 100,
                error = BackendError(ErrorCode.TASK_NOT_FOUND, "Task ${taskId.value} was not found"),
            ),
        )

    override fun observeBatch(batchId: BatchId): Flow<BatchEvent> = batches[batchId]?.events?.asStateFlow()
        ?: flowOf(
            BatchEvent(
                batchId = batchId,
                state = BatchState.FAILED,
                total = 0,
                completed = 0,
                failed = 0,
                cancelled = 0,
                taskIds = emptyList(),
                error = BackendError(ErrorCode.BATCH_NOT_FOUND, "Batch ${batchId.value} was not found"),
            ),
        )

    override suspend fun cancelTask(taskId: TaskId): CancelResult {
        val control = tasks[taskId] ?: return CancelResult.NOT_FOUND
        if (control.events.value.isTerminal) return CancelResult.ALREADY_FINISHED
        control.cancelRequested.set(true)

        val removed = queueMutex.withLock { queue.remove(control) }
        return if (removed) {
            completeTask(control, cancelledEvent(control))
            CancelResult.CANCELLED
        } else {
            val current = control.events.value
            control.events.value = current.copy(
                state = TaskState.CANCEL_REQUESTED,
                updatedAtEpochMillis = System.currentTimeMillis(),
            )
            CancelResult.REQUESTED
        }
    }

    override suspend fun cancelBatch(batchId: BatchId): CancelResult {
        val batch = batches[batchId] ?: return CancelResult.NOT_FOUND
        val results = batch.taskIds.map { cancelTask(it) }
        return when {
            results.all { it == CancelResult.ALREADY_FINISHED } -> CancelResult.ALREADY_FINISHED
            results.any { it == CancelResult.REQUESTED } -> CancelResult.REQUESTED
            else -> CancelResult.CANCELLED
        }
    }

    override suspend fun getResult(taskId: TaskId): RecognitionResult? =
        withContext(dispatchers.io) { store.findByTaskId(taskId.value)?.result }

    override suspend fun queryHistory(query: HistoryQuery): Page<RecognitionRecord> =
        withContext(dispatchers.io) { store.query(query) }

    override suspend fun deleteRecords(recordIds: List<String>): BackendResult<Unit> = try {
        withContext(dispatchers.io) { store.delete(recordIds) }
        BackendResult.Success(Unit)
    } catch (exception: Throwable) {
        BackendResult.Failure(internalError("Failed to delete records", exception))
    }

    override suspend fun exportReport(request: ReportRequest): BackendResult<ReportResult> = try {
        val records = withContext(dispatchers.io) { store.findByRecordIds(request.recordIds) }
        val result = withContext(dispatchers.io) { reportExporter.export(records, request.format) }
        BackendResult.Success(result)
    } catch (exception: BackendOperationException) {
        BackendResult.Failure(exception.backendError)
    } catch (exception: Throwable) {
        BackendResult.Failure(
            BackendError(
                ErrorCode.REPORT_EXPORT_FAILED,
                "Failed to export report",
                retryable = true,
                diagnostic = exception.message,
            ),
        )
    }

    override suspend fun release(): BackendResult<Unit> {
        lifecycleMutex.withLock {
            if (stateFlow.value.lifecycle == BackendLifecycle.RELEASED) {
                return BackendResult.Success(Unit)
            }
            acceptingTasks = false
            stateFlow.value = BackendState(BackendLifecycle.RELEASING)
        }

        val queuedTasks = queueMutex.withLock {
            buildList {
                while (queue.isNotEmpty()) add(queue.removeFirst())
            }
        }
        queuedTasks.forEach { control ->
            control.cancelRequested.set(true)
            completeTask(control, cancelledEvent(control))
        }
        tasks.values.filterNot { it.events.value.isTerminal }.forEach { it.cancelRequested.set(true) }

        workerJob.cancelAndJoin()
        return try {
            withContext(dispatchers.inference) { engine.release() }
            stateFlow.value = BackendState(BackendLifecycle.RELEASED)
            scope.cancel()
            dispatchers.close()
            BackendResult.Success(Unit)
        } catch (exception: Throwable) {
            val error = internalError("Failed to release backend", exception)
            stateFlow.value = BackendState(BackendLifecycle.FAILED, error)
            scope.cancel()
            dispatchers.close()
            BackendResult.Failure(error)
        }
    }

    private suspend fun workerLoop(): Unit {
        for (ignored in queueSignal) {
            while (true) {
                val control = queueMutex.withLock {
                    if (queue.isEmpty()) null else queue.removeFirst()
                } ?: break
                process(control)
            }
        }
    }

    private suspend fun process(control: TaskControl): Unit {
        if (control.cancelRequested.get()) {
            completeTask(control, cancelledEvent(control))
            return
        }
        markBatchRunning(control.batchId)
        control.events.value = control.events.value.copy(
            state = TaskState.RUNNING,
            stage = TaskStage.OPENING_INPUT,
            progressPercent = 1,
            updatedAtEpochMillis = System.currentTimeMillis(),
        )

        try {
            val result = withContext(dispatchers.inference) {
                engine.infer(control.id, control.request) { stage, progress ->
                    if (control.cancelRequested.get()) throw TaskCancelledException()
                    control.events.value = TaskEvent(
                        taskId = control.id,
                        state = TaskState.RUNNING,
                        stage = stage,
                        progressPercent = progress.coerceIn(0, 99),
                    )
                }
            }
            if (control.cancelRequested.get()) throw TaskCancelledException()

            control.events.value = TaskEvent(
                taskId = control.id,
                state = TaskState.RUNNING,
                stage = TaskStage.PERSISTING,
                progressPercent = 99,
            )
            if (config.persistResults) {
                withContext(dispatchers.io) { store.save(RecognitionRecord(result)) }
            }
            if (control.cancelRequested.get()) throw TaskCancelledException()
            completeTask(
                control,
                TaskEvent(
                    taskId = control.id,
                    state = TaskState.COMPLETED,
                    stage = TaskStage.FINISHED,
                    progressPercent = 100,
                    result = result,
                ),
            )
        } catch (exception: TaskCancelledException) {
            completeTask(control, cancelledEvent(control))
        } catch (exception: BackendOperationException) {
            completeTask(control, failedEvent(control, exception.backendError))
        } catch (exception: CancellationException) {
            completeTask(control, cancelledEvent(control))
        } catch (exception: Throwable) {
            completeTask(control, failedEvent(control, internalError("Inference failed", exception)))
        }
    }

    private fun newTask(request: RecognitionRequest, batchId: BatchId?): TaskControl {
        val id = TaskId.create()
        return TaskControl(
            id = id,
            request = request,
            batchId = batchId,
            events = MutableStateFlow(
                TaskEvent(
                    taskId = id,
                    state = TaskState.QUEUED,
                    stage = TaskStage.QUEUED,
                    progressPercent = 0,
                ),
            ),
        )
    }

    private fun completeTask(control: TaskControl, event: TaskEvent): Unit {
        if (!control.terminalNotified.compareAndSet(false, true)) return
        control.events.value = event
        control.batchId?.let { batchId -> updateBatchTerminal(batchId, event.state) }
    }

    private fun markBatchRunning(batchId: BatchId?): Unit {
        val batch = batchId?.let(batches::get) ?: return
        synchronized(batch) {
            if (batch.events.value.state == BatchState.QUEUED) {
                batch.events.value = batch.events.value.copy(
                    state = BatchState.RUNNING,
                    updatedAtEpochMillis = System.currentTimeMillis(),
                )
            }
        }
    }

    private fun updateBatchTerminal(batchId: BatchId, taskState: TaskState): Unit {
        val batch = batches[batchId] ?: return
        synchronized(batch) {
            when (taskState) {
                TaskState.COMPLETED -> batch.completed += 1
                TaskState.FAILED -> batch.failed += 1
                TaskState.CANCELLED -> batch.cancelled += 1
                else -> return
            }
            val finished = batch.completed + batch.failed + batch.cancelled
            val nextState = when {
                finished < batch.taskIds.size -> BatchState.RUNNING
                batch.cancelled == batch.taskIds.size -> BatchState.CANCELLED
                else -> BatchState.COMPLETED
            }
            batch.events.value = BatchEvent(
                batchId = batch.id,
                state = nextState,
                total = batch.taskIds.size,
                completed = batch.completed,
                failed = batch.failed,
                cancelled = batch.cancelled,
                taskIds = batch.taskIds,
            )
        }
    }

    private fun validateReady(): BackendError? = when (stateFlow.value.lifecycle) {
        BackendLifecycle.READY -> null
        BackendLifecycle.RELEASING,
        BackendLifecycle.RELEASED,
        -> BackendError(ErrorCode.BACKEND_RELEASED, "Backend is not accepting tasks")

        else -> BackendError(ErrorCode.BACKEND_NOT_INITIALIZED, "Backend is not initialized")
    }

    private fun queueRejectedError(): BackendError = if (!acceptingTasks) {
        BackendError(ErrorCode.BACKEND_RELEASED, "Backend is not accepting tasks")
    } else {
        BackendError(ErrorCode.QUEUE_FULL, "Inference queue is full", retryable = true)
    }

    private fun cancelledEvent(control: TaskControl): TaskEvent = TaskEvent(
        taskId = control.id,
        state = TaskState.CANCELLED,
        stage = TaskStage.FINISHED,
        progressPercent = 100,
        error = BackendError(ErrorCode.TASK_CANCELLED, "Task was cancelled"),
    )

    private fun failedEvent(control: TaskControl, error: BackendError): TaskEvent = TaskEvent(
        taskId = control.id,
        state = TaskState.FAILED,
        stage = TaskStage.FINISHED,
        progressPercent = 100,
        error = error,
    )

    private fun internalError(message: String, exception: Throwable): BackendError = BackendError(
        code = ErrorCode.INTERNAL_ERROR,
        message = message,
        retryable = false,
        diagnostic = exception.message ?: exception::class.java.name,
    )

    private class TaskCancelledException : RuntimeException()

    private data class TaskControl(
        val id: TaskId,
        val request: RecognitionRequest,
        val batchId: BatchId?,
        val events: MutableStateFlow<TaskEvent>,
        val cancelRequested: AtomicBoolean = AtomicBoolean(false),
        val terminalNotified: AtomicBoolean = AtomicBoolean(false),
    )

    private class BatchControl(
        val id: BatchId,
        val taskIds: List<TaskId>,
    ) {
        var completed: Int = 0
        var failed: Int = 0
        var cancelled: Int = 0
        val events: MutableStateFlow<BatchEvent> = MutableStateFlow(
            BatchEvent(
                batchId = id,
                state = BatchState.QUEUED,
                total = taskIds.size,
                completed = 0,
                failed = 0,
                cancelled = 0,
                taskIds = taskIds,
            ),
        )
    }
}
