#ifndef WPLAYER_ARTWORK_WEBP_ENCODER_H
#define WPLAYER_ARTWORK_WEBP_ENCODER_H

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace wplayer::media {

struct ArtworkWebPEncodeOptions {
    float quality = 84.0f;
    int32_t method = 4;
    int32_t alphaQuality = 100;
};

// Pixel bytes use BGRA order, matching the native PixelMap buffer consumed by the app.
bool EncodeArtworkWebP(const uint8_t *bgraSource, size_t sourceLength, int32_t width,
    int32_t height, bool premultiplied, const ArtworkWebPEncodeOptions &options,
    std::vector<uint8_t> &result, std::string &error);

} // namespace wplayer::media

#endif
