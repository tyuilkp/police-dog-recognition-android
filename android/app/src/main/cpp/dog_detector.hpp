#pragma once

#include "postprocess.hpp"

#include <android/asset_manager.h>
#include <net.h>

#include <string>
#include <vector>

namespace pdr {

class DogDetector final {
public:
    bool Load(AAssetManager* assets, const std::string& model_root, std::string& error);
    bool Detect(const ImageView& image, std::vector<Box>& detections, std::string& error) const;
    void Clear();

private:
    ncnn::Net network_;
    std::vector<Anchor> anchors_;
    bool loaded_ = false;
};

}  // namespace pdr
