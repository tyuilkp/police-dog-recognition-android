#pragma once

#include "dog_detector.hpp"
#include "pose_estimator.hpp"

#include <android/asset_manager.h>

#include <string>

namespace pdr {

class InferenceEngine final {
public:
    InferenceEngine() = default;

    std::string Initialize(AAssetManager* asset_manager, const std::string& model_root);
    std::string Infer(const ImageView& image) const;
    void Release();

private:
    DogDetector detector_;
    PoseEstimator pose_estimator_;
    bool initialized_ = false;
};

}  // namespace pdr
