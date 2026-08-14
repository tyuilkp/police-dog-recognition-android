package com.policedog.recognition.backend.storage

import com.policedog.recognition.backend.api.HistoryQuery
import com.policedog.recognition.backend.api.Page
import com.policedog.recognition.backend.api.RecognitionRecord
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

public class InMemoryRecognitionStore : RecognitionStore {
    private val mutex: Mutex = Mutex()
    private val records: LinkedHashMap<String, RecognitionRecord> = LinkedHashMap()

    override suspend fun save(record: RecognitionRecord): Unit = mutex.withLock {
        records[record.result.recordId] = record
    }

    override suspend fun findByTaskId(taskId: String): RecognitionRecord? = mutex.withLock {
        records.values.firstOrNull { it.result.taskId.value == taskId }
    }

    override suspend fun findByRecordIds(recordIds: List<String>): List<RecognitionRecord> = mutex.withLock {
        recordIds.mapNotNull(records::get)
    }

    override suspend fun query(query: HistoryQuery): Page<RecognitionRecord> = mutex.withLock {
        val safeOffset = query.offset.coerceAtLeast(0)
        val safeLimit = query.limit.coerceIn(1, 200)
        val sorted = records.values.sortedByDescending { it.result.createdAtEpochMillis }
        Page(
            items = sorted.drop(safeOffset).take(safeLimit),
            offset = safeOffset,
            limit = safeLimit,
            total = sorted.size,
        )
    }

    override suspend fun delete(recordIds: List<String>): Unit = mutex.withLock {
        recordIds.forEach(records::remove)
    }
}

