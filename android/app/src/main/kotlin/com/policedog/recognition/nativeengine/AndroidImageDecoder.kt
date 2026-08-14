package com.policedog.recognition.nativeengine

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import com.policedog.recognition.backend.api.BackendError
import com.policedog.recognition.backend.api.ErrorCode
import com.policedog.recognition.backend.engine.BackendOperationException

internal object AndroidImageDecoder {
    private const val MAX_EDGE = 4096
    private const val MAX_PIXELS = 16_000_000L

    fun decode(path: String): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            throw decodeError(ErrorCode.UNSUPPORTED_IMAGE_FORMAT, "Android could not decode the image")
        }

        var sampleSize = 1
        while (bounds.outWidth / sampleSize > MAX_EDGE ||
            bounds.outHeight / sampleSize > MAX_EDGE ||
            bounds.outWidth.toLong() * bounds.outHeight / sampleSize / sampleSize > MAX_PIXELS
        ) {
            sampleSize *= 2
        }

        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val decoded = BitmapFactory.decodeFile(path, options)
            ?: throw decodeError(ErrorCode.UNSUPPORTED_IMAGE_FORMAT, "Android could not decode the image pixels")
        val oriented = applyExifOrientation(decoded, path)
        if (oriented !== decoded) decoded.recycle()
        if (oriented.config == Bitmap.Config.ARGB_8888) return oriented

        val rgba = oriented.copy(Bitmap.Config.ARGB_8888, false)
            ?: throw decodeError(ErrorCode.INPUT_OPEN_FAILED, "Could not create an RGBA image buffer")
        oriented.recycle()
        return rgba
    }

    private fun applyExifOrientation(bitmap: Bitmap, path: String): Bitmap {
        val orientation = runCatching {
            ExifInterface(path).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
        }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.setScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.setRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.setRotate(-90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(-90f)
            else -> return bitmap
        }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }

    private fun decodeError(code: ErrorCode, message: String): BackendOperationException =
        BackendOperationException(BackendError(code = code, message = message))
}
