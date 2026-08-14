#pragma once

#include "dog_detector.hpp"
#include "postprocess.hpp"

#include <android/asset_manager.h>
#include <net.h>

#include <string>
#include <vector>

namespace pdr {

struct PoseKeypoint {
    int index;
    float x;
    float y;
    float confidence;
};

class PoseEstimator final {
public:
    bool Load(AAssetManager* assets, const std::string& model_root, std::string& error);
    bool Estimate(
        const ImageView& image,
        const Box& dog_box,
        std::vector<PoseKeypoint>& keypoints,
        std::string& error) const;
    void Clear();

private:
    ncnn::Net network_;
    bool loaded_ = false;
};

}  // namespace pdr
