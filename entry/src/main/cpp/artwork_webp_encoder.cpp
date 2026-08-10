#include "artwork_webp_encoder.h"

#include <algorithm>
#include <limits>
#include <webp/encode.h>

namespace wplayer::media {
namespace {

bool ValidateInput(const uint8_t *source, size_t sourceLength, int32_t width,
    int32_t height, const ArtworkWebPEncodeOptions &options, std::string &error)
{
    if (source == nullptr || width <= 0 || height <= 0) {
        error = "Invalid artwork WebP input";
        return false;
    }
    const size_t widthValue = static_cast<size_t>(width);
    const size_t heightValue = static_cast<size_t>(height);
    if (widthValue > std::numeric_limits<size_t>::max() / heightValue ||
        widthValue * heightValue > std::numeric_limits<size_t>::max() / 4 ||
        sourceLength != widthValue * heightValue * 4) {
        error = "Artwork WebP pixel buffer size does not match dimensions";
        return false;
    }
    if (options.quality < 0.0f || options.quality > 100.0f ||
        options.method < 0 || options.method > 6 ||
        options.alphaQuality < 0 || options.alphaQuality > 100) {
        error = "Invalid artwork WebP encoding options";
        return false;
    }
    return true;
}

uint8_t Unpremultiply(uint8_t value, uint8_t alpha)
{
    if (alpha == 0) {
        return 0;
    }
    if (alpha == 255) {
        return value;
    }
    const uint32_t restored =
        (static_cast<uint32_t>(value) * 255U + static_cast<uint32_t>(alpha) / 2U) /
        static_cast<uint32_t>(alpha);
    return static_cast<uint8_t>(std::min(restored, 255U));
}

std::string EncodingError(WebPEncodingError code);

bool ImportBgra(const uint8_t *source, int32_t width, int32_t height,
    bool premultiplied, WebPPicture &picture, std::string &error)
{
    if (!WebPPictureInit(&picture)) {
        error = "Unable to initialize WebP picture";
        return false;
    }
    picture.width = width;
    picture.height = height;
    picture.use_argb = 1;
    if (!WebPPictureAlloc(&picture)) {
        error = EncodingError(picture.error_code);
        return false;
    }
    for (int32_t y = 0; y < height; ++y) {
        uint32_t *target = picture.argb + static_cast<size_t>(y) * picture.argb_stride;
        const uint8_t *row = source + static_cast<size_t>(y) * width * 4;
        for (int32_t x = 0; x < width; ++x) {
            const uint8_t *pixel = row + static_cast<size_t>(x) * 4;
            const uint8_t alpha = pixel[3];
            const uint8_t red = premultiplied ? Unpremultiply(pixel[2], alpha) : pixel[2];
            const uint8_t green = premultiplied ? Unpremultiply(pixel[1], alpha) : pixel[1];
            const uint8_t blue = premultiplied ? Unpremultiply(pixel[0], alpha) : pixel[0];
            target[x] = (static_cast<uint32_t>(alpha) << 24U) |
                (static_cast<uint32_t>(red) << 16U) |
                (static_cast<uint32_t>(green) << 8U) | blue;
        }
    }
    return true;
}

std::string EncodingError(WebPEncodingError code)
{
    return "WebP encoder failed with code " + std::to_string(static_cast<int>(code));
}

bool EncodePicture(WebPPicture &picture, const ArtworkWebPEncodeOptions &options,
    std::vector<uint8_t> &result, std::string &error)
{
    WebPConfig config;
    if (!WebPConfigPreset(&config, WEBP_PRESET_PICTURE, options.quality)) {
        error = "Unable to initialize WebP encoder configuration";
        return false;
    }
    config.lossless = 0;
    config.method = options.method;
    config.alpha_quality = options.alphaQuality;
    config.thread_level = 0;
    if (!WebPValidateConfig(&config)) {
        error = "Invalid WebP encoder configuration";
        return false;
    }
    WebPMemoryWriter writer;
    WebPMemoryWriterInit(&writer);
    picture.writer = WebPMemoryWrite;
    picture.custom_ptr = &writer;
    const int encoded = WebPEncode(&config, &picture);
    if (encoded == 0) {
        error = EncodingError(picture.error_code);
    } else if (writer.mem == nullptr || writer.size == 0) {
        error = "WebP encoder produced no output";
    } else {
        result.assign(writer.mem, writer.mem + writer.size);
    }
    WebPMemoryWriterClear(&writer);
    return encoded != 0 && !result.empty();
}

bool CopyAndRescale(const WebPPicture &source, int32_t width, int32_t height,
    WebPPicture &target, std::string &error)
{
    if (!WebPPictureInit(&target) || !WebPPictureCopy(&source, &target)) {
        error = "Unable to copy WebP picture";
        return false;
    }
    if (!WebPPictureRescale(&target, width, height)) {
        error = EncodingError(target.error_code);
        return false;
    }
    return true;
}

void ExportBgra(const WebPPicture &picture, std::vector<uint8_t> &result)
{
    result.resize(static_cast<size_t>(picture.width) * picture.height * 4);
    for (int32_t y = 0; y < picture.height; ++y) {
        const uint32_t *row = picture.argb + static_cast<size_t>(y) * picture.argb_stride;
        uint8_t *target = result.data() + static_cast<size_t>(y) * picture.width * 4;
        for (int32_t x = 0; x < picture.width; ++x) {
            const uint32_t pixel = row[x];
            target[x * 4] = static_cast<uint8_t>(pixel & 0xffU);
            target[x * 4 + 1] = static_cast<uint8_t>((pixel >> 8U) & 0xffU);
            target[x * 4 + 2] = static_cast<uint8_t>((pixel >> 16U) & 0xffU);
            target[x * 4 + 3] = static_cast<uint8_t>((pixel >> 24U) & 0xffU);
        }
    }
}

} // namespace

bool EncodeArtworkWebP(const uint8_t *bgraSource, size_t sourceLength, int32_t width,
    int32_t height, bool premultiplied, const ArtworkWebPEncodeOptions &options,
    std::vector<uint8_t> &result, std::string &error)
{
    result.clear();
    if (!ValidateInput(bgraSource, sourceLength, width, height, options, error)) {
        return false;
    }

    WebPPicture picture = {};
    if (!ImportBgra(bgraSource, width, height, premultiplied, picture, error)) {
        WebPPictureFree(&picture);
        return false;
    }
    const bool encoded = EncodePicture(picture, options, result, error);
    WebPPictureFree(&picture);
    return encoded;
}

bool EncodeArtworkWebPVariants(const uint8_t *bgraSource, size_t sourceLength,
    int32_t width, int32_t height, bool premultiplied,
    int32_t smallWidth, int32_t smallHeight,
    int32_t paletteWidth, int32_t paletteHeight,
    const ArtworkWebPEncodeOptions &options, ArtworkWebPVariants &result, std::string &error)
{
    result = {};
    if (!ValidateInput(bgraSource, sourceLength, width, height, options, error) ||
        smallWidth <= 0 || smallHeight <= 0 || smallWidth > width || smallHeight > height ||
        paletteWidth <= 0 || paletteHeight <= 0 || paletteWidth > width || paletteHeight > height) {
        if (error.empty()) {
            error = "Invalid artwork WebP variant dimensions";
        }
        return false;
    }
    WebPPicture large = {};
    WebPPicture small = {};
    WebPPicture palette = {};
    if (!ImportBgra(bgraSource, width, height, premultiplied, large, error)) {
        WebPPictureFree(&large);
        return false;
    }
    bool success = CopyAndRescale(large, smallWidth, smallHeight, small, error) &&
        CopyAndRescale(small, paletteWidth, paletteHeight, palette, error) &&
        EncodePicture(large, options, result.large, error) &&
        EncodePicture(small, options, result.small, error);
    if (success) {
        ExportBgra(palette, result.paletteBgra);
        success = !result.paletteBgra.empty();
    }
    WebPPictureFree(&palette);
    WebPPictureFree(&small);
    WebPPictureFree(&large);
    return success;
}

} // namespace wplayer::media
