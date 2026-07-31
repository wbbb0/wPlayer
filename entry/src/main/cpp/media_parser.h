#ifndef WPLAYER_MEDIA_PARSER_H
#define WPLAYER_MEDIA_PARSER_H

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace wplayer::media {

enum class MediaFormat {
    MP3,
    FLAC
};

struct TagValue {
    std::string key;
    std::string value;
};

struct Artwork {
    int32_t pictureType = 0;
    std::string mimeType;
    std::string description;
    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t colorDepth = 0;
    uint64_t byteOffset = 0;
    uint64_t byteLength = 0;
    uint64_t payloadOffset = 0;
    uint32_t ordinal = 0;
    bool unsynchronized = false;
};

struct ParsedMedia {
    MediaFormat format = MediaFormat::MP3;
    uint64_t durationMs = 0;
    uint32_t sampleRate = 0;
    uint32_t channelCount = 0;
    uint32_t bitsPerSample = 0;
    std::vector<TagValue> tags;
    std::vector<Artwork> artworks;
};

bool ParseMediaFile(int fd, uint64_t fileSize, ParsedMedia &result, std::string &error);

bool ValidateArtworkRead(int fd, uint64_t fileSize, uint64_t byteOffset,
    uint64_t byteLength, uint64_t payloadOffset, size_t &outputLength,
    std::string &error);

bool ReadArtworkBytes(int fd, uint64_t fileSize, uint64_t byteOffset, uint64_t byteLength,
    uint64_t payloadOffset, bool unsynchronized, std::vector<uint8_t> &result,
    std::string &error);

bool ReadArtworkBytesDirect(int fd, uint64_t fileSize, uint64_t byteOffset,
    uint64_t byteLength, uint64_t payloadOffset, uint8_t *target,
    size_t targetLength, std::string &error);

bool FlattenArtworkPixels(const uint8_t *source, size_t sourceLength, int32_t width,
    int32_t height, bool premultiplied, uint8_t *target, std::string &error);

} // namespace wplayer::media

#endif
