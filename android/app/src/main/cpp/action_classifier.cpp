#include "action_classifier.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <initializer_list>
#include <limits>
#include <optional>

namespace pdr {
namespace {

constexpr float kVisibleConfidence = 0.25F;
constexpr std::size_t kKeypointCount = 39;

struct Point {
    float x;
    float y;
};

struct LegFeatures {
    float straightness = 0.0F;
    float vertical_reach = 0.0F;
    int complete_legs = 0;
};

float Clamp01(const float value) {
    return std::clamp(value, 0.0F, 1.0F);
}

float Ramp(const float value, const float low, const float high) {
    if (high <= low) return value >= high ? 1.0F : 0.0F;
    return Clamp01((value - low) / (high - low));
}

float Distance(const Point& first, const Point& second) {
    return std::hypot(first.x - second.x, first.y - second.y);
}

std::array<const PoseKeypoint*, kKeypointCount> IndexKeypoints(
    const std::vector<PoseKeypoint>& keypoints) {
    std::array<const PoseKeypoint*, kKeypointCount> indexed{};
    for (const auto& point : keypoints) {
        if (point.index < 0 || point.index >= static_cast<int>(kKeypointCount) ||
            !std::isfinite(point.x) || !std::isfinite(point.y) ||
            !std::isfinite(point.confidence)) {
            continue;
        }
        const std::size_t index = static_cast<std::size_t>(point.index);
        if (indexed[index] == nullptr || point.confidence > indexed[index]->confidence) {
            indexed[index] = &point;
        }
    }
    return indexed;
}

bool Visible(const PoseKeypoint* point) {
    return point != nullptr && point->confidence >= kVisibleConfidence;
}

std::optional<Point> MeanVisible(
    const std::array<const PoseKeypoint*, kKeypointCount>& points,
    const std::initializer_list<int> indices,
    int* visible_count = nullptr) {
    Point sum{0.0F, 0.0F};
    int count = 0;
    for (const int index : indices) {
        const PoseKeypoint* point = points[static_cast<std::size_t>(index)];
        if (!Visible(point)) continue;
        sum.x += point->x;
        sum.y += point->y;
        ++count;
    }
    if (visible_count != nullptr) *visible_count = count;
    if (count == 0) return std::nullopt;
    return Point{sum.x / count, sum.y / count};
}

LegFeatures ComputeLegFeatures(
    const std::array<const PoseKeypoint*, kKeypointCount>& points,
    const std::array<std::array<int, 3>, 2>& legs,
    const float dog_height) {
    LegFeatures features;
    for (const auto& indices : legs) {
        const PoseKeypoint* thigh = points[static_cast<std::size_t>(indices[0])];
        const PoseKeypoint* knee = points[static_cast<std::size_t>(indices[1])];
        const PoseKeypoint* paw = points[static_cast<std::size_t>(indices[2])];
        if (!Visible(thigh) || !Visible(knee) || !Visible(paw)) continue;
        const Point thigh_point{thigh->x, thigh->y};
        const Point knee_point{knee->x, knee->y};
        const Point paw_point{paw->x, paw->y};
        const float path_length =
            Distance(thigh_point, knee_point) + Distance(knee_point, paw_point);
        if (path_length <= 1.0e-5F) continue;
        features.straightness += Distance(thigh_point, paw_point) / path_length;
        features.vertical_reach += std::abs(paw_point.y - thigh_point.y) / dog_height;
        ++features.complete_legs;
    }
    if (features.complete_legs > 0) {
        features.straightness = Clamp01(features.straightness / features.complete_legs);
        features.vertical_reach = Clamp01(features.vertical_reach / features.complete_legs);
    }
    return features;
}

ActionClassification UnknownClassification(const float reliability = 0.0F) {
    ActionClassification result;
    result.keypoint_reliability = Clamp01(reliability);
    return result;
}

}  // namespace

const char* ActionLabelName(const ActionLabel label) {
    switch (label) {
        case ActionLabel::Standing: return "STANDING";
        case ActionLabel::Sitting: return "SITTING";
        case ActionLabel::Lying: return "LYING";
        case ActionLabel::Unknown: return "UNKNOWN";
    }
    return "UNKNOWN";
}

ActionClassification ClassifyDogAction(
    const std::vector<PoseKeypoint>& keypoints,
    const Box& dog_box) {
    const float dog_width = dog_box.right - dog_box.left;
    const float dog_height = dog_box.bottom - dog_box.top;
    if (dog_width <= 1.0F || dog_height <= 1.0F || keypoints.empty()) {
        return UnknownClassification();
    }

    const auto points = IndexKeypoints(keypoints);
    constexpr std::array<int, 18> essential = {
        15, 19, 20, 21, 22, 36,
        24, 25, 26, 27, 28, 29,
        30, 31, 32, 33, 34, 35,
    };
    int essential_visible = 0;
    for (const int index : essential) {
        if (Visible(points[static_cast<std::size_t>(index)])) ++essential_visible;
    }
    const float reliability = static_cast<float>(essential_visible) / essential.size();

    int body_visible = 0;
    const auto body = MeanVisible(points, {15, 19, 20, 21, 22, 36}, &body_visible);
    const auto front_body = MeanVisible(points, {15, 19});
    const auto rear_body = MeanVisible(points, {20, 22});
    const auto paws = MeanVisible(points, {26, 29, 30, 35});
    const LegFeatures front_legs = ComputeLegFeatures(
        points,
        {{{24, 25, 26}, {27, 28, 29}}},
        dog_height);
    const LegFeatures rear_legs = ComputeLegFeatures(
        points,
        {{{31, 33, 30}, {32, 34, 35}}},
        dog_height);

    if (!body || !front_body || !rear_body || !paws || body_visible < 3 ||
        front_legs.complete_legs == 0 || rear_legs.complete_legs == 0 ||
        reliability < 0.55F) {
        return UnknownClassification(reliability);
    }

    float body_min_y = std::numeric_limits<float>::max();
    float body_max_y = std::numeric_limits<float>::lowest();
    for (const int index : {15, 19, 20, 21, 22, 36}) {
        const PoseKeypoint* point = points[static_cast<std::size_t>(index)];
        if (!Visible(point)) continue;
        body_min_y = std::min(body_min_y, point->y);
        body_max_y = std::max(body_max_y, point->y);
    }

    const float body_to_ground = Clamp01((paws->y - body->y) / dog_height);
    const float body_vertical_span = Clamp01((body_max_y - body_min_y) / dog_height);
    const float rear_drop = Clamp01((rear_body->y - front_body->y) / dog_height);
    const float limb_vertical_reach =
        (front_legs.vertical_reach * front_legs.complete_legs +
         rear_legs.vertical_reach * rear_legs.complete_legs) /
        (front_legs.complete_legs + rear_legs.complete_legs);

    const float standing = Clamp01(
        0.30F * front_legs.straightness +
        0.30F * rear_legs.straightness +
        0.30F * Ramp(body_to_ground, 0.25F, 0.48F) +
        0.10F * (1.0F - Ramp(rear_drop, 0.08F, 0.22F)));
    const float sitting = Clamp01(
        0.25F * front_legs.straightness +
        0.35F * (1.0F - Ramp(rear_legs.straightness, 0.65F, 0.90F)) +
        0.25F * Ramp(rear_drop, 0.05F, 0.20F) +
        0.15F * Ramp(body_to_ground, 0.18F, 0.38F));
    const float lying = Clamp01(
        0.50F * (1.0F - Ramp(body_to_ground, 0.14F, 0.30F)) +
        0.30F * (1.0F - Ramp(limb_vertical_reach, 0.12F, 0.32F)) +
        0.20F * (1.0F - Ramp(body_vertical_span, 0.12F, 0.28F)));

    const std::array<float, 3> posture_scores = {standing, sitting, lying};
    std::array<std::size_t, 3> order = {0, 1, 2};
    std::sort(order.begin(), order.end(), [&](const std::size_t first, const std::size_t second) {
        return posture_scores[first] > posture_scores[second];
    });
    const float best = posture_scores[order[0]];
    const float margin = best - posture_scores[order[1]];
    const float certainty =
        reliability * Ramp(best, 0.50F, 0.78F) * Ramp(margin, 0.04F, 0.18F);
    const bool accepted = best >= 0.58F && margin >= 0.08F && certainty >= 0.45F;

    ActionClassification result;
    result.keypoint_reliability = reliability;
    result.label = accepted
        ? static_cast<ActionLabel>(order[0])
        : ActionLabel::Unknown;

    const float selected_probability = accepted
        ? std::clamp(0.55F + 0.40F * certainty, 0.55F, 0.95F)
        : std::clamp(0.55F + 0.40F * (1.0F - certainty), 0.55F, 0.95F);
    const float remaining = 1.0F - selected_probability;
    if (accepted) {
        result.scores[order[0]] = selected_probability;
        const float other_total =
            posture_scores[order[1]] + posture_scores[order[2]] + 0.10F;
        result.scores[order[1]] = remaining * posture_scores[order[1]] / other_total;
        result.scores[order[2]] = remaining * posture_scores[order[2]] / other_total;
        result.scores[static_cast<std::size_t>(ActionLabel::Unknown)] =
            remaining * 0.10F / other_total;
    } else {
        result.scores[static_cast<std::size_t>(ActionLabel::Unknown)] = selected_probability;
        const float posture_total = standing + sitting + lying;
        if (posture_total > 1.0e-5F) {
            result.scores[0] = remaining * standing / posture_total;
            result.scores[1] = remaining * sitting / posture_total;
            result.scores[2] = remaining * lying / posture_total;
        } else {
            result.scores[static_cast<std::size_t>(ActionLabel::Unknown)] = 1.0F;
        }
    }
    return result;
}

}  // namespace pdr
