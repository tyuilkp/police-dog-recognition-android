package com.example.police_dog_recognition_frontend.bridge

import com.policedog.recognition.backend.api.ActionLabel
import com.policedog.recognition.backend.api.BackendConfig
import com.policedog.recognition.backend.api.BackendError
import com.policedog.recognition.backend.api.BackendResult
import com.policedog.recognition.backend.api.BackendState
import com.policedog.recognition.backend.api.BatchEvent
import com.policedog.recognition.backend.api.BatchId
import com.policedog.recognition.backend.api.BatchRecognitionRequest
import com.policedog.recognition.backend.api.BoundingBox
import com.policedog.recognition.backend.api.HistoryQuery
import com.policedog.recognition.backend.api.InferenceTiming
import com.policedog.recognition.backend.api.Keypoint
import com.policedog.recognition.backend.api.ModelInfo
import com.policedog.recognition.backend.api.Page
import com.policedog.recognition.backend.api.QualityStatus
import com.policedog.recognition.backend.api.RecognitionRecord
import com.policedog.recognition.backend.api.RecognitionRequest
import com.policedog.recognition.backend.api.RecognitionResult
import com.policedog.recognition.backend.api.RecognitionWarning
import com.policedog.recognition.backend.api.ReportFormat
import com.policedog.recognition.backend.api.ReportRequest
import com.policedog.recognition.backend.api.ReportResult
import com.policedog.recognition.backend.api.TaskEvent
import com.policedog.recognition.backend.api.TaskId
import com.policedog.recognition.backend.api.TaskPriority
import org.json.JSONArray
import org.json.JSONObject

/**
 * backend-core 领域模型 <-> JSON 的双向转换。
 *
 * 桥接层只允许依赖 com.policedog.recognition.backend.api 与 mock 包，
 * 符合 pdr 仓库 docs/BACKEND_HANDOFF.md 的前端依赖边界约定。
 */
object BackendJson {

    // ---------- 出站：模型 -> JSON ----------

    fun errorToJson(error: BackendError): JSONObject = JSONObject()
        .put("code", error.code.name)
        .put("message", error.message)
        .put("retryable", error.retryable)
        .put("diagnostic", error.diagnostic ?: JSONObject.NULL)

    fun resultToJson(success: Boolean, error: BackendError?, value: JSONObject?): JSONObject {
        val json = JSONObject().put("success", success)
        json.put("value", value ?: JSONObject.NULL)
        json.put("error", error?.let(::errorToJson) ?: JSONObject.NULL)
        return json
    }

    fun stateToJson(state: BackendState): JSONObject = JSONObject()
        .put("lifecycle", state.lifecycle.name)
        .put("error", state.error?.let(::errorToJson) ?: JSONObject.NULL)

    fun boxToJson(box: BoundingBox): JSONObject = JSONObject()
        .put("left", box.left.toDouble())
        .put("top", box.top.toDouble())
        .put("right", box.right.toDouble())
        .put("bottom", box.bottom.toDouble())
        .put("confidence", box.confidence.toDouble())

    fun keypointToJson(kp: Keypoint): JSONObject = JSONObject()
        .put("index", kp.index)
        .put("name", kp.name)
        .put("x", kp.x.toDouble())
        .put("y", kp.y.toDouble())
        .put("confidence", kp.confidence.toDouble())

    fun timingToJson(t: InferenceTiming): JSONObject = JSONObject()
        .put("totalMillis", t.totalMillis)
        .put("detectionMillis", t.detectionMillis)
        .put("poseMillis", t.poseMillis)
        .put("classificationMillis", t.classificationMillis)

    fun modelInfoToJson(m: ModelInfo): JSONObject = JSONObject()
        .put("detectorName", m.detectorName)
        .put("poseModelName", m.poseModelName)
        .put("actionModelName", m.actionModelName)
        .put("version", m.version)

    fun resultToJson(r: RecognitionResult): JSONObject {
        val scores = JSONObject()
        r.actionScores.forEach { (label, score) -> scores.put(label.name, score.toDouble()) }
        val warnings = JSONArray()
        r.warnings.forEach { warnings.put(it.name) }
        val keypoints = JSONArray()
        r.keypoints.forEach { keypoints.put(keypointToJson(it)) }
        return JSONObject()
            .put("recordId", r.recordId)
            .put("taskId", r.taskId.value)
            .put("source", r.source)
            .put("action", r.action.name)
            .put("actionScores", scores)
            .put("dogBox", r.dogBox?.let(::boxToJson) ?: JSONObject.NULL)
            .put("keypoints", keypoints)
            .put("quality", r.quality.name)
            .put("warnings", warnings)
            .put("originalLocation", r.originalLocation ?: JSONObject.NULL)
            .put("overlayLocation", r.overlayLocation ?: JSONObject.NULL)
            .put("timing", timingToJson(r.timing))
            .put("modelInfo", modelInfoToJson(r.modelInfo))
            .put("createdAtEpochMillis", r.createdAtEpochMillis)
    }

    fun recordToJson(record: RecognitionRecord): JSONObject = JSONObject()
        .put("result", resultToJson(record.result))

    fun pageToJson(page: Page<RecognitionRecord>): JSONObject {
        val items = JSONArray()
        page.items.forEach { items.put(recordToJson(it)) }
        return JSONObject()
            .put("items", items)
            .put("offset", page.offset)
            .put("limit", page.limit)
            .put("total", page.total)
    }

    fun taskEventToJson(e: TaskEvent): JSONObject = JSONObject()
        .put("taskId", e.taskId.value)
        .put("state", e.state.name)
        .put("stage", e.stage.name)
        .put("progressPercent", e.progressPercent)
        .put("result", e.result?.let(::resultToJson) ?: JSONObject.NULL)
        .put("error", e.error?.let(::errorToJson) ?: JSONObject.NULL)
        .put("updatedAtEpochMillis", e.updatedAtEpochMillis)
        .put("isTerminal", e.isTerminal)

    fun batchEventToJson(e: BatchEvent): JSONObject {
        val taskIds = JSONArray()
        e.taskIds.forEach { taskIds.put(it.value) }
        return JSONObject()
            .put("batchId", e.batchId.value)
            .put("state", e.state.name)
            .put("total", e.total)
            .put("completed", e.completed)
            .put("failed", e.failed)
            .put("cancelled", e.cancelled)
            .put("taskIds", taskIds)
            .put("error", e.error?.let(::errorToJson) ?: JSONObject.NULL)
            .put("finished", e.finished)
            .put("progressPercent", e.progressPercent)
            .put("updatedAtEpochMillis", e.updatedAtEpochMillis)
    }

    fun reportResultToJson(r: ReportResult): JSONObject = JSONObject()
        .put("location", r.location)
        .put("mimeType", r.mimeType)
        .put("recordCount", r.recordCount)

    // ---------- 入站：JSON -> 模型 ----------

    fun configFromJson(json: JSONObject?): BackendConfig = BackendConfig(
        maxBatchSize = json?.optInt("maxBatchSize") ?: BackendConfig().maxBatchSize,
        persistResults = json?.optBoolean("persistResults") ?: BackendConfig().persistResults,
    )

    fun requestFromJson(json: JSONObject): RecognitionRequest {
        val priority = runCatching {
            TaskPriority.valueOf(json.optString("priority", TaskPriority.INTERACTIVE.name))
        }.getOrDefault(TaskPriority.INTERACTIVE)
        return RecognitionRequest(
            source = json.getString("source"),
            clientRequestId = json.optString("clientRequestId").takeIf { it.isNotBlank() },
            saveOriginal = json.optBoolean("saveOriginal"),
            saveOverlay = json.optBoolean("saveOverlay", true),
            priority = priority,
        )
    }

    fun batchRequestFromJson(json: JSONObject): BatchRecognitionRequest {
        val requests = JSONArray()
        requests.put(json) // 兼容单个对象传入
        return batchRequestFromJson(requests)
    }

    fun batchRequestFromJson(array: JSONArray): BatchRecognitionRequest =
        BatchRecognitionRequest(
            requests = buildList {
                for (i in 0 until array.length()) {
                    add(requestFromJson(array.getJSONObject(i)))
                }
            },
        )

    fun historyQueryFromJson(json: JSONObject): HistoryQuery = HistoryQuery(
        offset = json.optInt("offset", 0),
        limit = json.optInt("limit", 50),
    )

    fun reportRequestFromJson(json: JSONObject): ReportRequest = ReportRequest(
        recordIds = buildList {
            val ids = json.getJSONArray("recordIds")
            for (i in 0 until ids.length()) add(ids.getString(i))
        },
        format = runCatching {
            ReportFormat.valueOf(json.optString("format", ReportFormat.JSON.name))
        }.getOrDefault(ReportFormat.JSON),
    )

    fun taskIdFromJson(json: JSONObject): TaskId = TaskId(json.getString("taskId"))

    fun batchIdFromJson(json: JSONObject): BatchId = BatchId(json.getString("batchId"))

    fun recordIdsFromJson(json: JSONObject): List<String> = buildList {
        val ids = json.getJSONArray("recordIds")
        for (i in 0 until ids.length()) add(ids.getString(i))
    }
}
