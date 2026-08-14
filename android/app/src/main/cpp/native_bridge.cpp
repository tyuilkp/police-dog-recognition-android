#include "inference_engine.hpp"

#include <android/asset_manager_jni.h>
#include <android/bitmap.h>
#include <jni.h>

#include <cstdint>
#include <exception>
#include <new>
#include <string>

namespace {

pdr::InferenceEngine* FromHandle(const jlong handle) {
    return reinterpret_cast<pdr::InferenceEngine*>(handle);
}

std::string FromJString(JNIEnv* env, jstring value) {
    if (value == nullptr) return {};
    const char* chars = env->GetStringUTFChars(value, nullptr);
    if (chars == nullptr) return {};
    std::string result(chars);
    env->ReleaseStringUTFChars(value, chars);
    return result;
}

jstring ToJString(JNIEnv* env, const std::string& value) {
    return env->NewStringUTF(value.c_str());
}

}  // namespace

extern "C" JNIEXPORT jlong JNICALL
Java_com_policedog_recognition_nativeengine_NativeInferenceBridge_nativeCreate(
    JNIEnv*, jobject) {
    auto* engine = new (std::nothrow) pdr::InferenceEngine();
    return reinterpret_cast<jlong>(engine);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_policedog_recognition_nativeengine_NativeInferenceBridge_nativeInitialize(
    JNIEnv* env, jobject, jlong handle, jobject asset_manager, jstring model_root) {
    auto* engine = FromHandle(handle);
    if (engine == nullptr) {
        return ToJString(env, "{\"ok\":false,\"errorCode\":\"MODEL_LOAD_FAILED\",\"message\":\"Native engine allocation failed\"}");
    }
    auto* assets = AAssetManager_fromJava(env, asset_manager);
    try {
        return ToJString(env, engine->Initialize(assets, FromJString(env, model_root)));
    } catch (...) {
        engine->Release();
        return ToJString(env, "{\"ok\":false,\"errorCode\":\"MODEL_LOAD_FAILED\",\"message\":\"Native model initialization raised an exception\"}");
    }
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_policedog_recognition_nativeengine_NativeInferenceBridge_nativeInfer(
    JNIEnv* env, jobject, jlong handle, jobject bitmap) {
    auto* engine = FromHandle(handle);
    if (engine == nullptr) {
        return ToJString(env, "{\"ok\":false,\"errorCode\":\"BACKEND_NOT_INITIALIZED\",\"message\":\"Native engine handle is invalid\"}");
    }
    AndroidBitmapInfo info{};
    if (bitmap == nullptr || AndroidBitmap_getInfo(env, bitmap, &info) != ANDROID_BITMAP_RESULT_SUCCESS ||
        info.format != ANDROID_BITMAP_FORMAT_RGBA_8888) {
        return ToJString(env, "{\"ok\":false,\"errorCode\":\"UNSUPPORTED_IMAGE_FORMAT\",\"message\":\"Android bitmap must use RGBA_8888\"}");
    }
    void* pixels = nullptr;
    if (AndroidBitmap_lockPixels(env, bitmap, &pixels) != ANDROID_BITMAP_RESULT_SUCCESS || pixels == nullptr) {
        return ToJString(env, "{\"ok\":false,\"errorCode\":\"INPUT_OPEN_FAILED\",\"message\":\"Could not lock Android bitmap pixels\"}");
    }
    const pdr::ImageView image{
        static_cast<const std::uint8_t*>(pixels),
        static_cast<int>(info.width),
        static_cast<int>(info.height),
        static_cast<int>(info.stride),
    };
    std::string result;
    try {
        result = engine->Infer(image);
    } catch (const std::exception&) {
        result = "{\"ok\":false,\"errorCode\":\"INFERENCE_FAILED\",\"message\":\"Native inference raised an exception\"}";
    } catch (...) {
        result = "{\"ok\":false,\"errorCode\":\"INFERENCE_FAILED\",\"message\":\"Native inference failed unexpectedly\"}";
    }
    AndroidBitmap_unlockPixels(env, bitmap);
    return ToJString(env, result);
}

extern "C" JNIEXPORT void JNICALL
Java_com_policedog_recognition_nativeengine_NativeInferenceBridge_nativeRelease(
    JNIEnv*, jobject, jlong handle) {
    auto* engine = FromHandle(handle);
    if (engine != nullptr) {
        engine->Release();
        delete engine;
    }
}
