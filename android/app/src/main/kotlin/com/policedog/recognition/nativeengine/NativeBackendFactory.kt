package com.policedog.recognition.nativeengine

import android.content.Context
import com.policedog.recognition.backend.api.RecognitionBackend
import com.policedog.recognition.backend.impl.QueuedRecognitionBackend
import com.policedog.recognition.backend.report.InMemoryReportExporter
import com.policedog.recognition.backend.storage.InMemoryRecognitionStore

/** Creates the production-shaped backend with the JNI engine and current in-memory adapters. */
object NativeBackendFactory {
    fun create(context: Context, queueCapacity: Int = 16): RecognitionBackend =
        QueuedRecognitionBackend(
            engine = NativeRecognitionEngine(context),
            store = InMemoryRecognitionStore(),
            reportExporter = InMemoryReportExporter(),
            queueCapacity = queueCapacity,
        )
}
