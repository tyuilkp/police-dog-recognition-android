package com.policedog.recognition.nativeengine

import android.content.res.AssetManager
import android.graphics.Bitmap

/** Thin JNI boundary. Domain objects remain on the Kotlin side of the boundary. */
internal object NativeInferenceBridge {
    private val loadFailure: Throwable? = runCatching {
        System.loadLibrary("police_dog_inference")
    }.exceptionOrNull()

    fun create(): Long {
        loadFailure?.let { throw it }
        return nativeCreate()
    }

    fun initialize(handle: Long, assets: AssetManager, modelRoot: String): String {
        loadFailure?.let { throw it }
        return nativeInitialize(handle, assets, modelRoot)
    }

    fun infer(handle: Long, bitmap: Bitmap): String {
        loadFailure?.let { throw it }
        return nativeInfer(handle, bitmap)
    }

    fun release(handle: Long) {
        if (loadFailure == null && handle != 0L) nativeRelease(handle)
    }

    private external fun nativeCreate(): Long

    private external fun nativeInitialize(
        handle: Long,
        assets: AssetManager,
        modelRoot: String,
    ): String

    private external fun nativeInfer(handle: Long, bitmap: Bitmap): String

    private external fun nativeRelease(handle: Long)
}
