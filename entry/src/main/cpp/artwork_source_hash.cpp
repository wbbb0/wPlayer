#include "artwork_source_hash.h"

#define XXH_INLINE_ALL
#include <xxhash.h>

namespace wplayer::media {

std::string HashArtworkSourceXXH3_128(const uint8_t *source, size_t sourceLength)
{
    if (source == nullptr && sourceLength > 0) {
        return {};
    }
    const XXH128_hash_t hash = XXH3_128bits(source, sourceLength);
    XXH128_canonical_t canonical = {};
    XXH128_canonicalFromHash(&canonical, hash);
    static constexpr char HEX[] = "0123456789abcdef";
    std::string result(sizeof(canonical.digest) * 2, '0');
    for (size_t index = 0; index < sizeof(canonical.digest); ++index) {
        const uint8_t value = canonical.digest[index];
        result[index * 2] = HEX[value >> 4];
        result[index * 2 + 1] = HEX[value & 0x0f];
    }
    return result;
}

} // namespace wplayer::media
