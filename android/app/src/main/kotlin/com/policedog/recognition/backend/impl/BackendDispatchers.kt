package com.policedog.recognition.backend.impl

import java.util.concurrent.Executors
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExecutorCoroutineDispatcher
import kotlinx.coroutines.asCoroutineDispatcher

public class BackendDispatchers private constructor(
    public val coordinator: CoroutineDispatcher,
    public val inference: ExecutorCoroutineDispatcher,
    public val io: ExecutorCoroutineDispatcher,
) : AutoCloseable {
    override fun close(): Unit {
        inference.close()
        io.close()
    }

    public companion object {
        public fun createDefault(): BackendDispatchers = BackendDispatchers(
            coordinator = Dispatchers.Default,
            inference = Executors.newSingleThreadExecutor { runnable ->
                Thread(runnable, "recognition-inference").apply { isDaemon = true }
            }.asCoroutineDispatcher(),
            io = Executors.newFixedThreadPool(2) { runnable ->
                Thread(runnable, "recognition-io").apply { isDaemon = true }
            }.asCoroutineDispatcher(),
        )
    }
}

