package com.example.police_dog_recognition_frontend.bridge

import com.policedog.recognition.backend.api.BackendResult
import com.policedog.recognition.backend.api.BatchId
import com.policedog.recognition.backend.api.BatchState
import com.policedog.recognition.backend.api.CancelResult
import com.policedog.recognition.backend.api.ErrorCode
import com.policedog.recognition.backend.api.RecognitionBackend
import com.policedog.recognition.backend.api.TaskId
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/**
 * Flutter <-> pdr backend-core 的 MethodChannel / EventChannel 桥接。
 *
 * MethodChannel: com.policedog.recognition/backend
 * EventChannel : com.policedog.recognition/backend/events/{task|batch}/{id}
 *   （由 registerEventObserver 动态注册，支持多个任务/批次并发观察）
 */
class BackendBridge(private val messenger: BinaryMessenger) {

    companion object {
        const val CHANNEL = "com.policedog.recognition/backend"
        const val EVENT_CHANNEL_PREFIX = "com.policedog.recognition/backend/events"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val eventChannels = ConcurrentHashMap<String, EventChannel>()
    private val eventJobs = ConcurrentHashMap<String, Job>()

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            handle(call, result)
        }
    }

    private val backend: RecognitionBackend
        get() = BackendHolder.get()

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> scope.launch { initialize(call, result) }
            "getState" -> result.success(BackendJson.stateToJson(backend.backendState.value).toString())
            "submit" -> scope.launch { submit(call, result) }
            "submitBatch" -> scope.launch { submitBatch(call, result) }
            "cancelTask" -> scope.launch { cancelTask(call, result) }
            "cancelBatch" -> scope.launch { cancelBatch(call, result) }
            "getResult" -> scope.launch { getResult(call, result) }
            "queryHistory" -> scope.launch { queryHistory(call, result) }
            "deleteRecords" -> scope.launch { deleteRecords(call, result) }
            "exportReport" -> scope.launch { exportReport(call, result) }
            "release" -> scope.launch { release(result) }
            "registerEventObserver" -> registerEventObserver(call, result)
            else -> result.notImplemented()
        }
    }

    // ---------- 命令 ----------

    private suspend fun initialize(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
        val config = BackendJson.configFromJson(JSONObject(args))
        val res = backend.initialize(config)
        result.success(
            BackendJson.resultToJson(
                success = res is BackendResult.Success,
                error = (res as? BackendResult.Failure)?.error,
                value = null,
            ).toString(),
        )
    }

    private suspend fun submit(call: MethodCall, result: MethodChannel.Result) {
        val request = BackendJson.requestFromJson(JSONObject(call.arguments as? Map<*, *>))
        val res = backend.submit(request)
        val value = (res as? BackendResult.Success)?.value?.let { JSONObject().put("taskId", it.value) }
        result.success(
            BackendJson.resultToJson(
                success = res is BackendResult.Success,
                error = (res as? BackendResult.Failure)?.error,
                value = value,
            ).toString(),
        )
    }

    private suspend fun submitBatch(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
        val requests = JSONArray()
        (args["requests"] as? List<*>)?.forEach { item ->
            requests.put(JSONObject(item as? Map<*, *> ?: emptyMap<String, Any?>()))
        }
        val res = backend.submitBatch(BackendJson.batchRequestFromJson(requests))
        val value = (res as? BackendResult.Success)?.value?.let { JSONObject().put("batchId", it.value) }
        result.success(
            BackendJson.resultToJson(
                success = res is BackendResult.Success,
                error = (res as? BackendResult.Failure)?.error,
                value = value,
            ).toString(),
        )
    }

    private suspend fun cancelTask(call: MethodCall, result: MethodChannel.Result) {
        val taskId = BackendJson.taskIdFromJson(JSONObject(call.arguments as? Map<*, *>))
        result.success(backend.cancelTask(taskId).name)
    }

    private suspend fun cancelBatch(call: MethodCall, result: MethodChannel.Result) {
        val batchId = BackendJson.batchIdFromJson(JSONObject(call.arguments as? Map<*, *>))
        result.success(backend.cancelBatch(batchId).name)
    }

    private suspend fun getResult(call: MethodCall, result: MethodChannel.Result) {
        val taskId = BackendJson.taskIdFromJson(JSONObject(call.arguments as? Map<*, *>))
        val value = backend.getResult(taskId)?.let(BackendJson::resultToJson)
        result.success(value?.toString() ?: "null")
    }

    private suspend fun queryHistory(call: MethodCall, result: MethodChannel.Result) {
        val query = BackendJson.historyQueryFromJson(JSONObject(call.arguments as? Map<*, *>))
        result.success(BackendJson.pageToJson(backend.queryHistory(query)).toString())
    }

    private suspend fun deleteRecords(call: MethodCall, result: MethodChannel.Result) {
        val recordIds = BackendJson.recordIdsFromJson(JSONObject(call.arguments as? Map<*, *>))
        val res = backend.deleteRecords(recordIds)
        result.success(
            BackendJson.resultToJson(
                success = res is BackendResult.Success,
                error = (res as? BackendResult.Failure)?.error,
                value = null,
            ).toString(),
        )
    }

    private suspend fun exportReport(call: MethodCall, result: MethodChannel.Result) {
        val request = BackendJson.reportRequestFromJson(JSONObject(call.arguments as? Map<*, *>))
        val res = backend.exportReport(request)
        val value = (res as? BackendResult.Success)?.value?.let(BackendJson::reportResultToJson)
        result.success(
            BackendJson.resultToJson(
                success = res is BackendResult.Success,
                error = (res as? BackendResult.Failure)?.error,
                value = value,
            ).toString(),
        )
    }

    private suspend fun release(result: MethodChannel.Result) {
        val res = backend.release()
        BackendHolder.reset()
        result.success(
            BackendJson.resultToJson(
                success = res is BackendResult.Success,
                error = (res as? BackendResult.Failure)?.error,
                value = null,
            ).toString(),
        )
    }

    // ---------- 事件观察（EventChannel 动态注册） ----------

    private fun registerEventObserver(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
        val kind = args["kind"] as? String ?: run {
            result.error("INVALID_ARGS", "kind is required", null)
            return
        }
        val id = args["id"] as? String ?: run {
            result.error("INVALID_ARGS", "id is required", null)
            return
        }
        if (kind != "task" && kind != "batch") {
            result.error("INVALID_ARGS", "kind must be task or batch", null)
            return
        }
        val channelName = "$EVENT_CHANNEL_PREFIX/$kind/$id"
        if (!eventChannels.containsKey(channelName)) {
            val channel = EventChannel(messenger, channelName)
            eventChannels[channelName] = channel
            channel.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    val job = scope.launch {
                        try {
                            collectEvents(kind, id, events)
                        } catch (_: CancellationException) {
                            // 终端事件后主动结束
                        } catch (t: Throwable) {
                            events.error("EVENT_STREAM_FAILED", t.message, null)
                        }
                    }
                    eventJobs[channelName] = job
                }

                override fun onCancel(arguments: Any?) {
                    eventJobs.remove(channelName)?.cancel()
                    eventChannels.remove(channelName)
                }
            })
        }
        result.success(channelName)
    }

    private suspend fun collectEvents(kind: String, id: String, events: EventChannel.EventSink) {
        when (kind) {
            "task" -> backend.observeTask(TaskId(id)).collect { event ->
                events.success(BackendJson.taskEventToJson(event).toString())
                if (event.isTerminal) {
                    events.endOfStream()
                    throw CancellationException("task terminal")
                }
            }

            "batch" -> backend.observeBatch(BatchId(id)).collect { event ->
                events.success(BackendJson.batchEventToJson(event).toString())
                if (event.state == BatchState.COMPLETED ||
                    event.state == BatchState.CANCELLED ||
                    event.state == BatchState.FAILED
                ) {
                    events.endOfStream()
                    throw CancellationException("batch terminal")
                }
            }
        }
    }

    fun dispose() {
        eventJobs.values.forEach { it.cancel() }
        eventJobs.clear()
        eventChannels.clear()
        scope.cancel()
    }
}
