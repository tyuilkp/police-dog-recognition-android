package com.example.police_dog_recognition_frontend.bridge

import android.content.Context
import com.policedog.recognition.backend.api.RecognitionBackend
import com.policedog.recognition.nativeengine.NativeBackendFactory

/**
 * 进程级持有唯一的 RecognitionBackend 实例。
 *
 * 依据 pdr 仓库 docs/BACKEND_HANDOFF.md 约定：后端实例应由 Application 级
 * 组件或依赖注入容器持有，页面销毁不等于后端释放。
 */
object BackendHolder {
    @Volatile
    private var instance: RecognitionBackend? = null

    fun get(context: Context): RecognitionBackend =
        instance ?: synchronized(this) {
            instance ?: NativeBackendFactory.create(context.applicationContext).also { instance = it }
        }

    /** 仅供桥接层 release 流程使用：先释放旧实例，再清空引用以便重建。 */
    fun reset() {
        synchronized(this) { instance = null }
    }
}
