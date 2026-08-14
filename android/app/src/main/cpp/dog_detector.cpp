#include "dog_detector.hpp"

#include <algorithm>
#include <cmath>

namespace pdr {
namespace {

constexpr int kInputSize = 320;
constexpr float kScoreThreshold = 0.25F;
constexpr float kNmsThreshold = 0.55F;
constexpr std::size_t kTopCandidates = 300;

const float* MatrixRow(const ncnn::Mat& matrix, const int row) {
    if (matrix.dims == 2) return matrix.row(row);
    if (matrix.dims == 3 && matrix.c == 1) return matrix.channel(0).row(row);
    return nullptr;
}

int MatrixRows(const ncnn::Mat& matrix) {
    if (matrix.dims == 2) return matrix.h;
    if (matrix.dims == 3 && matrix.c == 1) return matrix.h;
    return 0;
}

float DogProbability(const float background_logit, const float dog_logit) {
    const float maximum = std::max(background_logit, dog_logit);
    const float background = std::exp(background_logit - maximum);
    const float dog = std::exp(dog_logit - maximum);
    return dog / (background + dog);
}

}  // namespace

bool DogDetector::Load(
    AAssetManager* assets,
    const std::string& model_root,
    std::string& error) {
    Clear();
    network_.opt.num_threads = 4;
    network_.opt.use_fp16_packed = true;
    network_.opt.use_fp16_storage = true;
    network_.opt.use_fp16_arithmetic = false;

    const std::string parameter_path = model_root + "/ssdlite.ncnn.param";
    const std::string weights_path = model_root + "/ssdlite.ncnn.bin";
    if (network_.load_param(assets, parameter_path.c_str()) != 0) {
        error = "Could not load SSDLite ncnn parameters";
        return false;
    }
    if (network_.load_model(assets, weights_path.c_str()) != 0) {
        error = "Could not load SSDLite ncnn weights";
        return false;
    }
    if (network_.input_names().size() != 1 || network_.output_names().size() != 2) {
        error = "SSDLite ncnn graph must have one input and two outputs";
        return false;
    }
    anchors_ = GenerateSSDLiteAnchors();
    loaded_ = anchors_.size() == 3234;
    if (!loaded_) error = "SSDLite anchor generation failed";
    return loaded_;
}

bool DogDetector::Detect(
    const ImageView& image,
    std::vector<Box>& detections,
    std::string& error) const {
    detections.clear();
    if (!loaded_) {
        error = "SSDLite detector is not loaded";
        return false;
    }
    if (image.rgba == nullptr || image.width <= 0 || image.height <= 0 || image.stride < image.width * 4) {
        error = "Invalid RGBA input image";
        return false;
    }

    ncnn::Mat input = ncnn::Mat::from_pixels_resize(
        image.rgba,
        ncnn::Mat::PIXEL_RGBA2RGB,
        image.width,
        image.height,
        image.stride,
        kInputSize,
        kInputSize);
    const float detector_mean[3] = {127.5F, 127.5F, 127.5F};
    const float detector_norm[3] = {1.0F / 127.5F, 1.0F / 127.5F, 1.0F / 127.5F};
    input.substract_mean_normalize(detector_mean, detector_norm);

    ncnn::Extractor extractor = network_.create_extractor();
    if (extractor.input(network_.input_names().front(), input) != 0) {
        error = "SSDLite rejected its input tensor";
        return false;
    }

    ncnn::Mat regression;
    ncnn::Mat logits;
    for (const char* output_name : network_.output_names()) {
        ncnn::Mat output;
        if (extractor.extract(output_name, output) != 0) {
            error = "SSDLite output extraction failed";
            return false;
        }
        if (output.w == 4) regression = output;
        if (output.w == 2) logits = output;
    }

    const int regression_rows = MatrixRows(regression);
    const int logit_rows = MatrixRows(logits);
    if (regression.w != 4 || logits.w != 2 || regression_rows != 3234 || logit_rows != 3234) {
        error = "SSDLite output tensors do not match [3234,4] and [3234,2]";
        return false;
    }

    std::vector<Box> candidates;
    candidates.reserve(kTopCandidates);
    for (int index = 0; index < regression_rows; ++index) {
        const float* regression_row = MatrixRow(regression, index);
        const float* logit_row = MatrixRow(logits, index);
        if (regression_row == nullptr || logit_row == nullptr) {
            error = "SSDLite output tensor layout is unsupported";
            return false;
        }
        const float score = DogProbability(logit_row[0], logit_row[1]);
        if (score <= kScoreThreshold) continue;
        Box box = DecodeSSDLiteBox(anchors_[index], regression_row, image.width, image.height);
        box.confidence = score;
        if (box.right - box.left >= 2.0F && box.bottom - box.top >= 2.0F) {
            candidates.push_back(box);
        }
    }

    if (candidates.size() > kTopCandidates) {
        std::partial_sort(
            candidates.begin(),
            candidates.begin() + static_cast<std::ptrdiff_t>(kTopCandidates),
            candidates.end(),
            [](const Box& first, const Box& second) { return first.confidence > second.confidence; });
        candidates.resize(kTopCandidates);
    }
    detections = NonMaximumSuppression(std::move(candidates), kNmsThreshold, kTopCandidates);
    return true;
}

void DogDetector::Clear() {
    network_.clear();
    anchors_.clear();
    loaded_ = false;
}

}  // namespace pdr
