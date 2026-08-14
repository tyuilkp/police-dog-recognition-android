package com.policedog.recognition.backend.report

import com.policedog.recognition.backend.api.RecognitionRecord
import com.policedog.recognition.backend.api.ReportFormat
import com.policedog.recognition.backend.api.ReportResult
import java.util.UUID

public class InMemoryReportExporter : ReportExporter {
    override suspend fun export(records: List<RecognitionRecord>, format: ReportFormat): ReportResult {
        val extension = format.name.lowercase()
        val mimeType = when (format) {
            ReportFormat.JSON -> "application/json"
            ReportFormat.CSV -> "text/csv"
            ReportFormat.PDF -> "application/pdf"
        }
        return ReportResult(
            location = "memory://reports/${UUID.randomUUID()}.$extension",
            mimeType = mimeType,
            recordCount = records.size,
        )
    }
}

