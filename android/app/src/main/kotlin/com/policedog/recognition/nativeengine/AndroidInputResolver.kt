package com.policedog.recognition.nativeengine

import android.content.Context
import android.net.Uri
import com.policedog.recognition.backend.api.BackendError
import com.policedog.recognition.backend.api.ErrorCode
import com.policedog.recognition.backend.api.TaskId
import com.policedog.recognition.backend.engine.BackendOperationException
import java.io.File
import java.io.IOException
import java.util.Locale

internal data class ResolvedInput(
    val path: String,
    val deleteAfterUse: Boolean,
)

/** Converts Android content URIs into bounded, native-readable files. */
internal object AndroidInputResolver {
    private const val MAX_INPUT_BYTES: Long = 64L * 1024L * 1024L

    fun resolve(context: Context, source: String, taskId: TaskId): ResolvedInput {
        if (source.isBlank()) {
            throw inputError(ErrorCode.INVALID_REQUEST, "Input source is blank")
        }

        val uri = Uri.parse(source)
        return when (uri.scheme?.lowercase(Locale.ROOT)) {
            "content" -> copyContentUri(context, uri, taskId)
            "file" -> validateFile(uri.path?.let(::File))
            null -> validateFile(File(source))
            else -> throw inputError(
                ErrorCode.INVALID_REQUEST,
                "Only local files and Android content URIs are supported",
            )
        }
    }

    private fun validateFile(file: File?): ResolvedInput {
        if (file == null || !file.isFile || !file.canRead()) {
            throw inputError(ErrorCode.INPUT_OPEN_FAILED, "Input image is not readable")
        }
        if (file.length() <= 0L) {
            throw inputError(ErrorCode.INPUT_OPEN_FAILED, "Input image is empty")
        }
        if (file.length() > MAX_INPUT_BYTES) {
            throw inputError(ErrorCode.IMAGE_TOO_LARGE, "Input image exceeds the 64 MiB limit")
        }
        return ResolvedInput(file.absolutePath, deleteAfterUse = false)
    }

    private fun copyContentUri(context: Context, uri: Uri, taskId: TaskId): ResolvedInput {
        val suffix = suffixFor(context.contentResolver.getType(uri))
        val inputDirectory = File(context.cacheDir, "native-input").apply { mkdirs() }
        val target = File.createTempFile("pdr-${taskId.value.take(8)}-", suffix, inputDirectory)

        try {
            val input = context.contentResolver.openInputStream(uri)
                ?: throw inputError(ErrorCode.INPUT_OPEN_FAILED, "Content provider returned no image data")
            input.use { stream ->
                target.outputStream().buffered().use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    var total = 0L
                    while (true) {
                        val read = stream.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > MAX_INPUT_BYTES) {
                            throw inputError(
                                ErrorCode.IMAGE_TOO_LARGE,
                                "Input image exceeds the 64 MiB limit",
                            )
                        }
                        output.write(buffer, 0, read)
                    }
                    if (total == 0L) {
                        throw inputError(ErrorCode.INPUT_OPEN_FAILED, "Input image is empty")
                    }
                }
            }
            return ResolvedInput(target.absolutePath, deleteAfterUse = true)
        } catch (error: BackendOperationException) {
            target.delete()
            throw error
        } catch (error: SecurityException) {
            target.delete()
            throw inputError(ErrorCode.INPUT_OPEN_FAILED, "Permission to read the image was denied", error)
        } catch (error: IOException) {
            target.delete()
            throw inputError(ErrorCode.INPUT_OPEN_FAILED, "Failed to copy the input image", error)
        }
    }

    private fun suffixFor(mimeType: String?): String = when (mimeType?.lowercase(Locale.ROOT)) {
        "image/png" -> ".png"
        "image/webp" -> ".webp"
        "image/heic", "image/heif" -> ".heic"
        else -> ".jpg"
    }

    private fun inputError(
        code: ErrorCode,
        message: String,
        cause: Throwable? = null,
    ): BackendOperationException = BackendOperationException(
        BackendError(
            code = code,
            message = message,
            retryable = code == ErrorCode.INPUT_OPEN_FAILED,
            diagnostic = cause?.javaClass?.simpleName,
        ),
    )
}
