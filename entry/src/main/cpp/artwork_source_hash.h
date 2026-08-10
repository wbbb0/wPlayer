#ifndef WPLAYER_ARTWORK_SOURCE_HASH_H
#define WPLAYER_ARTWORK_SOURCE_HASH_H

#include <cstddef>
#include <cstdint>
#include <string>

namespace wplayer::media {

std::string HashArtworkSourceXXH3_128(const uint8_t *source, size_t sourceLength);

} // namespace wplayer::media

#endif
