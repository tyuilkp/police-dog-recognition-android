#include "postprocess.hpp"

#include <cassert>
#include <cmath>
#include <vector>

namespace {

bool Near(float actual, float expected, float tolerance = 1e-4F) {
    return std::abs(actual - expected) <= tolerance;
}

}  // namespace

int main() {
    const auto anchors = pdr::GenerateSSDLiteAnchors();
    assert(anchors.size() == 3234);
    assert(Near(anchors.front().center_x, 0.025F));
    assert(Near(anchors.front().center_y, 0.025F));
    assert(Near(anchors.front().width, 0.20F));
    assert(Near(anchors.front().height, 0.20F));
    assert(Near(anchors.back().center_x, 0.5F));
    assert(Near(anchors.back().center_y, 0.5F));

    const float zero_regression[] = {0.0F, 0.0F, 0.0F, 0.0F};
    const auto decoded = pdr::DecodeSSDLiteBox(anchors.front(), zero_regression, 640, 320);
    assert(Near(decoded.left, 0.0F));
    assert(Near(decoded.top, 0.0F));
    assert(Near(decoded.right, 80.0F));
    assert(Near(decoded.bottom, 40.0F));

    const auto kept = pdr::NonMaximumSuppression(
        {
            {0.0F, 0.0F, 100.0F, 100.0F, 0.9F},
            {5.0F, 5.0F, 105.0F, 105.0F, 0.8F},
            {200.0F, 200.0F, 250.0F, 250.0F, 0.7F},
        },
        0.55F,
        10);
    assert(kept.size() == 2);
    assert(Near(kept[0].confidence, 0.9F));
    assert(Near(kept[1].confidence, 0.7F));

    const pdr::Box wide_box{20.0F, 40.0F, 220.0F, 140.0F, 1.0F};
    const auto crop = pdr::ComputeTopDownCrop(wide_box, 20, 256, 256);
    assert(Near(crop.offset_x, 0.0F));
    assert(Near(crop.offset_y, -30.0F));
    assert(Near(crop.scale_x, 240.0F / 256.0F));
    assert(Near(crop.scale_y, 240.0F / 256.0F));

    const std::vector<std::uint8_t> rgba = {
        10, 20, 30, 255, 40, 50, 60, 255,
        70, 80, 90, 255, 100, 110, 120, 255,
    };
    const pdr::ImageView image{rgba.data(), 2, 2, 8};
    const auto identity_crop = pdr::BuildPoseCrop(
        image,
        {0.0F, 0.0F, 1.0F, 1.0F},
        2,
        2);
    assert(identity_crop == rgba);
    const auto padded_crop = pdr::BuildPoseCrop(
        image,
        {-1.0F, -1.0F, 1.0F, 1.0F},
        2,
        2);
    assert(padded_crop[0] == 0);
    assert(padded_crop[1] == 0);
    assert(padded_crop[2] == 0);
    assert(padded_crop[3] == 255);
    assert(padded_crop[12] == 10);
    assert(padded_crop[13] == 20);
    assert(padded_crop[14] == 30);
    assert(padded_crop[15] == 255);

    std::vector<float> x_logits(512, -1.0F);
    std::vector<float> y_logits(512, -1.0F);
    x_logits[100] = 1.0F;
    y_logits[200] = 1.0F;
    const auto point = pdr::DecodeSimCC(
        x_logits.data(), x_logits.size(), y_logits.data(), y_logits.size(), 2.0F, 849.0F);
    assert(Near(point.x, 50.0F));
    assert(Near(point.y, 100.0F));
    assert(point.confidence > 0.999F);
    return 0;
}
