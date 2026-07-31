#include "media_parser.h"

#include <cstring>
#include <exception>
#include <limits>
#include <napi/native_api.h>
#include <new>
#include <string>

namespace wplayer::media {
namespace {

napi_value Undefined(napi_env env)
{
    napi_value value = nullptr;
    napi_get_undefined(env, &value);
    return value;
}

napi_value Throw(napi_env env, const std::string &message)
{
    napi_throw_error(env, nullptr, message.c_str());
    return Undefined(env);
}

napi_value ThrowLiteral(napi_env env, const char *message) noexcept
{
    napi_throw_error(env, nullptr, message);
    napi_value value = nullptr;
    napi_get_undefined(env, &value);
    return value;
}

bool StringValue(napi_env env, const std::string &text, napi_value &value)
{
    return napi_create_string_utf8(env, text.data(), text.size(), &value) == napi_ok;
}

bool NumberValue(napi_env env, double number, napi_value &value)
{
    return napi_create_double(env, number, &value) == napi_ok;
}

bool BoolValue(napi_env env, bool boolean, napi_value &value)
{
    return napi_get_boolean(env, boolean, &value) == napi_ok;
}

bool SetNamed(napi_env env, napi_value object, const char *name, napi_value value)
{
    return napi_set_named_property(env, object, name, value) == napi_ok;
}

bool SetString(napi_env env, napi_value object, const char *name, const std::string &text)
{
    napi_value value = nullptr;
    return StringValue(env, text, value) && SetNamed(env, object, name, value);
}

bool SetNumber(napi_env env, napi_value object, const char *name, double number)
{
    napi_value value = nullptr;
    return NumberValue(env, number, value) && SetNamed(env, object, name, value);
}

bool SetBool(napi_env env, napi_value object, const char *name, bool boolean)
{
    napi_value value = nullptr;
    return BoolValue(env, boolean, value) && SetNamed(env, object, name, value);
}

bool BuildTags(napi_env env, const ParsedMedia &parsed, napi_value &tags)
{
    if (napi_create_array_with_length(env, parsed.tags.size(), &tags) != napi_ok) {
        return false;
    }
    for (size_t index = 0; index < parsed.tags.size(); ++index) {
        napi_value entry = nullptr;
        if (napi_create_object(env, &entry) != napi_ok ||
            !SetString(env, entry, "key", parsed.tags[index].key) ||
            !SetString(env, entry, "value", parsed.tags[index].value) ||
            napi_set_element(env, tags, static_cast<uint32_t>(index), entry) != napi_ok) {
            return false;
        }
    }
    return true;
}

bool BuildArtworks(napi_env env, const ParsedMedia &parsed, napi_value &artworks)
{
    if (napi_create_array_with_length(env, parsed.artworks.size(), &artworks) != napi_ok) {
        return false;
    }
    for (size_t index = 0; index < parsed.artworks.size(); ++index) {
        const Artwork &artwork = parsed.artworks[index];
        napi_value entry = nullptr;
        if (napi_create_object(env, &entry) != napi_ok ||
            !SetNumber(env, entry, "pictureType", artwork.pictureType) ||
            !SetString(env, entry, "mimeType", artwork.mimeType) ||
            !SetString(env, entry, "description", artwork.description) ||
            !SetNumber(env, entry, "width", artwork.width) ||
            !SetNumber(env, entry, "height", artwork.height) ||
            !SetNumber(env, entry, "colorDepth", artwork.colorDepth) ||
            !SetNumber(env, entry, "byteOffset", static_cast<double>(artwork.byteOffset)) ||
            !SetNumber(env, entry, "byteLength", static_cast<double>(artwork.byteLength)) ||
            !SetNumber(env, entry, "payloadOffset", static_cast<double>(artwork.payloadOffset)) ||
            !SetNumber(env, entry, "ordinal", artwork.ordinal) ||
            !SetBool(env, entry, "unsynchronized", artwork.unsynchronized) ||
            napi_set_element(env, artworks, static_cast<uint32_t>(index), entry) != napi_ok) {
            return false;
        }
    }
    return true;
}

napi_value ParseMediaImpl(napi_env env, napi_callback_info info)
{
    size_t argumentCount = 2;
    napi_value arguments[2] = {};
    int32_t fd = -1;
    int64_t fileSize = 0;
    if (napi_get_cb_info(env, info, &argumentCount, arguments, nullptr, nullptr) != napi_ok ||
        argumentCount < 2 ||
        napi_get_value_int32(env, arguments[0], &fd) != napi_ok ||
        napi_get_value_int64(env, arguments[1], &fileSize) != napi_ok ||
        fd < 0 || fileSize <= 0) {
        return Throw(env, "Invalid native media parse arguments");
    }
    ParsedMedia parsed;
    std::string error;
    if (!ParseMediaFile(fd, static_cast<uint64_t>(fileSize), parsed, error)) {
        return Throw(env, error);
    }
    napi_value result = nullptr;
    napi_value tags = nullptr;
    napi_value artworks = nullptr;
    if (napi_create_object(env, &result) != napi_ok ||
        !SetString(env, result, "format",
            parsed.format == MediaFormat::FLAC ? "flac" : "mp3") ||
        !SetNumber(env, result, "durationMs", static_cast<double>(parsed.durationMs)) ||
        !SetNumber(env, result, "sampleRate", parsed.sampleRate) ||
        !SetNumber(env, result, "channelCount", parsed.channelCount) ||
        !SetNumber(env, result, "bitsPerSample", parsed.bitsPerSample) ||
        !BuildTags(env, parsed, tags) || !SetNamed(env, result, "tags", tags) ||
        !BuildArtworks(env, parsed, artworks) || !SetNamed(env, result, "artworks", artworks)) {
        return Throw(env, "Unable to create native media parse result");
    }
    return result;
}

napi_value ParseMedia(napi_env env, napi_callback_info info)
{
    try {
        return ParseMediaImpl(env, info);
    } catch (const std::bad_alloc &) {
        return ThrowLiteral(env, "Native media parse ran out of memory");
    } catch (...) {
        return ThrowLiteral(env, "Native media parse failed");
    }
}

napi_value ReadArtworkImpl(napi_env env, napi_callback_info info)
{
    size_t argumentCount = 6;
    napi_value arguments[6] = {};
    int32_t fd = -1;
    int64_t fileSize = 0;
    int64_t byteOffset = 0;
    int64_t byteLength = 0;
    int64_t payloadOffset = 0;
    bool unsynchronized = false;
    if (napi_get_cb_info(env, info, &argumentCount, arguments, nullptr, nullptr) != napi_ok ||
        argumentCount < 6 ||
        napi_get_value_int32(env, arguments[0], &fd) != napi_ok ||
        napi_get_value_int64(env, arguments[1], &fileSize) != napi_ok ||
        napi_get_value_int64(env, arguments[2], &byteOffset) != napi_ok ||
        napi_get_value_int64(env, arguments[3], &byteLength) != napi_ok ||
        napi_get_value_int64(env, arguments[4], &payloadOffset) != napi_ok ||
        napi_get_value_bool(env, arguments[5], &unsynchronized) != napi_ok ||
        fd < 0 || fileSize <= 0 || byteOffset < 0 || byteLength <= 0 ||
        payloadOffset < 0) {
        return Throw(env, "Invalid native artwork read arguments");
    }
    std::string error;
    if (!unsynchronized) {
        size_t outputLength = 0;
        if (!ValidateArtworkRead(fd, static_cast<uint64_t>(fileSize),
            static_cast<uint64_t>(byteOffset), static_cast<uint64_t>(byteLength),
            static_cast<uint64_t>(payloadOffset), outputLength, error)) {
            return Throw(env, error);
        }
        void *target = nullptr;
        napi_value output = nullptr;
        if (napi_create_arraybuffer(env, outputLength, &target, &output) != napi_ok ||
            (outputLength > 0 && target == nullptr)) {
            return Throw(env, "Unable to allocate native artwork result");
        }
        if (!ReadArtworkBytesDirect(fd, static_cast<uint64_t>(fileSize),
            static_cast<uint64_t>(byteOffset), static_cast<uint64_t>(byteLength),
            static_cast<uint64_t>(payloadOffset), static_cast<uint8_t *>(target),
            outputLength, error)) {
            return Throw(env, error);
        }
        return output;
    }
    std::vector<uint8_t> bytes;
    if (!ReadArtworkBytes(fd, static_cast<uint64_t>(fileSize),
        static_cast<uint64_t>(byteOffset), static_cast<uint64_t>(byteLength),
        static_cast<uint64_t>(payloadOffset), unsynchronized, bytes, error)) {
        return Throw(env, error);
    }
    void *target = nullptr;
    napi_value output = nullptr;
    if (napi_create_arraybuffer(env, bytes.size(), &target, &output) != napi_ok ||
        (bytes.size() > 0 && target == nullptr)) {
        return Throw(env, "Unable to allocate native artwork result");
    }
    if (!bytes.empty()) {
        std::memcpy(target, bytes.data(), bytes.size());
    }
    return output;
}

napi_value ReadArtwork(napi_env env, napi_callback_info info)
{
    try {
        return ReadArtworkImpl(env, info);
    } catch (const std::bad_alloc &) {
        return ThrowLiteral(env, "Native artwork read ran out of memory");
    } catch (...) {
        return ThrowLiteral(env, "Native artwork read failed");
    }
}

napi_value FlattenPixelsImpl(napi_env env, napi_callback_info info)
{
    size_t argumentCount = 4;
    napi_value arguments[4] = {};
    void *source = nullptr;
    size_t sourceLength = 0;
    int32_t width = 0;
    int32_t height = 0;
    bool premultiplied = false;
    if (napi_get_cb_info(env, info, &argumentCount, arguments, nullptr, nullptr) != napi_ok ||
        argumentCount < 4 ||
        napi_get_arraybuffer_info(env, arguments[0], &source, &sourceLength) != napi_ok ||
        napi_get_value_int32(env, arguments[1], &width) != napi_ok ||
        napi_get_value_int32(env, arguments[2], &height) != napi_ok ||
        napi_get_value_bool(env, arguments[3], &premultiplied) != napi_ok ||
        width <= 0 || height <= 0) {
        return Throw(env, "Invalid native artwork flatten arguments");
    }
    const size_t widthValue = static_cast<size_t>(width);
    const size_t heightValue = static_cast<size_t>(height);
    if (widthValue > std::numeric_limits<size_t>::max() / heightValue ||
        widthValue * heightValue > std::numeric_limits<size_t>::max() / 4) {
        return Throw(env, "Native artwork dimensions overflow");
    }
    const size_t targetLength = widthValue * heightValue * 4;
    if (sourceLength != targetLength) {
        return Throw(env, "Artwork pixel buffer size does not match dimensions");
    }
    void *target = nullptr;
    napi_value output = nullptr;
    if (napi_create_arraybuffer(env, targetLength, &target, &output) != napi_ok ||
        target == nullptr) {
        return Throw(env, "Unable to allocate native flattened artwork");
    }
    std::string error;
    if (!FlattenArtworkPixels(static_cast<const uint8_t *>(source), sourceLength,
        width, height, premultiplied, static_cast<uint8_t *>(target), error)) {
        return Throw(env, error);
    }
    return output;
}

napi_value FlattenPixels(napi_env env, napi_callback_info info)
{
    try {
        return FlattenPixelsImpl(env, info);
    } catch (const std::bad_alloc &) {
        return ThrowLiteral(env, "Native artwork flatten ran out of memory");
    } catch (...) {
        return ThrowLiteral(env, "Native artwork flatten failed");
    }
}

napi_value Init(napi_env env, napi_value exports)
{
    const napi_property_descriptor properties[] = {
        { "parseMediaFile", nullptr, ParseMedia, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "readArtworkBytes", nullptr, ReadArtwork, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "flattenArtworkPixels", nullptr, FlattenPixels, nullptr, nullptr, nullptr, napi_default, nullptr }
    };
    if (napi_define_properties(env, exports,
        sizeof(properties) / sizeof(properties[0]), properties) != napi_ok) {
        napi_throw_error(env, nullptr, "Unable to export native media functions");
    }
    return exports;
}

napi_module MEDIA_MODULE = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "wplayermedia",
    .nm_priv = nullptr,
    .reserved = { 0 }
};

} // namespace

extern "C" __attribute__((constructor)) void RegisterWPlayerMediaModule()
{
    napi_module_register(&MEDIA_MODULE);
}

} // namespace wplayer::media
