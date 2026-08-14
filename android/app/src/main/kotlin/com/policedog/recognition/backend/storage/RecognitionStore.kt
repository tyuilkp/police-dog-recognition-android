package com.policedog.recognition.backend.storage

import com.policedog.recognition.backend.api.HistoryQuery
import com.policedog.recognition.backend.api.Page
import com.policedog.recognition.backend.api.RecognitionRecord

public interface RecognitionStore {
    public suspend fun save(record: RecognitionRecord)

    public suspend fun findByTaskId(taskId: String): RecognitionRecord?

    public suspend fun findByRecordIds(recordIds: List<String>): List<RecognitionRecord>

    public suspend fun query(query: HistoryQuery): Page<RecognitionRecord>

    public suspend fun delete(recordIds: List<String>)
}

