#include "postprocess.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <numeric>

namespace pdr {
namespace {

constexpr int kDetectorSize = 320;
constexpr std::array<int, 6> kFeatureSizes = {20, 10, 5, 3, 2, 1};
constexpr std::array<float, 7> kScales = {0.20F, 0.35F, 0.50F, 0.65F, 0.80F, 0.95F, 1.0F};
constexpr std::array<float, 2> kAspectRatios = {2.0F, 3.0F};

float Clamp(const float value, const float low, const float high) {
    return std::max(low, std::min(value, high));
}

float IntersectionOverUnion(const Box& first, const Box& second) {
    const float left = std::max(first.left, second.left);
    const float top = std::max(first.top, second.top);
    const float right = std::min(first.right, second.right);
    const float bottom = std::min(first.bottom, second.bottom);
    const float intersection = std::max(0.0F, right - left) * std::max(0.0F, bottom - top);
    const float first_area = std::max(0.0F, first.right - first.left) *
                             std::max(0.0F, first.bottom - first.top);
    const float second_area = std::max(0.0F, second.right - second.left) *
                              std::max(0.0F, second.bottom - second.top);
    const float denominator = first_area + second_area - intersection;
    return denominator > 0.0F ? intersection / denominator : 0.0F;
}

std::uint8_t SampleChannel(
    const ImageView& image,
    const float source_x,
    const float source_y,
    const int channel) {
    if (source_x < 0.0F || source_y < 0.0F ||
        source_x > image.width - 1.0F || source_y > image.height - 1.0F) {
        return 0;
    }
    const int x0 = static_cast<int>(std::floor(source_x));
    const int y0 = static_cast<int>(std::floor(source_y));
    const int x1 = std::min(x0 + 1, image.width - 1);
    const int y1 = std::min(y0 + 1, image.height - 1);
    const float x_weight = source_x - x0;
    const float y_weight = source_y - y0;
    const auto pixel = [&](const int x, const int y) -> float {
        return image.rgba[y * image.stride + x * 4 + channel];
    };
    const float top = pixel(x0, y0) * (1.0F - x_weight) + pixel(x1, y0) * x_weight;
    const float bottom = pixel(x0, y1) * (1.0F - x_weight) + pixel(x1, y1) * x_weight;
    return static_cast<std::uint8_t>(std::round(top * (1.0F - y_weight) + bottom * y_weight));
}

std::pair<std::size_t, float> SoftmaxMaximum(
    const float* logits,
    const std::size_t size,
    const float scale) {
    const auto maximum = std::max_element(logits, logits + size);
    const std::size_t maximum_index = static_cast<std::size_t>(maximum - logits);
    const float shifted_maximum = *maximum * scale;
    double denominator = 0.0;
    for (std::size_t index = 0; index < size; ++index) {
        denominator += std::exp(static_cast<double>(logits[index] * scale - shifted_maximum));
    }
    const float probability = denominator > 0.0
        ? static_cast<float>(1.0 / denominator)
        : 0.0F;
    return {maximum_index, probability};
}

}  // namespace

std::vector<Anchor> GenerateSSDLiteAnchors() {
    std::vector<Anchor> anchors;
    anchors.reserve(3234);
    for (std::size_t level = 0; level < kFeatureSizes.size(); ++level) {
        const int feature_size = kFeatureSizes[level];
        const float scale = kScales[level];
        const float prime_scale = std::sqrt(kScales[level] * kScales[level + 1]);
        std::array<std::pair<float, float>, 6> dimensions = {
            std::pair<float, float>{scale, scale},
            {prime_scale, prime_scale},
            {scale * std::sqrt(kAspectRatios[0]), scale / std::sqrt(kAspectRatios[0])},
            {scale / std::sqrt(kAspectRatios[0]), scale * std::sqrt(kAspectRatios[0])},
            {scale * std::sqrt(kAspectRatios[1]), scale / std::sqrt(kAspectRatios[1])},
            {scale / std::sqrt(kAspectRatios[1]), scale * std::sqrt(kAspectRatios[1])},
        };
        for (int y = 0; y < feature_size; ++y) {
            for (int x = 0; x < feature_size; ++x) {
                const float center_x = (static_cast<float>(x) + 0.5F) / feature_size;
                const float center_y = (static_cast<float>(y) + 0.5F) / feature_size;
                for (const auto& [width, height] : dimensions) {
                    anchors.push_back({
                        center_x,
                        center_y,
                        Clamp(width, 0.0F, 1.0F),
                        Clamp(height, 0.0F, 1.0F),
                    });
                }
            }
        }
    }
    return anchors;
}

Box DecodeSSDLiteBox(
    const Anchor& anchor,
    const float regression[4],
    const int image_width,
    const int image_height) {
    const float anchor_width = anchor.width * kDetectorSize;
    const float anchor_height = anchor.height * kDetectorSize;
    const float anchor_center_x = anchor.center_x * kDetectorSize;
    const float anchor_center_y = anchor.center_y * kDetectorSize;
    const float predicted_center_x = regression[0] / 10.0F * anchor_width + anchor_center_x;
    const float predicted_center_y = regression[1] / 10.0F * anchor_height + anchor_center_y;
    const float predicted_width = std::exp(std::min(regression[2] / 5.0F, 4.1351666F)) * anchor_width;
    const float predicted_height = std::exp(std::min(regression[3] / 5.0F, 4.1351666F)) * anchor_height;
    const float scale_x = static_cast<float>(image_width) / kDetectorSize;
    const float scale_y = static_cast<float>(image_height) / kDetectorSize;
    return {
        Clamp((predicted_center_x - predicted_width / 2.0F) * scale_x, 0.0F, static_cast<float>(image_width)),
        Clamp((predicted_center_y - predicted_height / 2.0F) * scale_y, 0.0F, static_cast<float>(image_height)),
        Clamp((predicted_center_x + predicted_width / 2.0F) * scale_x, 0.0F, static_cast<float>(image_width)),
        Clamp((predicted_center_y + predicted_height / 2.0F) * scale_y, 0.0F, static_cast<float>(image_height)),
        0.0F,
    };
}

std::vector<Box> NonMaximumSuppression(
    std::vector<Box> boxes,
    const float iou_threshold,
    const std::size_t maximum_results) {
    std::sort(boxes.begin(), boxes.end(), [](const Box& first, const Box& second) {
        return first.confidence > second.confidence;
    });
    std::vector<Box> selected;
    selected.reserve(std::min(boxes.size(), maximum_results));
    for (const auto& candidate : boxes) {
        const bool overlaps = std::any_of(selected.begin(), selected.end(), [&](const Box& kept) {
            return IntersectionOverUnion(candidate, kept) > iou_threshold;
        });
        if (!overlaps) selected.push_back(candidate);
        if (selected.size() == maximum_results) break;
    }
    return selected;
}

CropTransform ComputeTopDownCrop(
    const Box& box,
    const int margin,
    const int output_width,
    const int output_height) {
    const float center_x = (box.left + box.right) / 2.0F;
    const float center_y = (box.top + box.bottom) / 2.0F;
    float width = box.right - box.left + 2.0F * margin;
    float height = box.bottom - box.top + 2.0F * margin;
    const float output_ratio = static_cast<float>(output_width) / output_height;
    if (width / height > output_ratio) {
        height = width / output_ratio;
    } else {
        width = height * output_ratio;
    }
    const float x1 = std::round(center_x - width / 2.0F);
    const float y1 = std::round(center_y - height / 2.0F);
    const float x2 = std::round(center_x + width / 2.0F);
    const float y2 = std::round(center_y + height / 2.0F);
    return {
        x1,
        y1,
        (x2 - x1) / output_width,
        (y2 - y1) / output_height,
    };
}

std::vector<std::uint8_t> BuildPoseCrop(
    const ImageView& image,
    const CropTransform& transform,
    const int output_width,
    const int output_height) {
    if (image.rgba == nullptr || image.width <= 0 || image.height <= 0 ||
        image.stride < image.width * 4 || output_width <= 0 || output_height <= 0) {
        return {};
    }
    std::vector<std::uint8_t> crop(
        static_cast<std::size_t>(output_width) * output_height * 4,
        0);
    for (int y = 0; y < output_height; ++y) {
        for (int x = 0; x < output_width; ++x) {
            const float source_x = transform.offset_x + (x + 0.5F) * transform.scale_x - 0.5F;
            const float source_y = transform.offset_y + (y + 0.5F) * transform.scale_y - 0.5F;
            const std::size_t destination =
                (static_cast<std::size_t>(y) * output_width + x) * 4;
            crop[destination] = SampleChannel(image, source_x, source_y, 0);
            crop[destination + 1] = SampleChannel(image, source_x, source_y, 1);
            crop[destination + 2] = SampleChannel(image, source_x, source_y, 2);
            crop[destination + 3] = 255;
        }
    }
    return crop;
}

SimCCPoint DecodeSimCC(
    const float* x_logits,
    const std::size_t x_size,
    const float* y_logits,
    const std::size_t y_size,
    const float split_ratio,
    const float logit_scale) {
    const auto [x_index, x_probability] = SoftmaxMaximum(x_logits, x_size, logit_scale);
    const auto [y_index, y_probability] = SoftmaxMaximum(y_logits, y_size, logit_scale);
    return {
        static_cast<float>(x_index) / split_ratio,
        static_cast<float>(y_index) / split_ratio,
        std::min(x_probability, y_probability),
    };
}

}  // namespace pdr
