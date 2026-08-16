#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace pdr {

struct ImageView {
    const std::uint8_t* rgba = nullptr;
    int width = 0;
    int height = 0;
    int stride = 0;
};

struct Box {
    float left = 0.0F;
    float top = 0.0F;
    float right = 0.0F;
    float bottom = 0.0F;
    float confidence = 0.0F;
};

struct Anchor {
    float center_x;
    float center_y;
    float width;
    float height;
};

struct CropTransform {
    float offset_x;
    float offset_y;
    float scale_x;
    float scale_y;
};

struct SimCCPoint {
    float x;
    float y;
    float confidence;
};

struct PoseKeypoint {
    int index;
    float x;
    float y;
    float confidence;
};

std::vector<Anchor> GenerateSSDLiteAnchors();

Box DecodeSSDLiteBox(
    const Anchor& anchor,
    const float regression[4],
    int image_width,
    int image_height);

std::vector<Box> NonMaximumSuppression(
    std::vector<Box> boxes,
    float iou_threshold,
    std::size_t maximum_results);

CropTransform ComputeTopDownCrop(const Box& box, int margin, int output_width, int output_height);

std::vector<std::uint8_t> BuildPoseCrop(
    const ImageView& image,
    const CropTransform& transform,
    int output_width,
    int output_height);

SimCCPoint DecodeSimCC(
    const float* x_logits,
    std::size_t x_size,
    const float* y_logits,
    std::size_t y_size,
    float split_ratio,
    float logit_scale);

}  // namespace pdr
