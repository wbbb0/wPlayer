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

void CopyStraightBgra(const uint8_t *source, size_t sourceLength,
    std::vector<uint8_t> &straight)
{
    straight.resize(sourceLength);
    for (size_t offset = 0; offset < sourceLength; offset += 4) {
        const uint8_t alpha = source[offset + 3];
        straight[offset] = Unpremultiply(source[offset], alpha);
        straight[offset + 1] = Unpremultiply(source[offset + 1], alpha);
        straight[offset + 2] = Unpremultiply(source[offset + 2], alpha);
        straight[offset + 3] = alpha;
    }
}

std::string EncodingError(WebPEncodingError code)
{
    return "WebP encoder failed with code " + std::to_string(static_cast<int>(code));
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

    WebPPicture picture;
    if (!WebPPictureInit(&picture)) {
        error = "Unable to initialize WebP picture";
        return false;
    }
    picture.width = width;
    picture.height = height;
    picture.use_argb = 1;

    std::vector<uint8_t> straight;
    const uint8_t *input = bgraSource;
    if (premultiplied) {
        CopyStraightBgra(bgraSource, sourceLength, straight);
        input = straight.data();
    }
    if (!WebPPictureImportBGRA(&picture, input, width * 4)) {
        error = EncodingError(picture.error_code);
        WebPPictureFree(&picture);
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
    WebPPictureFree(&picture);
    return encoded != 0 && !result.empty();
}

} // namespace wplayer::media
