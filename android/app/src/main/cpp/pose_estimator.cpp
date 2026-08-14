#include "pose_estimator.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

namespace pdr {
namespace {

constexpr int kInputSize = 256;
constexpr int kKeypointCount = 39;
constexpr int kCropMargin = 20;
constexpr float kSimCCSplitRatio = 2.0F;
constexpr float kSimCCLogitScale = 5.66F * 150.0F;

const float* AxisRow(const ncnn::Mat& axis, const int keypoint) {
    if (axis.dims == 2) return axis.row(keypoint);
    if (axis.dims == 3 && axis.c == 1) return axis.channel(0).row(keypoint);
    return nullptr;
}

int AxisRows(const ncnn::Mat& axis) {
    if (axis.dims == 2) return axis.h;
    if (axis.dims == 3 && axis.c == 1) return axis.h;
    return 0;
}

}  // namespace

bool PoseEstimator::Load(
    AAssetManager* assets,
    const std::string& model_root,
    std::string& error) {
    Clear();
    network_.opt.num_threads = 4;
    network_.opt.use_fp16_packed = true;
    network_.opt.use_fp16_storage = true;
    network_.opt.use_fp16_arithmetic = false;

    const std::string parameter_path = model_root + "/rtmpose_s.ncnn.param";
    const std::string weights_path = model_root + "/rtmpose_s.ncnn.bin";
    if (network_.load_param(assets, parameter_path.c_str()) != 0) {
        error = "Could not load RTMPose-S ncnn parameters";
        return false;
    }
    if (network_.load_model(assets, weights_path.c_str()) != 0) {
        error = "Could not load RTMPose-S ncnn weights";
        return false;
    }
    if (network_.input_names().size() != 1 || network_.output_names().size() != 2) {
        error = "RTMPose-S ncnn graph must have one input and two outputs";
        return false;
    }
    loaded_ = true;
    return true;
}

bool PoseEstimator::Estimate(
    const ImageView& image,
    const Box& dog_box,
    std::vector<PoseKeypoint>& keypoints,
    std::string& error) const {
    keypoints.clear();
    if (!loaded_) {
        error = "RTMPose-S estimator is not loaded";
        return false;
    }

    const CropTransform transform = ComputeTopDownCrop(
        dog_box,
        kCropMargin,
        kInputSize,
        kInputSize);
    const std::vector<std::uint8_t> crop = BuildPoseCrop(
        image,
        transform,
        kInputSize,
        kInputSize);
    if (crop.empty()) {
        error = "Could not build the RTMPose-S crop";
        return false;
    }
    ncnn::Mat input = ncnn::Mat::from_pixels(
        crop.data(),
        ncnn::Mat::PIXEL_RGBA2RGB,
        kInputSize,
        kInputSize);
    const float pose_mean[3] = {0.485F * 255.0F, 0.456F * 255.0F, 0.406F * 255.0F};
    const float pose_norm[3] = {
        1.0F / (0.229F * 255.0F),
        1.0F / (0.224F * 255.0F),
        1.0F / (0.225F * 255.0F),
    };
    input.substract_mean_normalize(pose_mean, pose_norm);

    ncnn::Extractor extractor = network_.create_extractor();
    if (extractor.input(network_.input_names().front(), input) != 0) {
        error = "RTMPose-S rejected its input tensor";
        return false;
    }
    ncnn::Mat simcc_x;
    ncnn::Mat simcc_y;
    if (extractor.extract(network_.output_names()[0], simcc_x) != 0 ||
        extractor.extract(network_.output_names()[1], simcc_y) != 0) {
        error = "RTMPose-S output extraction failed";
        return false;
    }
    if (AxisRows(simcc_x) != kKeypointCount || AxisRows(simcc_y) != kKeypointCount ||
        simcc_x.w != kInputSize * 2 || simcc_y.w != kInputSize * 2) {
        error = "RTMPose-S outputs must be [39,512] SimCC tensors";
        return false;
    }

    keypoints.reserve(kKeypointCount);
    for (int index = 0; index < kKeypointCount; ++index) {
        const float* x_logits = AxisRow(simcc_x, index);
        const float* y_logits = AxisRow(simcc_y, index);
        if (x_logits == nullptr || y_logits == nullptr) {
            error = "RTMPose-S output tensor layout is unsupported";
            return false;
        }
        const SimCCPoint decoded = DecodeSimCC(
            x_logits,
            simcc_x.w,
            y_logits,
            simcc_y.w,
            kSimCCSplitRatio,
            kSimCCLogitScale);
        keypoints.push_back({
            index,
            std::clamp(decoded.x * transform.scale_x + transform.offset_x, 0.0F, static_cast<float>(image.width)),
            std::clamp(decoded.y * transform.scale_y + transform.offset_y, 0.0F, static_cast<float>(image.height)),
            decoded.confidence,
        });
    }
    return true;
}

void PoseEstimator::Clear() {
    network_.clear();
    loaded_ = false;
}

}  // namespace pdr
