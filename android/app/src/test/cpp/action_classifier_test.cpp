#include "action_classifier.hpp"

#include <array>
#include <cassert>
#include <cmath>
#include <string>
#include <vector>

namespace {

std::vector<pdr::PoseKeypoint> EmptyPose() {
    std::vector<pdr::PoseKeypoint> points;
    points.reserve(39);
    for (int index = 0; index < 39; ++index) {
        points.push_back({index, 0.0F, 0.0F, 0.0F});
    }
    return points;
}

void Set(
    std::vector<pdr::PoseKeypoint>& points,
    const int index,
    const float x,
    const float y,
    const float confidence = 0.95F) {
    points[static_cast<std::size_t>(index)] = {index, x, y, confidence};
}

void SetBody(
    std::vector<pdr::PoseKeypoint>& points,
    const std::array<float, 6>& y) {
    Set(points, 15, 15.0F, y[0]);
    Set(points, 19, 35.0F, y[1]);
    Set(points, 21, 55.0F, y[2]);
    Set(points, 20, 75.0F, y[3]);
    Set(points, 22, 85.0F, y[4]);
    Set(points, 36, 55.0F, y[5]);
}

void SetFrontLegs(
    std::vector<pdr::PoseKeypoint>& points,
    const float thigh_y,
    const float knee_y,
    const float paw_y) {
    Set(points, 24, 28.0F, thigh_y);
    Set(points, 25, 28.0F, knee_y);
    Set(points, 26, 28.0F, paw_y);
    Set(points, 27, 38.0F, thigh_y);
    Set(points, 28, 38.0F, knee_y);
    Set(points, 29, 38.0F, paw_y);
}

float ScoreSum(const pdr::ActionClassification& classification) {
    float sum = 0.0F;
    for (const float score : classification.scores) sum += score;
    return sum;
}

void AssertClassification(
    const std::vector<pdr::PoseKeypoint>& points,
    const pdr::ActionLabel expected) {
    const auto result = pdr::ClassifyDogAction(
        points,
        {0.0F, 0.0F, 100.0F, 100.0F, 1.0F});
    assert(result.label == expected);
    assert(std::abs(ScoreSum(result) - 1.0F) < 1.0e-4F);
    assert(result.scores[static_cast<std::size_t>(expected)] >= 0.55F);
}

}  // namespace

int main() {
    auto standing = EmptyPose();
    SetBody(standing, {30.0F, 31.0F, 32.0F, 33.0F, 34.0F, 40.0F});
    SetFrontLegs(standing, 40.0F, 65.0F, 92.0F);
    Set(standing, 31, 70.0F, 42.0F);
    Set(standing, 33, 70.0F, 66.0F);
    Set(standing, 30, 70.0F, 92.0F);
    Set(standing, 32, 80.0F, 42.0F);
    Set(standing, 34, 80.0F, 66.0F);
    Set(standing, 35, 80.0F, 92.0F);
    AssertClassification(standing, pdr::ActionLabel::Standing);

    auto sitting = EmptyPose();
    SetBody(sitting, {25.0F, 35.0F, 42.0F, 52.0F, 60.0F, 48.0F});
    SetFrontLegs(sitting, 40.0F, 65.0F, 92.0F);
    Set(sitting, 31, 70.0F, 58.0F);
    Set(sitting, 33, 53.0F, 72.0F);
    Set(sitting, 30, 72.0F, 79.0F);
    Set(sitting, 32, 80.0F, 58.0F);
    Set(sitting, 34, 97.0F, 72.0F);
    Set(sitting, 35, 78.0F, 79.0F);
    AssertClassification(sitting, pdr::ActionLabel::Sitting);

    auto lying = EmptyPose();
    SetBody(lying, {64.0F, 65.0F, 65.0F, 66.0F, 66.0F, 68.0F});
    Set(lying, 24, 25.0F, 67.0F);
    Set(lying, 25, 40.0F, 70.0F);
    Set(lying, 26, 55.0F, 74.0F);
    Set(lying, 27, 30.0F, 67.0F);
    Set(lying, 28, 45.0F, 70.0F);
    Set(lying, 29, 60.0F, 74.0F);
    Set(lying, 31, 75.0F, 67.0F);
    Set(lying, 33, 60.0F, 70.0F);
    Set(lying, 30, 45.0F, 74.0F);
    Set(lying, 32, 80.0F, 67.0F);
    Set(lying, 34, 65.0F, 70.0F);
    Set(lying, 35, 50.0F, 74.0F);
    AssertClassification(lying, pdr::ActionLabel::Lying);

    auto ambiguous = EmptyPose();
    SetBody(ambiguous, {50.0F, 50.0F, 50.0F, 50.0F, 50.0F, 55.0F});
    SetFrontLegs(ambiguous, 50.0F, 60.0F, 70.0F);
    Set(ambiguous, 31, 70.0F, 50.0F);
    Set(ambiguous, 33, 70.0F, 60.0F);
    Set(ambiguous, 30, 70.0F, 70.0F);
    Set(ambiguous, 32, 80.0F, 50.0F);
    Set(ambiguous, 34, 80.0F, 60.0F);
    Set(ambiguous, 35, 80.0F, 70.0F);
    AssertClassification(ambiguous, pdr::ActionLabel::Unknown);

    for (auto& point : standing) point.confidence = 0.10F;
    AssertClassification(standing, pdr::ActionLabel::Unknown);

    const auto invalid_box = pdr::ClassifyDogAction(
        lying,
        {0.0F, 0.0F, 0.0F, 100.0F, 1.0F});
    assert(invalid_box.label == pdr::ActionLabel::Unknown);
    assert(invalid_box.scores[3] == 1.0F);

    assert(std::string(pdr::ActionLabelName(pdr::ActionLabel::Standing)) == "STANDING");
    assert(std::string(pdr::ActionLabelName(pdr::ActionLabel::Sitting)) == "SITTING");
    assert(std::string(pdr::ActionLabelName(pdr::ActionLabel::Lying)) == "LYING");
    assert(std::string(pdr::ActionLabelName(pdr::ActionLabel::Unknown)) == "UNKNOWN");
    return 0;
}
