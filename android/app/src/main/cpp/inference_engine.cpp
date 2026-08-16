#include "inference_engine.hpp"

#include "action_classifier.hpp"

#include <android/asset_manager.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <iomanip>
#include <sstream>
#include <string>
#include <vector>

namespace pdr {
namespace {

using Clock = std::chrono::steady_clock;

constexpr std::array<const char*, 39> kKeypointNames = {
    "nose", "upper_jaw", "lower_jaw", "mouth_end_right", "mouth_end_left",
    "right_eye", "right_earbase", "right_earend", "right_antler_base", "right_antler_end",
    "left_eye", "left_earbase", "left_earend", "left_antler_base", "left_antler_end",
    "neck_base", "neck_end", "throat_base", "throat_end", "back_base", "back_end",
    "back_middle", "tail_base", "tail_end", "front_left_thai", "front_left_knee",
    "front_left_paw", "front_right_thai", "front_right_knee", "front_right_paw",
    "back_left_paw", "back_left_thai", "back_right_thai", "back_left_knee",
    "back_right_knee", "back_right_paw", "belly_bottom", "body_middle_right",
    "body_middle_left",
};

std::string ErrorJson(const char* code, const std::string& message) {
    std::ostringstream output;
    output << "{\"ok\":false,\"errorCode\":\"" << code
           << "\",\"message\":\"" << message << "\"}";
    return output.str();
}

long long ElapsedMillis(const Clock::time_point start) {
    return std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - start).count();
}

bool AssetExists(AAssetManager* assets, const std::string& path) {
    AAsset* asset = AAssetManager_open(assets, path.c_str(), AASSET_MODE_UNKNOWN);
    if (asset == nullptr) return false;
    AAsset_close(asset);
    return true;
}

}  // namespace

std::string InferenceEngine::Initialize(
    AAssetManager* asset_manager,
    const std::string& model_root) {
    Release();
    if (asset_manager == nullptr) {
        return ErrorJson("MODEL_LOAD_FAILED", "Android asset manager is unavailable");
    }
    const std::vector<std::string> required_assets = {
        model_root + "/ssdlite.ncnn.param",
        model_root + "/ssdlite.ncnn.bin",
        model_root + "/rtmpose_s.ncnn.param",
        model_root + "/rtmpose_s.ncnn.bin",
    };
    for (const auto& asset : required_assets) {
        if (!AssetExists(asset_manager, asset)) {
            return ErrorJson("MODEL_FILE_MISSING", "Required ncnn model asset is missing: " + asset);
        }
    }

    std::string error;
    if (!detector_.Load(asset_manager, model_root, error)) {
        Release();
        return ErrorJson("MODEL_LOAD_FAILED", error);
    }
    if (!pose_estimator_.Load(asset_manager, model_root, error)) {
        Release();
        return ErrorJson("MODEL_LOAD_FAILED", error);
    }
    initialized_ = true;
    return "{\"ok\":true,\"mode\":\"ncnn\",\"modelsLoaded\":true}";
}

std::string InferenceEngine::Infer(const ImageView& image) const {
    if (!initialized_) {
        return ErrorJson("BACKEND_NOT_INITIALIZED", "Native ncnn engine is not initialized");
    }
    if (image.rgba == nullptr || image.width <= 0 || image.height <= 0) {
        return ErrorJson("INPUT_OPEN_FAILED", "Decoded input image is invalid");
    }

    const auto total_started = Clock::now();
    const auto detection_started = Clock::now();
    std::vector<Box> detections;
    std::string error;
    if (!detector_.Detect(image, detections, error)) {
        return ErrorJson("INFERENCE_FAILED", error);
    }
    const auto detection_millis = ElapsedMillis(detection_started);
    if (detections.empty()) {
        return ErrorJson("NO_DOG_DETECTED", "No dog passed the SSDLite confidence threshold");
    }
    if (detections.size() > 1) {
        return ErrorJson("MULTIPLE_DOGS_DETECTED", "Multiple dogs were detected; use an image containing one dog");
    }

    const auto pose_started = Clock::now();
    std::vector<PoseKeypoint> keypoints;
    if (!pose_estimator_.Estimate(image, detections.front(), keypoints, error)) {
        return ErrorJson("INFERENCE_FAILED", error);
    }
    const auto pose_millis = ElapsedMillis(pose_started);

    const int confident_keypoints = static_cast<int>(std::count_if(
        keypoints.begin(), keypoints.end(), [](const PoseKeypoint& point) {
            return point.confidence >= 0.20F;
        }));
    float mean_confidence = 0.0F;
    for (const auto& point : keypoints) mean_confidence += point.confidence;
    if (!keypoints.empty()) mean_confidence /= static_cast<float>(keypoints.size());
    const bool pose_accepted = confident_keypoints >= 20 && mean_confidence >= 0.20F;

    const auto classification_started = Clock::now();
    const ActionClassification action = ClassifyDogAction(keypoints, detections.front());
    const auto classification_millis = ElapsedMillis(classification_started);
    const bool action_accepted = action.label != ActionLabel::Unknown;
    const char* quality = !pose_accepted
        ? "LOW_CONFIDENCE"
        : (action_accepted ? "ACCEPTED" : "UNKNOWN_POSE");

    const Box& dog = detections.front();
    std::ostringstream output;
    output << std::fixed << std::setprecision(7);
    output << "{"
           << "\"ok\":true,"
           << "\"engineMode\":\"ncnn\","
           << "\"action\":\"" << ActionLabelName(action.label) << "\","
           << "\"actionScores\":{"
           << "\"STANDING\":" << action.scores[0] << ','
           << "\"SITTING\":" << action.scores[1] << ','
           << "\"LYING\":" << action.scores[2] << ','
           << "\"UNKNOWN\":" << action.scores[3] << "},"
           << "\"dogBox\":{"
           << "\"left\":" << dog.left / image.width << ','
           << "\"top\":" << dog.top / image.height << ','
           << "\"right\":" << dog.right / image.width << ','
           << "\"bottom\":" << dog.bottom / image.height << ','
           << "\"confidence\":" << dog.confidence << "},"
           << "\"keypoints\":[";
    for (std::size_t index = 0; index < keypoints.size(); ++index) {
        if (index > 0) output << ',';
        const auto& point = keypoints[index];
        output << "{\"index\":" << point.index
               << ",\"name\":\"" << kKeypointNames[static_cast<std::size_t>(point.index)] << "\""
               << ",\"x\":" << point.x / image.width
               << ",\"y\":" << point.y / image.height
               << ",\"confidence\":" << point.confidence << '}';
    }
    output << "],"
           << "\"quality\":\"" << quality << "\","
           << "\"warnings\":[";
    bool has_warning = false;
    if (!pose_accepted) {
        output << "\"LOW_KEYPOINT_CONFIDENCE\"";
        has_warning = true;
    }
    if (!action_accepted) {
        if (has_warning) output << ',';
        output << "\"LOW_ACTION_CONFIDENCE\"";
    }
    output << "],"
           << "\"timing\":{"
           << "\"totalMillis\":" << ElapsedMillis(total_started) << ','
           << "\"detectionMillis\":" << detection_millis << ','
           << "\"poseMillis\":" << pose_millis << ','
           << "\"classificationMillis\":" << classification_millis << "},"
           << "\"modelInfo\":{"
           << "\"detectorName\":\"superanimal_quadruped_ssdlite_ncnn\","
           << "\"poseModelName\":\"superanimal_quadruped_rtmpose_s_ncnn\","
           << "\"actionModelName\":\"geometric-keypoint-rules-v1\","
           << "\"version\":\"ncnn-20260526-pipeline-0.3.0\"}"
           << '}';
    return output.str();
}

void InferenceEngine::Release() {
    pose_estimator_.Clear();
    detector_.Clear();
    initialized_ = false;
}

}  // namespace pdr
