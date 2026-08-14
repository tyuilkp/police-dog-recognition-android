package com.policedog.recognition.backend.report

import com.policedog.recognition.backend.api.RecognitionRecord
import com.policedog.recognition.backend.api.ReportFormat
import com.policedog.recognition.backend.api.ReportResult

public interface ReportExporter {
    public suspend fun export(records: List<RecognitionRecord>, format: ReportFormat): ReportResult
}

