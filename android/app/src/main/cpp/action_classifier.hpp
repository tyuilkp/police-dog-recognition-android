#pragma once

#include "postprocess.hpp"

#include <array>
#include <vector>

namespace pdr {

enum class ActionLabel : std::size_t {
    Standing = 0,
    Sitting = 1,
    Lying = 2,
    Unknown = 3,
};

struct ActionClassification {
    ActionLabel label = ActionLabel::Unknown;
    std::array<float, 4> scores = {0.0F, 0.0F, 0.0F, 1.0F};
    float keypoint_reliability = 0.0F;
};

const char* ActionLabelName(ActionLabel label);

ActionClassification ClassifyDogAction(
    const std::vector<PoseKeypoint>& keypoints,
    const Box& dog_box);

}  // namespace pdr
