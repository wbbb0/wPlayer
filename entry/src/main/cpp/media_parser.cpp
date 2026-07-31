#include "media_parser.h"

#include <algorithm>
#include <cerrno>
#include <cctype>
#include <cmath>
#include <cstring>
#include <limits>
#include <string_view>
#include <unistd.h>
#include <utility>

namespace wplayer::media {
namespace {

constexpr uint64_t MAX_ID3_TAG_BYTES = 32ULL * 1024 * 1024;
constexpr uint64_t MAX_ID3_FRAME_BYTES = 16ULL * 1024 * 1024;
constexpr uint64_t MAX_ARTWORK_BYTES = 64ULL * 1024 * 1024;
constexpr uint32_t MAX_ID3_FRAME_COUNT = 8192;
constexpr uint32_t MAX_ARTWORK_COUNT = 32;
constexpr uint64_t MAX_FLAC_BLOCK_BYTES = 32ULL * 1024 * 1024;
constexpr uint64_t MAX_FLAC_COMMENT_BYTES = 8ULL * 1024 * 1024;
constexpr uint32_t MAX_FLAC_COMMENT_COUNT = 4096;
constexpr uint32_t MAX_FLAC_BLOCK_COUNT = 256;
constexpr uint64_t MAX_FLAC_METADATA_BYTES = 64ULL * 1024 * 1024;
constexpr uint32_t MAX_MIME_BYTES = 256;
constexpr uint32_t MAX_DESCRIPTION_BYTES = 64 * 1024;
constexpr uint32_t REPLACEMENT_CHARACTER = 0xFFFD;

bool CheckedRange(uint64_t offset, uint64_t length, uint64_t total)
{
    return offset <= total && length <= total - offset;
}

bool ReadExactInto(int fd, uint64_t fileSize, uint64_t offset, uint8_t *target,
    size_t length, std::string &error)
{
    if (!CheckedRange(offset, length, fileSize) || (length > 0 && target == nullptr)) {
        error = "Invalid file range";
        return false;
    }
    size_t totalRead = 0;
    while (totalRead < length) {
        const ssize_t count = pread(fd, target + totalRead, length - totalRead,
            static_cast<off_t>(offset + totalRead));
        if (count < 0 && errno == EINTR) {
            continue;
        }
        if (count <= 0) {
            error = count == 0 ? "Unexpected end of file" :
                "Unable to read media file: " + std::string(std::strerror(errno));
            return false;
        }
        totalRead += static_cast<size_t>(count);
    }
    return true;
}

bool ReadExact(int fd, uint64_t fileSize, uint64_t offset, size_t length,
    std::vector<uint8_t> &result, std::string &error)
{
    result.resize(length);
    return ReadExactInto(fd, fileSize, offset, result.data(), length, error);
}

uint16_t Uint16BE(const uint8_t *bytes)
{
    return static_cast<uint16_t>((static_cast<uint16_t>(bytes[0]) << 8) | bytes[1]);
}

uint32_t Uint24BE(const uint8_t *bytes)
{
    return (static_cast<uint32_t>(bytes[0]) << 16) |
        (static_cast<uint32_t>(bytes[1]) << 8) | bytes[2];
}

uint32_t Uint32BE(const uint8_t *bytes)
{
    return (static_cast<uint32_t>(bytes[0]) << 24) |
        (static_cast<uint32_t>(bytes[1]) << 16) |
        (static_cast<uint32_t>(bytes[2]) << 8) | bytes[3];
}

uint32_t Uint32LE(const uint8_t *bytes)
{
    return static_cast<uint32_t>(bytes[0]) |
        (static_cast<uint32_t>(bytes[1]) << 8) |
        (static_cast<uint32_t>(bytes[2]) << 16) |
        (static_cast<uint32_t>(bytes[3]) << 24);
}

uint32_t SyncSafe32(const uint8_t *bytes)
{
    return (static_cast<uint32_t>(bytes[0]) << 21) |
        (static_cast<uint32_t>(bytes[1]) << 14) |
        (static_cast<uint32_t>(bytes[2]) << 7) | bytes[3];
}

void AppendUtf8(std::string &output, uint32_t codePoint)
{
    if (codePoint <= 0x7F) {
        output.push_back(static_cast<char>(codePoint));
    } else if (codePoint <= 0x7FF) {
        output.push_back(static_cast<char>(0xC0 | (codePoint >> 6)));
        output.push_back(static_cast<char>(0x80 | (codePoint & 0x3F)));
    } else if (codePoint <= 0xFFFF) {
        output.push_back(static_cast<char>(0xE0 | (codePoint >> 12)));
        output.push_back(static_cast<char>(0x80 | ((codePoint >> 6) & 0x3F)));
        output.push_back(static_cast<char>(0x80 | (codePoint & 0x3F)));
    } else {
        output.push_back(static_cast<char>(0xF0 | (codePoint >> 18)));
        output.push_back(static_cast<char>(0x80 | ((codePoint >> 12) & 0x3F)));
        output.push_back(static_cast<char>(0x80 | ((codePoint >> 6) & 0x3F)));
        output.push_back(static_cast<char>(0x80 | (codePoint & 0x3F)));
    }
}

std::string DecodeLatin1(const uint8_t *bytes, size_t length)
{
    std::string output;
    output.reserve(length);
    for (size_t index = 0; index < length; ++index) {
        AppendUtf8(output, bytes[index]);
    }
    return output;
}

std::string DecodeTrimmedLatin1(const uint8_t *bytes, size_t length)
{
    const auto isSpace = [](uint8_t value) {
        return value == 0x09 || value == 0x0A || value == 0x0B ||
            value == 0x0C || value == 0x0D || value == 0x20 || value == 0xA0;
    };
    size_t start = 0;
    while (start < length && isSpace(bytes[start])) {
        ++start;
    }
    while (length > start && isSpace(bytes[length - 1])) {
        --length;
    }
    return DecodeLatin1(bytes + start, length - start);
}

bool IsContinuation(uint8_t value)
{
    return (value & 0xC0) == 0x80;
}

std::string DecodeUtf8(const uint8_t *bytes, size_t length)
{
    std::string output;
    output.reserve(length);
    size_t index = 0;
    while (index < length) {
        const uint8_t first = bytes[index];
        if (first <= 0x7F) {
            output.push_back(static_cast<char>(first));
            ++index;
            continue;
        }
        uint32_t codePoint = 0;
        size_t sequenceLength = 0;
        uint32_t minimum = 0;
        if (first >= 0xC2 && first <= 0xDF) {
            codePoint = first & 0x1F;
            sequenceLength = 2;
            minimum = 0x80;
        } else if (first >= 0xE0 && first <= 0xEF) {
            codePoint = first & 0x0F;
            sequenceLength = 3;
            minimum = 0x800;
        } else if (first >= 0xF0 && first <= 0xF4) {
            codePoint = first & 0x07;
            sequenceLength = 4;
            minimum = 0x10000;
        }
        if (sequenceLength == 0) {
            AppendUtf8(output, REPLACEMENT_CHARACTER);
            ++index;
            continue;
        }
        size_t consumed = 1;
        bool valid = true;
        while (consumed < sequenceLength && index + consumed < length) {
            const uint8_t continuation = bytes[index + consumed];
            if (!IsContinuation(continuation)) {
                valid = false;
                break;
            }
            if (consumed == 1 &&
                ((first == 0xE0 && continuation < 0xA0) ||
                 (first == 0xED && continuation > 0x9F) ||
                 (first == 0xF0 && continuation < 0x90) ||
                 (first == 0xF4 && continuation > 0x8F))) {
                valid = false;
                break;
            }
            codePoint = (codePoint << 6) | (continuation & 0x3F);
            ++consumed;
        }
        if (!valid) {
            AppendUtf8(output, REPLACEMENT_CHARACTER);
            index += consumed;
            continue;
        }
        if (consumed < sequenceLength) {
            AppendUtf8(output, REPLACEMENT_CHARACTER);
            index += consumed;
            continue;
        }
        if (codePoint < minimum || codePoint > 0x10FFFF ||
            (codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
            AppendUtf8(output, REPLACEMENT_CHARACTER);
            ++index;
            continue;
        }
        AppendUtf8(output, codePoint);
        index += sequenceLength;
    }
    return output;
}

std::string DecodeUtf16(const uint8_t *bytes, size_t length, bool defaultBigEndian,
    bool honorBom)
{
    bool bigEndian = defaultBigEndian;
    size_t index = 0;
    if (honorBom && length >= 2) {
        if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
            bigEndian = true;
            index = 2;
        } else if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
            bigEndian = false;
            index = 2;
        }
    }
    std::string output;
    output.reserve(length);
    auto unitAt = [bytes, bigEndian](size_t offset) -> uint16_t {
        return bigEndian ? Uint16BE(bytes + offset) :
            static_cast<uint16_t>(bytes[offset] | (static_cast<uint16_t>(bytes[offset + 1]) << 8));
    };
    while (index + 1 < length) {
        const uint16_t first = unitAt(index);
        index += 2;
        if (first >= 0xD800 && first <= 0xDBFF) {
            if (index + 1 < length) {
                const uint16_t second = unitAt(index);
                if (second >= 0xDC00 && second <= 0xDFFF) {
                    index += 2;
                    AppendUtf8(output, 0x10000 +
                        ((static_cast<uint32_t>(first) - 0xD800) << 10) +
                        (static_cast<uint32_t>(second) - 0xDC00));
                    continue;
                }
            } else if (index < length) {
                index = length;
            }
            AppendUtf8(output, REPLACEMENT_CHARACTER);
        } else if (first >= 0xDC00 && first <= 0xDFFF) {
            AppendUtf8(output, REPLACEMENT_CHARACTER);
        } else {
            AppendUtf8(output, first);
        }
    }
    if (index < length) {
        AppendUtf8(output, REPLACEMENT_CHARACTER);
    }
    return output;
}

std::string DecodeId3Text(uint8_t encoding, const uint8_t *bytes, size_t length)
{
    if (encoding == 0) {
        size_t end = 0;
        while (end < length && bytes[end] != 0) {
            ++end;
        }
        return DecodeLatin1(bytes, end);
    }
    if (encoding == 1) {
        return DecodeUtf16(bytes, length, false, true);
    }
    if (encoding == 2) {
        return DecodeUtf16(bytes, length, true, false);
    }
    return DecodeUtf8(bytes, length);
}

size_t FindTerminator(const std::vector<uint8_t> &bytes, size_t start, size_t width)
{
    for (size_t index = start; index + width <= bytes.size(); index += width) {
        if (bytes[index] == 0 && (width == 1 || bytes[index + 1] == 0)) {
            return index;
        }
    }
    return std::string::npos;
}

std::vector<uint8_t> RemoveUnsynchronization(const uint8_t *bytes, size_t length)
{
    std::vector<uint8_t> output;
    output.reserve(length);
    for (size_t index = 0; index < length; ++index) {
        output.push_back(bytes[index]);
        if (bytes[index] == 0xFF && index + 1 < length && bytes[index + 1] == 0) {
            ++index;
        }
    }
    return output;
}

void AddTag(ParsedMedia &result, std::string key, std::string value)
{
    result.tags.push_back({ std::move(key), std::move(value) });
}

std::string MapV22Id(std::string id)
{
    static const std::pair<std::string_view, std::string_view> mappings[] = {
        { "TT2", "TIT2" }, { "TAL", "TALB" }, { "TP1", "TPE1" },
        { "TP2", "TPE2" }, { "TCM", "TCOM" }, { "TXT", "TEXT" },
        { "TCO", "TCON" }, { "TRK", "TRCK" }, { "TPA", "TPOS" },
        { "TYE", "TYER" }, { "TOR", "TORY" }, { "PIC", "PIC" },
        { "ULT", "USLT" }
    };
    for (const auto &mapping : mappings) {
        if (id == mapping.first) {
            return std::string(mapping.second);
        }
    }
    return id;
}

struct Id3Frame {
    std::string id;
    uint64_t dataOffset = 0;
    uint64_t dataLength = 0;
    bool unsynchronized = false;
};

bool ReadId3FrameHeader(int fd, uint64_t fileSize, uint64_t offset, uint64_t tagEnd,
    uint8_t version, bool globalUnsynchronization, Id3Frame &frame, bool &hasFrame,
    std::string &error)
{
    const size_t headerSize = version == 2 ? 6 : 10;
    hasFrame = false;
    if (!CheckedRange(offset, headerSize, tagEnd)) {
        return true;
    }
    std::vector<uint8_t> bytes;
    if (!ReadExact(fd, fileSize, offset, headerSize, bytes, error)) {
        return false;
    }
    const size_t idLength = version == 2 ? 3 : 4;
    std::string id;
    for (size_t index = 0; index < idLength; ++index) {
        if (bytes[index] == 0) {
            return true;
        }
        id.push_back(static_cast<char>(bytes[index]));
    }
    const uint32_t frameSize = version == 2 ? Uint24BE(bytes.data() + 3) :
        (version == 4 ? SyncSafe32(bytes.data() + 4) : Uint32BE(bytes.data() + 4));
    if (frameSize == 0 || !CheckedRange(offset + headerSize, frameSize, tagEnd)) {
        return true;
    }
    const uint8_t formatFlags = version == 2 ? 0 : bytes[9];
    const bool unsupported = version == 3 ? (formatFlags & 0xC0) != 0 :
        (version == 4 && (formatFlags & 0x0C) != 0);
    if (unsupported) {
        frame = { "", offset + headerSize, frameSize, false };
        hasFrame = true;
        return true;
    }
    uint32_t prefixLength = 0;
    if (version == 3 && (formatFlags & 0x20) != 0) {
        prefixLength = 1;
    } else if (version == 4) {
        if ((formatFlags & 0x40) != 0) {
            ++prefixLength;
        }
        if ((formatFlags & 0x01) != 0) {
            prefixLength += 4;
        }
    }
    if (prefixLength >= frameSize) {
        return true;
    }
    frame = {
        version == 2 ? MapV22Id(id) : id,
        offset + headerSize + prefixLength,
        frameSize - prefixLength,
        globalUnsynchronization || (version == 4 && (formatFlags & 0x02) != 0)
    };
    hasFrame = true;
    return true;
}

bool ReadFrameBytes(int fd, uint64_t fileSize, const Id3Frame &frame,
    std::vector<uint8_t> &bytes, std::string &error)
{
    if (!ReadExact(fd, fileSize, frame.dataOffset, static_cast<size_t>(frame.dataLength),
        bytes, error)) {
        return false;
    }
    if (frame.unsynchronized) {
        bytes = RemoveUnsynchronization(bytes.data(), bytes.size());
    }
    return true;
}

bool ParseId3TextFrame(int fd, uint64_t fileSize, const Id3Frame &frame,
    ParsedMedia &result, std::string &error)
{
    std::vector<uint8_t> bytes;
    if (!ReadFrameBytes(fd, fileSize, frame, bytes, error)) {
        return false;
    }
    if (bytes.size() < 2) {
        return true;
    }
    AddTag(result, frame.id, DecodeId3Text(bytes[0], bytes.data() + 1, bytes.size() - 1));
    return true;
}

bool ParseId3Lyrics(int fd, uint64_t fileSize, const Id3Frame &frame,
    ParsedMedia &result, std::string &error)
{
    std::vector<uint8_t> bytes;
    if (!ReadFrameBytes(fd, fileSize, frame, bytes, error)) {
        return false;
    }
    if (bytes.size() < 5) {
        return true;
    }
    const uint8_t encoding = bytes[0];
    const size_t terminatorWidth = encoding == 1 || encoding == 2 ? 2 : 1;
    const size_t descriptionEnd = FindTerminator(bytes, 4, terminatorWidth);
    if (descriptionEnd == std::string::npos) {
        return true;
    }
    const size_t lyricsOffset = descriptionEnd + terminatorWidth;
    AddTag(result, "USLT", DecodeId3Text(encoding, bytes.data() + lyricsOffset,
        bytes.size() - lyricsOffset));
    return true;
}

bool ParseId3Picture(int fd, uint64_t fileSize, const Id3Frame &frame, uint8_t version,
    uint32_t ordinal, ParsedMedia &result, std::string &error)
{
    std::vector<uint8_t> bytes;
    if (frame.unsynchronized) {
        if (!ReadFrameBytes(fd, fileSize, frame, bytes, error)) {
            return false;
        }
    } else {
        size_t prefixLength = static_cast<size_t>(
            std::min<uint64_t>(frame.dataLength, 4096));
        while (true) {
            if (!ReadExact(fd, fileSize, frame.dataOffset, prefixLength, bytes, error)) {
                return false;
            }
            if (bytes.size() >= 8) {
                size_t probeOffset = 1;
                size_t mimeEnd = std::string::npos;
                if (version == 2) {
                    if (bytes.size() >= 5) {
                        mimeEnd = 4;
                        probeOffset = 5;
                    }
                } else {
                    mimeEnd = FindTerminator(bytes, probeOffset, 1);
                    if (mimeEnd != std::string::npos) {
                        probeOffset = mimeEnd + 2;
                    }
                }
                if (mimeEnd != std::string::npos && probeOffset <= bytes.size()) {
                    const uint8_t encoding = bytes[0];
                    const size_t width = encoding == 1 || encoding == 2 ? 2 : 1;
                    if (FindTerminator(bytes, probeOffset, width) != std::string::npos) {
                        break;
                    }
                }
            }
            if (prefixLength >= frame.dataLength) {
                break;
            }
            prefixLength = static_cast<size_t>(
                std::min<uint64_t>(frame.dataLength, prefixLength * 2ULL));
        }
    }
    if (bytes.size() < 8) {
        return true;
    }
    const uint8_t encoding = bytes[0];
    size_t offset = 1;
    std::string mimeType;
    if (version == 2) {
        if (offset + 3 > bytes.size()) {
            return true;
        }
        std::string format = DecodeTrimmedLatin1(bytes.data() + offset, 3);
        std::transform(format.begin(), format.end(), format.begin(),
            [](unsigned char value) { return static_cast<char>(std::toupper(value)); });
        mimeType = format == "PNG" ? "image/png" : "image/jpeg";
        offset += 3;
    } else {
        const size_t mimeEnd = FindTerminator(bytes, offset, 1);
        if (mimeEnd == std::string::npos) {
            return true;
        }
        mimeType = DecodeTrimmedLatin1(bytes.data() + offset, mimeEnd - offset);
        offset = mimeEnd + 1;
        if (mimeType == "-->") {
            return true;
        }
    }
    if (offset >= bytes.size()) {
        return true;
    }
    const int32_t pictureType = bytes[offset++];
    const size_t terminatorWidth = encoding == 1 || encoding == 2 ? 2 : 1;
    const size_t descriptionEnd = FindTerminator(bytes, offset, terminatorWidth);
    if (descriptionEnd == std::string::npos) {
        return true;
    }
    const std::string description = encoding == 0 ?
        DecodeTrimmedLatin1(bytes.data() + offset, descriptionEnd - offset) :
        DecodeId3Text(encoding, bytes.data() + offset, descriptionEnd - offset);
    offset = descriptionEnd + terminatorWidth;
    if (offset > frame.dataLength) {
        return true;
    }
    const uint64_t imageLength = frame.unsynchronized ?
        bytes.size() - offset : frame.dataLength - offset;
    if (imageLength == 0 || imageLength > MAX_ARTWORK_BYTES) {
        return true;
    }
    result.artworks.push_back({
        pictureType <= 20 ? pictureType : 0,
        std::move(mimeType),
        description,
        0,
        0,
        0,
        frame.unsynchronized ? frame.dataOffset : frame.dataOffset + offset,
        frame.unsynchronized ? frame.dataLength : imageLength,
        frame.unsynchronized ? offset : 0,
        ordinal,
        frame.unsynchronized
    });
    return true;
}

void AddId3v1Fallback(ParsedMedia &result, std::string key, const uint8_t *bytes,
    size_t length)
{
    size_t end = 0;
    while (end < length && bytes[end] != 0) {
        ++end;
    }
    AddTag(result, "__ID3V1_" + key, DecodeLatin1(bytes, end));
}

bool ParseId3v1(int fd, uint64_t fileSize, ParsedMedia &result, std::string &error)
{
    if (fileSize < 128) {
        return true;
    }
    std::vector<uint8_t> bytes;
    if (!ReadExact(fd, fileSize, fileSize - 128, 128, bytes, error)) {
        return false;
    }
    if (bytes[0] != 'T' || bytes[1] != 'A' || bytes[2] != 'G') {
        return true;
    }
    AddId3v1Fallback(result, "TIT2", bytes.data() + 3, 30);
    AddId3v1Fallback(result, "TPE1", bytes.data() + 33, 30);
    AddId3v1Fallback(result, "TALB", bytes.data() + 63, 30);
    AddId3v1Fallback(result, "TDRC", bytes.data() + 93, 4);
    if (bytes[125] == 0 && bytes[126] > 0) {
        AddTag(result, "__ID3V1_TRCK", std::to_string(bytes[126]));
    }
    return true;
}

bool ParseId3(int fd, uint64_t fileSize, ParsedMedia &result, std::string &error)
{
    result.format = MediaFormat::MP3;
    if (fileSize < 10) {
        return true;
    }
    std::vector<uint8_t> header;
    if (!ReadExact(fd, fileSize, 0, 10, header, error)) {
        return false;
    }
    if (header[0] != 'I' || header[1] != 'D' || header[2] != '3') {
        return ParseId3v1(fd, fileSize, result, error);
    }
    const uint8_t version = header[3];
    if (version < 2 || version > 4) {
        return true;
    }
    const uint64_t tagSize = SyncSafe32(header.data() + 6);
    if (tagSize == 0 || tagSize > MAX_ID3_TAG_BYTES ||
        !CheckedRange(10, tagSize, fileSize)) {
        error = "Invalid ID3 tag size";
        return false;
    }
    const bool globalUnsynchronization = (header[5] & 0x80) != 0;
    uint64_t frameOffset = 10;
    const uint64_t tagEnd = 10 + tagSize;
    if ((header[5] & 0x40) != 0 && version >= 3) {
        std::vector<uint8_t> extendedHeader;
        if (!ReadExact(fd, fileSize, frameOffset, 4, extendedHeader, error)) {
            return false;
        }
        const uint64_t extendedSize = version == 4 ? SyncSafe32(extendedHeader.data()) :
            static_cast<uint64_t>(Uint32BE(extendedHeader.data())) + 4;
        if (extendedSize >= 4 && CheckedRange(frameOffset, extendedSize, tagEnd)) {
            frameOffset += extendedSize;
        }
    }
    uint32_t frameCount = 0;
    uint32_t artworkOrdinal = 0;
    while (frameOffset < tagEnd && frameCount < MAX_ID3_FRAME_COUNT) {
        Id3Frame frame;
        bool hasFrame = false;
        if (!ReadId3FrameHeader(fd, fileSize, frameOffset, tagEnd, version,
            globalUnsynchronization, frame, hasFrame, error)) {
            return false;
        }
        if (!hasFrame) {
            break;
        }
        if (frame.dataLength <= MAX_ID3_FRAME_BYTES) {
            if ((frame.id == "APIC" || frame.id == "PIC") &&
                artworkOrdinal < MAX_ARTWORK_COUNT) {
                const size_t before = result.artworks.size();
                if (!ParseId3Picture(fd, fileSize, frame, version, artworkOrdinal,
                    result, error)) {
                    return false;
                }
                if (result.artworks.size() > before) {
                    ++artworkOrdinal;
                }
            } else if (!frame.id.empty() && frame.id[0] == 'T' && frame.id != "TXXX") {
                if (!ParseId3TextFrame(fd, fileSize, frame, result, error)) {
                    return false;
                }
            } else if (frame.id == "USLT") {
                if (!ParseId3Lyrics(fd, fileSize, frame, result, error)) {
                    return false;
                }
            }
        }
        frameOffset = frame.dataOffset + frame.dataLength;
        ++frameCount;
    }
    return ParseId3v1(fd, fileSize, result, error);
}

bool ParseFlacStreamInfo(const std::vector<uint8_t> &bytes, ParsedMedia &result)
{
    if (bytes.size() != 34) {
        return true;
    }
    result.sampleRate = (static_cast<uint32_t>(bytes[10]) << 12) |
        (static_cast<uint32_t>(bytes[11]) << 4) | (bytes[12] >> 4);
    result.channelCount = ((bytes[12] >> 1) & 0x07) + 1;
    result.bitsPerSample = ((bytes[12] & 0x01) << 4) | (bytes[13] >> 4);
    result.bitsPerSample += 1;
    const uint64_t totalSamples = (static_cast<uint64_t>(bytes[13] & 0x0F) << 32) |
        (static_cast<uint64_t>(bytes[14]) << 24) |
        (static_cast<uint64_t>(bytes[15]) << 16) |
        (static_cast<uint64_t>(bytes[16]) << 8) | bytes[17];
    if (result.sampleRate > 0 && totalSamples > 0) {
        result.durationMs = static_cast<uint64_t>(
            std::llround(static_cast<double>(totalSamples) * 1000.0 / result.sampleRate));
    }
    return true;
}

void ParseVorbisComments(const std::vector<uint8_t> &bytes, ParsedMedia &result)
{
    if (bytes.size() < 8) {
        return;
    }
    size_t offset = 0;
    const uint32_t vendorLength = Uint32LE(bytes.data());
    offset += 4;
    if (vendorLength > bytes.size() - offset || bytes.size() - offset - vendorLength < 4) {
        return;
    }
    offset += vendorLength;
    const uint32_t commentCount =
        std::min(Uint32LE(bytes.data() + offset), MAX_FLAC_COMMENT_COUNT);
    offset += 4;
    for (uint32_t index = 0; index < commentCount && offset + 4 <= bytes.size(); ++index) {
        const uint32_t length = Uint32LE(bytes.data() + offset);
        offset += 4;
        if (length > bytes.size() - offset) {
            break;
        }
        const std::string comment = DecodeUtf8(bytes.data() + offset, length);
        offset += length;
        const size_t separator = comment.find('=');
        if (separator == std::string::npos || separator == 0) {
            continue;
        }
        AddTag(result, comment.substr(0, separator), comment.substr(separator + 1));
    }
}

bool ParseFlacPicture(int fd, uint64_t fileSize, uint64_t blockOffset,
    uint64_t blockLength, uint32_t ordinal, ParsedMedia &result, std::string &error)
{
    if (blockLength < 32) {
        return true;
    }
    std::vector<uint8_t> prefix;
    if (!ReadExact(fd, fileSize, blockOffset, 8, prefix, error)) {
        return false;
    }
    const uint32_t pictureType = Uint32BE(prefix.data());
    const uint32_t mimeLength = Uint32BE(prefix.data() + 4);
    uint64_t offset = 8;
    if (mimeLength > MAX_MIME_BYTES || mimeLength > blockLength - offset ||
        blockLength - offset - mimeLength < 4) {
        return true;
    }
    std::vector<uint8_t> mime;
    if (!ReadExact(fd, fileSize, blockOffset + offset, mimeLength, mime, error)) {
        return false;
    }
    const std::string mimeType = DecodeUtf8(mime.data(), mime.size());
    offset += mimeLength;
    std::vector<uint8_t> lengthBytes;
    if (!ReadExact(fd, fileSize, blockOffset + offset, 4, lengthBytes, error)) {
        return false;
    }
    const uint32_t descriptionLength = Uint32BE(lengthBytes.data());
    offset += 4;
    if (descriptionLength > MAX_DESCRIPTION_BYTES ||
        descriptionLength > blockLength - offset ||
        blockLength - offset - descriptionLength < 20) {
        return true;
    }
    std::vector<uint8_t> descriptionBytes;
    if (!ReadExact(fd, fileSize, blockOffset + offset, descriptionLength,
        descriptionBytes, error)) {
        return false;
    }
    const std::string description =
        DecodeUtf8(descriptionBytes.data(), descriptionBytes.size());
    offset += descriptionLength;
    std::vector<uint8_t> pictureInfo;
    if (!ReadExact(fd, fileSize, blockOffset + offset, 20, pictureInfo, error)) {
        return false;
    }
    const uint32_t width = Uint32BE(pictureInfo.data());
    const uint32_t height = Uint32BE(pictureInfo.data() + 4);
    const uint32_t depth = Uint32BE(pictureInfo.data() + 8);
    offset += 16;
    const uint32_t dataLength = Uint32BE(pictureInfo.data() + 16);
    offset += 4;
    if (dataLength == 0 || dataLength > MAX_ARTWORK_BYTES ||
        dataLength > blockLength - offset) {
        return true;
    }
    result.artworks.push_back({
        pictureType <= 20 ? static_cast<int32_t>(pictureType) : 0,
        mimeType,
        description,
        width,
        height,
        depth,
        blockOffset + offset,
        dataLength,
        0,
        ordinal,
        false
    });
    return true;
}

bool ParseFlac(int fd, uint64_t fileSize, ParsedMedia &result, std::string &error)
{
    result.format = MediaFormat::FLAC;
    uint64_t offset = 4;
    bool isLast = false;
    uint32_t blockCount = 0;
    uint32_t artworkOrdinal = 0;
    uint64_t totalMetadataBytes = 0;
    while (!isLast) {
        if (blockCount >= MAX_FLAC_BLOCK_COUNT || !CheckedRange(offset, 4, fileSize)) {
            error = blockCount >= MAX_FLAC_BLOCK_COUNT ?
                "Too many FLAC metadata blocks" : "Truncated FLAC metadata";
            return false;
        }
        std::vector<uint8_t> header;
        if (!ReadExact(fd, fileSize, offset, 4, header, error)) {
            return false;
        }
        isLast = (header[0] & 0x80) != 0;
        const uint8_t type = header[0] & 0x7F;
        const uint64_t length = Uint24BE(header.data() + 1);
        offset += 4;
        totalMetadataBytes += length;
        if (length > MAX_FLAC_BLOCK_BYTES || totalMetadataBytes > MAX_FLAC_METADATA_BYTES ||
            !CheckedRange(offset, length, fileSize)) {
            error = "Invalid FLAC metadata block";
            return false;
        }
        if (type == 0 && length >= 34) {
            std::vector<uint8_t> bytes;
            if (!ReadExact(fd, fileSize, offset, 34, bytes, error)) {
                return false;
            }
            ParseFlacStreamInfo(bytes, result);
        } else if (type == 4 && length <= MAX_FLAC_COMMENT_BYTES) {
            std::vector<uint8_t> bytes;
            if (!ReadExact(fd, fileSize, offset, static_cast<size_t>(length), bytes, error)) {
                return false;
            }
            ParseVorbisComments(bytes, result);
        } else if (type == 6 && artworkOrdinal < MAX_ARTWORK_COUNT) {
            const size_t before = result.artworks.size();
            if (!ParseFlacPicture(fd, fileSize, offset, length, artworkOrdinal,
                result, error)) {
                return false;
            }
            if (result.artworks.size() > before) {
                ++artworkOrdinal;
            }
        }
        offset += length;
        ++blockCount;
    }
    return true;
}

} // namespace

bool ParseMediaFile(int fd, uint64_t fileSize, ParsedMedia &result, std::string &error)
{
    if (fd < 0 || fileSize == 0 ||
        fileSize > static_cast<uint64_t>(std::numeric_limits<off_t>::max())) {
        error = "Invalid media file descriptor or size";
        return false;
    }
    std::vector<uint8_t> signature;
    if (!ReadExact(fd, fileSize, 0, static_cast<size_t>(std::min<uint64_t>(4, fileSize)),
        signature, error)) {
        return false;
    }
    if (signature.size() >= 4 && signature[0] == 'f' && signature[1] == 'L' &&
        signature[2] == 'a' && signature[3] == 'C') {
        return ParseFlac(fd, fileSize, result, error);
    }
    if ((signature.size() >= 3 && signature[0] == 'I' && signature[1] == 'D' &&
        signature[2] == '3') ||
        (signature.size() >= 2 && signature[0] == 0xFF &&
        (signature[1] & 0xE0) == 0xE0)) {
        return ParseId3(fd, fileSize, result, error);
    }
    error = "Only MP3 and FLAC files are supported";
    return false;
}

bool ReadArtworkBytes(int fd, uint64_t fileSize, uint64_t byteOffset, uint64_t byteLength,
    uint64_t payloadOffset, bool unsynchronized, std::vector<uint8_t> &result,
    std::string &error)
{
    size_t outputLength = 0;
    if (!ValidateArtworkRead(fd, fileSize, byteOffset, byteLength, payloadOffset,
        outputLength, error)) {
        return false;
    }
    if (!unsynchronized) {
        return ReadExact(fd, fileSize, byteOffset + payloadOffset,
            outputLength, result, error);
    }
    if (!ReadExact(fd, fileSize, byteOffset, static_cast<size_t>(byteLength), result, error)) {
        return false;
    }
    size_t writeIndex = 0;
    for (size_t readIndex = 0; readIndex < result.size(); ++readIndex) {
        result[writeIndex++] = result[readIndex];
        if (result[readIndex] == 0xFF && readIndex + 1 < result.size() &&
            result[readIndex + 1] == 0x00) {
            ++readIndex;
        }
    }
    result.resize(writeIndex);
    if (payloadOffset > result.size()) {
        error = "Invalid artwork payload offset";
        return false;
    }
    result.erase(result.begin(), result.begin() + static_cast<size_t>(payloadOffset));
    return true;
}

bool ValidateArtworkRead(int fd, uint64_t fileSize, uint64_t byteOffset,
    uint64_t byteLength, uint64_t payloadOffset, size_t &outputLength,
    std::string &error)
{
    if (fd < 0 || fileSize > static_cast<uint64_t>(std::numeric_limits<off_t>::max()) ||
        byteLength == 0 || byteLength > MAX_ARTWORK_BYTES ||
        !CheckedRange(byteOffset, byteLength, fileSize) ||
        payloadOffset > byteLength ||
        byteLength - payloadOffset > std::numeric_limits<size_t>::max()) {
        error = "Invalid artwork byte range";
        return false;
    }
    outputLength = static_cast<size_t>(byteLength - payloadOffset);
    return true;
}

bool ReadArtworkBytesDirect(int fd, uint64_t fileSize, uint64_t byteOffset,
    uint64_t byteLength, uint64_t payloadOffset, uint8_t *target,
    size_t targetLength, std::string &error)
{
    size_t outputLength = 0;
    if (!ValidateArtworkRead(fd, fileSize, byteOffset, byteLength, payloadOffset,
        outputLength, error) || outputLength != targetLength) {
        return false;
    }
    return ReadExactInto(fd, fileSize, byteOffset + payloadOffset, target, targetLength, error);
}

bool FlattenArtworkPixels(const uint8_t *source, size_t sourceLength, int32_t width,
    int32_t height, bool premultiplied, uint8_t *target, std::string &error)
{
    if (source == nullptr || target == nullptr || width <= 0 || height <= 0) {
        error = "Invalid artwork pixel buffer";
        return false;
    }
    const size_t widthValue = static_cast<size_t>(width);
    const size_t heightValue = static_cast<size_t>(height);
    if (widthValue > std::numeric_limits<size_t>::max() / heightValue) {
        error = "Artwork pixel dimensions overflow";
        return false;
    }
    const size_t pixelCount = widthValue * heightValue;
    if (pixelCount > std::numeric_limits<size_t>::max() / 4 ||
        sourceLength != pixelCount * 4) {
        error = "Artwork pixel buffer size does not match dimensions";
        return false;
    }
    for (size_t pixel = 0; pixel < pixelCount; ++pixel) {
        const size_t offset = pixel * 4;
        const uint32_t alpha = source[offset + 3];
        const uint32_t white = 255 - alpha;
        const uint32_t blue = source[offset];
        const uint32_t green = source[offset + 1];
        const uint32_t red = source[offset + 2];
        const auto flatten = [alpha, white, premultiplied](uint32_t color) -> uint8_t {
            const uint32_t value = premultiplied ?
                color + white : (color * alpha + 127) / 255 + white;
            return static_cast<uint8_t>(std::min<uint32_t>(255, value));
        };
        target[offset] = flatten(red);
        target[offset + 1] = flatten(green);
        target[offset + 2] = flatten(blue);
        target[offset + 3] = 255;
    }
    return true;
}

} // namespace wplayer::media
