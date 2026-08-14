package com.policedog.recognition.backend.mock

import com.policedog.recognition.backend.api.RecognitionBackend
import com.policedog.recognition.backend.impl.QueuedRecognitionBackend
import com.policedog.recognition.backend.report.InMemoryReportExporter
import com.policedog.recognition.backend.storage.InMemoryRecognitionStore

public object MockBackendFactory {
    public fun create(
        engineConfig: MockEngineConfig = MockEngineConfig(),
        queueCapacity: Int = 16,
    ): RecognitionBackend = QueuedRecognitionBackend(
        engine = MockRecognitionEngine(engineConfig),
        store = InMemoryRecognitionStore(),
        reportExporter = InMemoryReportExporter(),
        queueCapacity = queueCapacity,
    )
}

