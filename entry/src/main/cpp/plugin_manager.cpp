#include "plugin_manager.h"

#include "apple_music_renderer.h"

#include <hilog/log.h>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>

namespace wplayer {
namespace {

constexpr uint32_t APP_LOG_DOMAIN = 0xD004201;
constexpr char APP_LOG_TAG[] = "WPlayerBackground";

struct ComponentState {
    std::shared_ptr<AppleMusicRenderer> renderer;
    OH_NativeXComponent *component = nullptr;
    bool paused = false;
};

std::mutex g_componentMutex;
std::unordered_map<std::string, ComponentState> g_components;
OH_NativeXComponent_Callback g_surfaceCallbacks {};

bool ComponentId(OH_NativeXComponent *component, std::string &id)
{
    if (component == nullptr) {
        return false;
    }
    char idBuffer[OH_XCOMPONENT_ID_LEN_MAX + 1] = {};
    uint64_t idSize = sizeof(idBuffer);
    if (OH_NativeXComponent_GetXComponentId(component, idBuffer, &idSize) !=
        OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        return false;
    }
    id.assign(idBuffer);
    return true;
}

std::shared_ptr<AppleMusicRenderer> RendererFor(OH_NativeXComponent *component)
{
    std::string id;
    if (!ComponentId(component, id)) {
        return nullptr;
    }
    std::lock_guard<std::mutex> lock(g_componentMutex);
    const auto iterator = g_components.find(id);
    if (iterator == g_components.end() || iterator->second.component != component) {
        return nullptr;
    }
    return iterator->second.renderer;
}

bool NativeComponentFromCallback(napi_env env, napi_callback_info info,
    size_t *argumentCount, napi_value *arguments, OH_NativeXComponent **component)
{
    napi_value thisArgument = nullptr;
    if (napi_get_cb_info(env, info, argumentCount, arguments, &thisArgument, nullptr) != napi_ok) {
        return false;
    }
    napi_value componentObject = nullptr;
    if (napi_get_named_property(env, thisArgument, OH_NATIVE_XCOMPONENT_OBJ,
        &componentObject) != napi_ok) {
        return false;
    }
    return napi_unwrap(env, componentObject, reinterpret_cast<void **>(component)) == napi_ok &&
        *component != nullptr;
}

void ConfigureFrameCallback(OH_NativeXComponent *component, bool paused);

void OnFrame(OH_NativeXComponent *component, uint64_t timestamp, uint64_t)
{
    const auto renderer = RendererFor(component);
    if (renderer != nullptr) {
        renderer->Render(static_cast<double>(timestamp) / 1'000'000'000.0);
    }
}

void ConfigureFrameCallback(OH_NativeXComponent *component, bool paused)
{
    if (component == nullptr) {
        return;
    }
    OH_NativeXComponent_UnregisterOnFrameCallback(component);
    if (paused) {
        return;
    }
    OH_NativeXComponent_RegisterOnFrameCallback(component, OnFrame);
}

void OnSurfaceCreated(OH_NativeXComponent *component, void *window)
{
    const auto renderer = RendererFor(component);
    if (renderer == nullptr || window == nullptr) {
        return;
    }
    uint64_t width = 0;
    uint64_t height = 0;
    if (OH_NativeXComponent_GetXComponentSize(component, window, &width, &height) !=
        OH_NATIVEXCOMPONENT_RESULT_SUCCESS ||
        !renderer->Initialize(static_cast<OHNativeWindow *>(window), width, height)) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, APP_LOG_DOMAIN, APP_LOG_TAG,
            "Unable to initialize v3 surface");
        return;
    }
    bool paused = false;
    {
        std::string id;
        if (ComponentId(component, id)) {
            std::lock_guard<std::mutex> lock(g_componentMutex);
            const auto iterator = g_components.find(id);
            if (iterator != g_components.end()) {
                paused = iterator->second.paused;
            }
        }
    }
    ConfigureFrameCallback(component, paused);
    if (!paused) {
        renderer->Render(0.0);
    }
}

void OnSurfaceChanged(OH_NativeXComponent *component, void *window)
{
    const auto renderer = RendererFor(component);
    if (renderer == nullptr || window == nullptr) {
        return;
    }
    uint64_t width = 0;
    uint64_t height = 0;
    if (OH_NativeXComponent_GetXComponentSize(component, window, &width, &height) ==
        OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        renderer->Resize(width, height);
    }
}

void OnSurfaceDestroyed(OH_NativeXComponent *component, void *)
{
    ConfigureFrameCallback(component, true);
    const auto renderer = RendererFor(component);
    if (renderer != nullptr) {
        renderer->Release();
    }
}

} // namespace

napi_value PluginManager::SetArtwork(napi_env env, napi_callback_info info)
{
    size_t argumentCount = 4;
    napi_value arguments[4] = {};
    OH_NativeXComponent *component = nullptr;
    if (!NativeComponentFromCallback(env, info, &argumentCount, arguments, &component) ||
        argumentCount < 3) {
        return nullptr;
    }
    void *bytes = nullptr;
    size_t byteCount = 0;
    int32_t width = 0;
    int32_t height = 0;
    bool swapRedBlue = true;
    if (napi_get_arraybuffer_info(env, arguments[0], &bytes, &byteCount) != napi_ok ||
        napi_get_value_int32(env, arguments[1], &width) != napi_ok ||
        napi_get_value_int32(env, arguments[2], &height) != napi_ok) {
        return nullptr;
    }
    if (argumentCount >= 4) {
        napi_get_value_bool(env, arguments[3], &swapRedBlue);
    }
    const auto renderer = RendererFor(component);
    if (renderer != nullptr) {
        renderer->SetArtwork(static_cast<uint8_t *>(bytes), byteCount, width, height,
            swapRedBlue);
    }
    return nullptr;
}

napi_value PluginManager::SetPaused(napi_env env, napi_callback_info info)
{
    size_t argumentCount = 1;
    napi_value arguments[1] = {};
    OH_NativeXComponent *component = nullptr;
    bool paused = false;
    if (!NativeComponentFromCallback(env, info, &argumentCount, arguments, &component) ||
        argumentCount < 1 || napi_get_value_bool(env, arguments[0], &paused) != napi_ok) {
        return nullptr;
    }
    const auto renderer = RendererFor(component);
    if (renderer != nullptr) {
        renderer->SetPaused(paused);
    }
    std::string id;
    if (ComponentId(component, id)) {
        std::lock_guard<std::mutex> lock(g_componentMutex);
        const auto iterator = g_components.find(id);
        if (iterator != g_components.end() && iterator->second.component == component) {
            iterator->second.paused = paused;
        }
    }
    ConfigureFrameCallback(component, paused);
    return nullptr;
}

napi_value PluginManager::SetSpeed(napi_env env, napi_callback_info info)
{
    size_t argumentCount = 1;
    napi_value arguments[1] = {};
    OH_NativeXComponent *component = nullptr;
    double speed = 1.0;
    if (!NativeComponentFromCallback(env, info, &argumentCount, arguments, &component) ||
        argumentCount < 1 || napi_get_value_double(env, arguments[0], &speed) != napi_ok) {
        return nullptr;
    }
    const auto renderer = RendererFor(component);
    if (renderer != nullptr) {
        renderer->SetSpeed(static_cast<float>(speed));
    }
    return nullptr;
}

napi_value PluginManager::SetRenderScale(napi_env env, napi_callback_info info)
{
    size_t argumentCount = 1;
    napi_value arguments[1] = {};
    OH_NativeXComponent *component = nullptr;
    double scale = 1.0;
    if (!NativeComponentFromCallback(env, info, &argumentCount, arguments, &component) ||
        argumentCount < 1 || napi_get_value_double(env, arguments[0], &scale) != napi_ok) {
        return nullptr;
    }
    const auto renderer = RendererFor(component);
    if (renderer != nullptr) {
        renderer->SetRenderScale(static_cast<float>(scale));
    }
    return nullptr;
}

napi_value PluginManager::SetFrameRates(napi_env env, napi_callback_info info)
{
    size_t argumentCount = 4;
    napi_value arguments[4] = {};
    OH_NativeXComponent *component = nullptr;
    double backgroundFps = 15.0;
    double transitionFps = 60.0;
    double transitionDuration = 0.8;
    double initialRevealDurationRatio = 0.5;
    if (!NativeComponentFromCallback(env, info, &argumentCount, arguments, &component) ||
        argumentCount < 4 ||
        napi_get_value_double(env, arguments[0], &backgroundFps) != napi_ok ||
        napi_get_value_double(env, arguments[1], &transitionFps) != napi_ok ||
        napi_get_value_double(env, arguments[2], &transitionDuration) != napi_ok ||
        napi_get_value_double(env, arguments[3], &initialRevealDurationRatio) != napi_ok) {
        return nullptr;
    }
    const auto renderer = RendererFor(component);
    if (renderer != nullptr) {
        renderer->SetFrameRates(
            static_cast<float>(backgroundFps),
            static_cast<float>(transitionFps),
            static_cast<float>(transitionDuration),
            static_cast<float>(initialRevealDurationRatio));
    }
    return nullptr;
}

napi_value PluginManager::SetWorkTextureSize(napi_env env, napi_callback_info info)
{
    size_t argumentCount = 1;
    napi_value arguments[1] = {};
    OH_NativeXComponent *component = nullptr;
    int32_t size = 256;
    if (!NativeComponentFromCallback(env, info, &argumentCount, arguments, &component) ||
        argumentCount < 1 || napi_get_value_int32(env, arguments[0], &size) != napi_ok) {
        return nullptr;
    }
    const auto renderer = RendererFor(component);
    if (renderer != nullptr) {
        renderer->SetWorkTextureSize(size);
    }
    return nullptr;
}

napi_value PluginManager::SetBlurRadius(napi_env env, napi_callback_info info)
{
    size_t argumentCount = 1;
    napi_value arguments[1] = {};
    OH_NativeXComponent *component = nullptr;
    double actualPixelRadius = 86.0;
    if (!NativeComponentFromCallback(env, info, &argumentCount, arguments, &component) ||
        argumentCount < 1 ||
        napi_get_value_double(env, arguments[0], &actualPixelRadius) != napi_ok) {
        return nullptr;
    }
    const auto renderer = RendererFor(component);
    if (renderer != nullptr) {
        renderer->SetBlurRadius(static_cast<float>(actualPixelRadius));
    }
    return nullptr;
}

napi_value PluginManager::SetOverscan(napi_env env, napi_callback_info info)
{
    size_t argumentCount = 1;
    napi_value arguments[1] = {};
    OH_NativeXComponent *component = nullptr;
    double overscan = 1.16;
    if (!NativeComponentFromCallback(env, info, &argumentCount, arguments, &component) ||
        argumentCount < 1 || napi_get_value_double(env, arguments[0], &overscan) != napi_ok) {
        return nullptr;
    }
    const auto renderer = RendererFor(component);
    if (renderer != nullptr) {
        renderer->SetOverscan(static_cast<float>(overscan));
    }
    return nullptr;
}

void PluginManager::Export(napi_env env, napi_value exports)
{
    napi_value componentObject = nullptr;
    if (napi_get_named_property(env, exports, OH_NATIVE_XCOMPONENT_OBJ,
        &componentObject) != napi_ok) {
        return;
    }
    OH_NativeXComponent *component = nullptr;
    if (napi_unwrap(env, componentObject, reinterpret_cast<void **>(&component)) != napi_ok ||
        component == nullptr) {
        return;
    }
    std::string id;
    if (!ComponentId(component, id)) {
        return;
    }
    {
        std::lock_guard<std::mutex> lock(g_componentMutex);
        auto &state = g_components[id];
        if (state.renderer == nullptr || state.component != component) {
            state.renderer = std::make_shared<AppleMusicRenderer>();
            state.paused = false;
        }
        state.component = component;
    }

    g_surfaceCallbacks.OnSurfaceCreated = OnSurfaceCreated;
    g_surfaceCallbacks.OnSurfaceChanged = OnSurfaceChanged;
    g_surfaceCallbacks.OnSurfaceDestroyed = OnSurfaceDestroyed;
    g_surfaceCallbacks.DispatchTouchEvent = nullptr;
    OH_NativeXComponent_RegisterCallback(component, &g_surfaceCallbacks);

    const napi_property_descriptor properties[] = {
        { "setArtwork", nullptr, SetArtwork, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setPaused", nullptr, SetPaused, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setSpeed", nullptr, SetSpeed, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setRenderScale", nullptr, SetRenderScale, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setFrameRates", nullptr, SetFrameRates, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setWorkTextureSize", nullptr, SetWorkTextureSize, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setBlurRadius", nullptr, SetBlurRadius, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setOverscan", nullptr, SetOverscan, nullptr, nullptr, nullptr, napi_default, nullptr }
    };
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
}

} // namespace wplayer
