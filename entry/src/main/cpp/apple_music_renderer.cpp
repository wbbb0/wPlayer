#include "apple_music_renderer.h"
#include "dynamic_background_render_policy.h"

#include <algorithm>
#include <cmath>
#include <hilog/log.h>
#include <native_window/external_window.h>

namespace wplayer {
namespace {

constexpr uint32_t APP_LOG_DOMAIN = 0xD004201;
constexpr char APP_LOG_TAG[] = "WPlayerBackground";
constexpr int32_t BLUR_PASSES = 9;
constexpr int32_t MAX_ARTWORK_DIMENSION = 4096;
constexpr int32_t MAX_RENDER_TARGET_DIMENSION = 4096;
constexpr double GEOMETRY_RETRY_INTERVAL_SECONDS = 0.5;

bool ScaledBufferDimension(uint64_t logicalDimension, float scale, int32_t &bufferDimension)
{
    if (!DynamicBackgroundRenderPolicy::IsLogicalDimensionSupported(logicalDimension) ||
        !std::isfinite(scale) || scale <= 0.0f) {
        return false;
    }
    const double scaledDimension =
        static_cast<double>(logicalDimension) * static_cast<double>(scale);
    if (!std::isfinite(scaledDimension) ||
        scaledDimension > static_cast<double>(MAX_RENDER_TARGET_DIMENSION)) {
        return false;
    }
    bufferDimension = std::max(2, static_cast<int32_t>(std::lround(scaledDimension)));
    return true;
}

std::vector<uint8_t> CenterCropToWorkTexture(const std::vector<uint8_t> &source,
    int32_t sourceWidth, int32_t sourceHeight, int32_t targetSize)
{
    if (sourceWidth == targetSize && sourceHeight == targetSize) {
        return source;
    }
    std::vector<uint8_t> result(
        static_cast<size_t>(targetSize) * targetSize * 4);
    const float side = static_cast<float>(std::min(sourceWidth, sourceHeight));
    const float offsetX = (static_cast<float>(sourceWidth) - side) * 0.5f;
    const float offsetY = (static_cast<float>(sourceHeight) - side) * 0.5f;
    const float scale = side / static_cast<float>(targetSize);
    for (int32_t targetY = 0; targetY < targetSize; ++targetY) {
        const float sourceY = std::clamp(
            offsetY + (static_cast<float>(targetY) + 0.5f) * scale - 0.5f,
            0.0f, static_cast<float>(sourceHeight - 1));
        const int32_t y0 = static_cast<int32_t>(std::floor(sourceY));
        const int32_t y1 = std::min(y0 + 1, sourceHeight - 1);
        const float fy = sourceY - static_cast<float>(y0);
        for (int32_t targetX = 0; targetX < targetSize; ++targetX) {
            const float sourceX = std::clamp(
                offsetX + (static_cast<float>(targetX) + 0.5f) * scale - 0.5f,
                0.0f, static_cast<float>(sourceWidth - 1));
            const int32_t x0 = static_cast<int32_t>(std::floor(sourceX));
            const int32_t x1 = std::min(x0 + 1, sourceWidth - 1);
            const float fx = sourceX - static_cast<float>(x0);
            const size_t destinationOffset =
                (static_cast<size_t>(targetY) * targetSize + targetX) * 4;
            const size_t offsets[4] = {
                (static_cast<size_t>(y0) * sourceWidth + x0) * 4,
                (static_cast<size_t>(y0) * sourceWidth + x1) * 4,
                (static_cast<size_t>(y1) * sourceWidth + x0) * 4,
                (static_cast<size_t>(y1) * sourceWidth + x1) * 4
            };
            for (int32_t channel = 0; channel < 4; ++channel) {
                const float top = static_cast<float>(source[offsets[0] + channel]) *
                    (1.0f - fx) + static_cast<float>(source[offsets[1] + channel]) * fx;
                const float bottom = static_cast<float>(source[offsets[2] + channel]) *
                    (1.0f - fx) + static_cast<float>(source[offsets[3] + channel]) * fx;
                result[destinationOffset + channel] = static_cast<uint8_t>(
                    std::lround(top * (1.0f - fy) + bottom * fy));
            }
        }
    }
    return result;
}

const char *VERTEX_SHADER = R"(#version 300 es
precision highp float;
out vec2 v_uv;
const vec2 POSITIONS[6] = vec2[](
    vec2(-1.0, -1.0), vec2(1.0, -1.0), vec2(-1.0, 1.0),
    vec2(-1.0, 1.0), vec2(1.0, -1.0), vec2(1.0, 1.0)
);
void main() {
    vec2 position = POSITIONS[gl_VertexID];
    v_uv = position * 0.5 + 0.5;
    gl_Position = vec4(position, 0.0, 1.0);
}
)";

const char *SCENE_FRAGMENT_SHADER = R"(#version 300 es
precision highp float;
in vec2 v_uv;
out vec4 fragmentColor;

uniform sampler2D u_texture;
uniform sampler2D u_previousTexture;
uniform vec2 u_resolution;
uniform vec2 u_textureSize;
uniform float u_time;
uniform float u_swapRedBlue;
uniform float u_previousSwapRedBlue;
uniform float u_artworkTransition;

mat2 rotate2d(float angle) {
    float sine = sin(angle);
    float cosine = cos(angle);
    return mat2(cosine, -sine, sine, cosine);
}

vec2 mirrorRepeat(vec2 uv) {
    return abs(fract(uv * 0.5) * 2.0 - 1.0);
}

vec3 sampleArtwork(vec2 uv) {
    vec2 mirrored = mirrorRepeat(uv);
    float textureAspect = u_textureSize.x / max(u_textureSize.y, 1.0);
    vec2 cropped = mirrored;
    if (textureAspect > 1.0) {
        cropped.x = 0.5 + (mirrored.x - 0.5) / textureAspect;
    } else {
        cropped.y = 0.5 + (mirrored.y - 0.5) * textureAspect;
    }
    cropped.y = 1.0 - cropped.y;
    if (u_artworkTransition <= 0.001) {
        vec3 previousColor = texture(u_previousTexture, cropped).rgb;
        return mix(previousColor, previousColor.bgr, u_previousSwapRedBlue);
    }
    vec3 currentColor = texture(u_texture, cropped).rgb;
    currentColor = mix(currentColor, currentColor.bgr, u_swapRedBlue);
    if (u_artworkTransition >= 0.999) {
        return currentColor;
    }
    vec3 previousColor = texture(u_previousTexture, cropped).rgb;
    previousColor = mix(previousColor, previousColor.bgr, u_previousSwapRedBlue);
    float transition = u_artworkTransition * u_artworkTransition *
        (3.0 - 2.0 * u_artworkTransition);
    return mix(previousColor, currentColor, transition);
}

vec2 twistCoord(vec2 point, float layerFactor) {
    const float twist = -3.25;
    const float twistRadius = 0.90;
    float distanceFromCenter = length(point);
    float ratio = clamp((twistRadius - distanceFromCenter) / twistRadius, 0.0, 1.0);
    float angle = twist * ratio * ratio * layerFactor;
    return rotate2d(angle) * point;
}

vec4 layerSample(vec2 point, float scale, float opacity, float rotationSpeed,
    float orbit, float phase, float layerFactor) {
    float angle = u_time * rotationSpeed + phase;
    vec2 center = vec2(cos(angle * 0.73 + phase), sin(angle * 0.91 + phase)) * orbit;
    vec2 transformed = rotate2d(-angle) * ((point - center) / max(scale, 0.05));
    transformed = twistCoord(transformed, layerFactor);
    vec3 color = sampleArtwork(transformed + 0.5);
    float edge = max(abs(transformed.x), abs(transformed.y));
    float mask = 1.0 - smoothstep(0.42, 0.64, edge);
    return vec4(color, opacity * mask);
}

vec3 alphaOver(vec3 base, vec4 top) {
    const float mixStrength = 0.84;
    return mix(base, top.rgb, clamp(top.a * mixStrength, 0.0, 1.0));
}

void main() {
    vec2 point = v_uv - 0.5;
    float aspect = u_resolution.x / max(u_resolution.y, 1.0);
    point.x *= aspect;
    float cover = max(aspect, 1.0);

    vec4 layer1 = layerSample(point, 1.25 * cover, 1.00, 0.045, 0.00, 0.00, 0.72);
    vec4 layer2 = layerSample(point, 0.80 * cover, 0.55, -0.120, 0.02, 1.57, 0.86);
    vec4 layer3 = layerSample(point, 0.50 * cover, 0.50, -0.090, 0.25, 3.10, 1.00);
    vec4 layer4 = layerSample(point, 0.25 * cover, 0.44, 0.060, 0.31, 4.65, 1.12);

    vec3 color = layer1.rgb;
    color = alphaOver(color, layer2);
    color = alphaOver(color, layer3);
    color = alphaOver(color, layer4);
    fragmentColor = vec4(color, 1.0);
}
)";

const char *BLUR_FRAGMENT_SHADER = R"(#version 300 es
precision highp float;
in vec2 v_uv;
out vec4 fragmentColor;
uniform sampler2D u_input;
uniform vec2 u_texel;
uniform float u_offset;
void main() {
    vec2 delta = u_texel * u_offset;
    vec3 color = vec3(0.0);
    color += texture(u_input, v_uv + vec2(delta.x, delta.y)).rgb;
    color += texture(u_input, v_uv + vec2(-delta.x, delta.y)).rgb;
    color += texture(u_input, v_uv + vec2(delta.x, -delta.y)).rgb;
    color += texture(u_input, v_uv + vec2(-delta.x, -delta.y)).rgb;
    fragmentColor = vec4(color * 0.25, 1.0);
}
)";

const char *FINAL_FRAGMENT_SHADER = R"(#version 300 es
precision highp float;
in vec2 v_uv;
out vec4 fragmentColor;
uniform sampler2D u_input;
uniform sampler2D u_previousInput;
uniform float u_artworkTransition;
uniform vec2 u_resolution;
uniform float u_overscan;
uniform float u_reveal;
void main() {
    vec2 sampleUv = 0.5 + (v_uv - 0.5) / max(u_overscan, 0.01);
    vec3 currentColor = texture(u_input, sampleUv).rgb;
    vec3 previousColor = texture(u_previousInput, sampleUv).rgb;
    float transition = clamp(u_artworkTransition, 0.0, 1.0);
    transition = transition * transition * (3.0 - 2.0 * transition);
    vec3 color = mix(previousColor, currentColor, transition);
    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = mix(vec3(luma), color, 2.75);
    color = (color - 0.5) * 1.12 + 0.5;
    color *= 0.90;
    color = max(color, 0.0);

    float aspect = u_resolution.x / max(u_resolution.y, 1.0);
    float vignette = smoothstep(0.20, 0.88,
        length((sampleUv - 0.5) * vec2(aspect, 1.0)));
    color *= 1.0 - vignette * 0.34;
    color = color / (1.0 + color * 0.12);

    // Port the two black gradients from the reference stage::after overlay.
    float linearShade = mix(0.26, 0.08, v_uv.y);
    vec2 pixelPoint = (v_uv - vec2(0.5, 0.8)) * u_resolution;
    float radialRadius = length(vec2(0.5, 0.8) * u_resolution);
    float radialProgress = length(pixelPoint) / max(radialRadius, 1.0);
    float radialShade = mix(0.0, 0.18,
        clamp((radialProgress - 0.38) / 0.40, 0.0, 1.0));
    radialShade = mix(radialShade, 0.36,
        clamp((radialProgress - 0.78) / 0.22, 0.0, 1.0));
    color *= (1.0 - radialShade) * (1.0 - linearShade);
    float reveal = clamp(u_reveal, 0.0, 1.0);
    fragmentColor = vec4(color * reveal, reveal);
}
)";

} // namespace

AppleMusicRenderer::~AppleMusicRenderer()
{
    Release();
}

bool AppleMusicRenderer::Initialize(OHNativeWindow *window, uint64_t width, uint64_t height)
{
    std::lock_guard<std::recursive_mutex> renderLock(renderMutex_);
    float scale = 1.0f;
    {
        std::lock_guard<std::mutex> lock(stateMutex_);
        scale = renderScale_;
    }
    int32_t nextBufferWidth = 0;
    int32_t nextBufferHeight = 0;
    if (window == nullptr ||
        !ScaledBufferDimension(width, scale, nextBufferWidth) ||
        !ScaledBufferDimension(height, scale, nextBufferHeight)) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, APP_LOG_DOMAIN, APP_LOG_TAG,
            "Rejected unsupported initial surface dimensions");
        return false;
    }
    Release();
    window_ = window;
    {
        std::lock_guard<std::mutex> lock(stateMutex_);
        logicalWidth_ = width;
        logicalHeight_ = height;
        geometryDirty_ = true;
    }
    bufferWidth_ = nextBufferWidth;
    bufferHeight_ = nextBufferHeight;
    const int32_t geometryResult = OH_NativeWindow_NativeWindowHandleOpt(
        window_, SET_BUFFER_GEOMETRY, bufferWidth_, bufferHeight_);
    if (geometryResult != 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, APP_LOG_DOMAIN, APP_LOG_TAG,
            "SET_BUFFER_GEOMETRY failed during initialization: %{public}d", geometryResult);
        return false;
    }

    eglDisplay_ = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (eglDisplay_ == EGL_NO_DISPLAY || !eglInitialize(eglDisplay_, nullptr, nullptr)) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, APP_LOG_DOMAIN, APP_LOG_TAG, "Unable to initialize EGL display");
        return false;
    }
    const EGLint configAttributes[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_NONE
    };
    EGLint configCount = 0;
    if (!eglChooseConfig(eglDisplay_, configAttributes, &eglConfig_, 1, &configCount) ||
        configCount < 1) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, APP_LOG_DOMAIN, APP_LOG_TAG, "Unable to choose EGL config");
        return false;
    }
    eglSurface_ = eglCreateWindowSurface(
        eglDisplay_, eglConfig_, reinterpret_cast<EGLNativeWindowType>(window_), nullptr);
    if (eglSurface_ == EGL_NO_SURFACE) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, APP_LOG_DOMAIN, APP_LOG_TAG, "Unable to create EGL surface");
        return false;
    }
    const EGLint contextAttributes[] = { EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE };
    eglContext_ = eglCreateContext(
        eglDisplay_, eglConfig_, EGL_NO_CONTEXT, contextAttributes);
    if (eglContext_ == EGL_NO_CONTEXT ||
        !eglMakeCurrent(eglDisplay_, eglSurface_, eglSurface_, eglContext_)) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, APP_LOG_DOMAIN, APP_LOG_TAG, "Unable to create EGL context");
        return false;
    }
    eglSwapInterval(eglDisplay_, 1);
    if (!CreatePrograms() || !CreateSourceTextures() || !CreateRenderTargets()) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, APP_LOG_DOMAIN, APP_LOG_TAG, "Unable to create renderer resources");
        return false;
    }
    {
        std::lock_guard<std::mutex> lock(stateMutex_);
        const bool configurationStillCurrent =
            logicalWidth_ == width && logicalHeight_ == height &&
            std::abs(renderScale_ - scale) <= 0.001f;
        if (DynamicBackgroundRenderPolicy::CanCommitGeometry(
            true, true, configurationStillCurrent)) {
            geometryDirty_ = false;
        }
    }
    RestoreCachedArtwork();
    sceneDirty_ = true;
    resetClock_ = true;
    lastPresentedTimestampSeconds_ = 0.0;
    return true;
}

void AppleMusicRenderer::Resize(uint64_t width, uint64_t height)
{
    std::lock_guard<std::mutex> lock(stateMutex_);
    int32_t ignoredWidth = 0;
    int32_t ignoredHeight = 0;
    if (!ScaledBufferDimension(width, renderScale_, ignoredWidth) ||
        !ScaledBufferDimension(height, renderScale_, ignoredHeight)) {
        return;
    }
    logicalWidth_ = width;
    logicalHeight_ = height;
    geometryDirty_ = true;
}

void AppleMusicRenderer::SetArtwork(const uint8_t *bytes, size_t byteCount, int32_t width,
    int32_t height, bool swapRedBlue)
{
    if (bytes == nullptr || width <= 0 || height <= 0 ||
        width > MAX_ARTWORK_DIMENSION || height > MAX_ARTWORK_DIMENSION) {
        return;
    }
    const size_t requiredByteCount =
        static_cast<size_t>(width) * static_cast<size_t>(height) * 4;
    if (byteCount < requiredByteCount) {
        return;
    }
    std::lock_guard<std::mutex> lock(stateMutex_);
    pendingArtwork_.assign(bytes, bytes + requiredByteCount);
    pendingArtworkWidth_ = width;
    pendingArtworkHeight_ = height;
    pendingSwapRedBlue_ = swapRedBlue;
    artworkPending_ = true;
}

void AppleMusicRenderer::SetPaused(bool paused)
{
    std::lock_guard<std::mutex> lock(stateMutex_);
    paused_ = paused;
    resetClock_ = true;
}

void AppleMusicRenderer::SetSpeed(float speed)
{
    if (!std::isfinite(speed)) {
        return;
    }
    std::lock_guard<std::mutex> lock(stateMutex_);
    speed_ = std::clamp(speed, 0.0f, 10.0f);
}

void AppleMusicRenderer::SetRenderScale(float scale)
{
    if (!std::isfinite(scale)) {
        return;
    }
    std::lock_guard<std::mutex> lock(stateMutex_);
    const float clamped = std::clamp(scale, 0.05f, 1.0f);
    int32_t ignoredWidth = 0;
    int32_t ignoredHeight = 0;
    if ((logicalWidth_ > 0 &&
        !ScaledBufferDimension(logicalWidth_, clamped, ignoredWidth)) ||
        (logicalHeight_ > 0 &&
        !ScaledBufferDimension(logicalHeight_, clamped, ignoredHeight))) {
        return;
    }
    if (std::abs(renderScale_ - clamped) > 0.001f) {
        renderScale_ = clamped;
        geometryDirty_ = true;
    }
}

void AppleMusicRenderer::SetFrameRates(float backgroundFps, float transitionFps,
    float transitionDurationSeconds, float initialRevealDurationRatio)
{
    if (!std::isfinite(backgroundFps) || !std::isfinite(transitionFps) ||
        !std::isfinite(transitionDurationSeconds) ||
        !std::isfinite(initialRevealDurationRatio)) {
        return;
    }
    std::lock_guard<std::mutex> lock(stateMutex_);
    backgroundFrameIntervalSeconds_ =
        1.0 / static_cast<double>(std::clamp(backgroundFps, 1.0f, 120.0f));
    transitionFrameIntervalSeconds_ =
        1.0 / static_cast<double>(std::clamp(transitionFps, 1.0f, 120.0f));
    artworkTransitionDurationSeconds_ =
        static_cast<double>(std::clamp(transitionDurationSeconds, 0.1f, 5.0f));
    initialRevealDurationRatio_ =
        static_cast<double>(std::clamp(initialRevealDurationRatio, 0.05f, 2.0f));
}

void AppleMusicRenderer::SetWorkTextureSize(int32_t size)
{
    std::lock_guard<std::mutex> lock(stateMutex_);
    workTextureSize_ = std::clamp(size, 64, 2048);
}

void AppleMusicRenderer::SetBlurRadius(float actualPixelRadius)
{
    if (!std::isfinite(actualPixelRadius)) {
        return;
    }
    std::lock_guard<std::mutex> lock(stateMutex_);
    blurRadiusActualPixels_ = std::clamp(actualPixelRadius, 0.0f, 512.0f);
}

void AppleMusicRenderer::SetOverscan(float overscan)
{
    if (!std::isfinite(overscan)) {
        return;
    }
    std::lock_guard<std::mutex> lock(stateMutex_);
    overscan_ = std::clamp(overscan, 1.0f, 2.0f);
}

bool AppleMusicRenderer::ApplyPendingConfiguration()
{
    uint64_t logicalWidth = 0;
    uint64_t logicalHeight = 0;
    float scale = 1.0f;
    bool dirty = false;
    {
        std::lock_guard<std::mutex> lock(stateMutex_);
        dirty = geometryDirty_;
        logicalWidth = logicalWidth_;
        logicalHeight = logicalHeight_;
        scale = renderScale_;
    }
    if (!dirty) {
        return true;
    }
    if (window_ == nullptr || logicalWidth == 0 || logicalHeight == 0) {
        return false;
    }
    int32_t nextBufferWidth = 0;
    int32_t nextBufferHeight = 0;
    if (!ScaledBufferDimension(logicalWidth, scale, nextBufferWidth) ||
        !ScaledBufferDimension(logicalHeight, scale, nextBufferHeight)) {
        return false;
    }
    const int32_t result = OH_NativeWindow_NativeWindowHandleOpt(
        window_, SET_BUFFER_GEOMETRY, nextBufferWidth, nextBufferHeight);
    if (result != 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, APP_LOG_DOMAIN, APP_LOG_TAG,
            "SET_BUFFER_GEOMETRY failed: %{public}d", result);
        return false;
    }
    if (eglContext_ == EGL_NO_CONTEXT ||
        !eglMakeCurrent(eglDisplay_, eglSurface_, eglSurface_, eglContext_)) {
        return false;
    }
    const int32_t previousBufferWidth = bufferWidth_;
    const int32_t previousBufferHeight = bufferHeight_;
    bufferWidth_ = nextBufferWidth;
    bufferHeight_ = nextBufferHeight;
    if (!CreateRenderTargets()) {
        bufferWidth_ = previousBufferWidth;
        bufferHeight_ = previousBufferHeight;
        OH_LOG_Print(LOG_APP, LOG_ERROR, APP_LOG_DOMAIN, APP_LOG_TAG,
            "Unable to recreate render targets for resized surface");
        return false;
    }
    {
        std::lock_guard<std::mutex> lock(stateMutex_);
        const bool configurationStillCurrent =
            logicalWidth_ == logicalWidth && logicalHeight_ == logicalHeight &&
            std::abs(renderScale_ - scale) <= 0.001f;
        if (DynamicBackgroundRenderPolicy::CanCommitGeometry(
            true, true, configurationStillCurrent)) {
            geometryDirty_ = false;
        }
    }
    lastBlurredTexture_ = 0;
    hasRenderedFrame_ = false;
    previousFrameValid_ = false;
    sceneDirty_ = true;
    artworkTransitionProgress_ = 1.0f;
    artworkTransitionSeconds_ = 0.0;
    artworkTransitionJustStarted_ = false;
    return true;
}

void AppleMusicRenderer::UploadPendingArtwork()
{
    std::vector<uint8_t> artwork;
    int32_t width = 0;
    int32_t height = 0;
    int32_t workTextureSize = 256;
    bool swapRedBlue = false;
    {
        std::lock_guard<std::mutex> lock(stateMutex_);
        if (!artworkPending_) {
            return;
        }
        artwork.swap(pendingArtwork_);
        width = pendingArtworkWidth_;
        height = pendingArtworkHeight_;
        workTextureSize = workTextureSize_;
        swapRedBlue = pendingSwapRedBlue_;
        artworkPending_ = false;
    }
    if (artwork.size() < static_cast<size_t>(width) * static_cast<size_t>(height) * 4) {
        return;
    }
    std::vector<uint8_t> workTexture =
        CenterCropToWorkTexture(artwork, width, height, workTextureSize);
    cachedArtwork_ = workTexture;
    cachedArtworkSize_ = workTextureSize;
    cachedSwapRedBlue_ = swapRedBlue;
    if (hasUploadedArtwork_) {
        previousFrameValid_ = CopyCurrentFrameToPrevious();
        std::swap(previousSourceTexture_, sourceTexture_);
        previousSwapRedBlue_ = swapRedBlue_;
        artworkTransitionSeconds_ = 0.0;
        artworkTransitionProgress_ = previousFrameValid_ ? 0.0f : 1.0f;
        artworkTransitionJustStarted_ = previousFrameValid_;
    }
    glBindTexture(GL_TEXTURE_2D, sourceTexture_);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, workTextureSize, workTextureSize, 0,
        GL_RGBA, GL_UNSIGNED_BYTE, workTexture.data());
    artworkWidth_ = workTextureSize;
    artworkHeight_ = workTextureSize;
    swapRedBlue_ = swapRedBlue;
    if (!hasUploadedArtwork_) {
        UploadFirstArtworkTexture(workTexture, workTextureSize, swapRedBlue);
    }
    sceneDirty_ = true;
}

void AppleMusicRenderer::RestoreCachedArtwork()
{
    if (cachedArtwork_.empty() || cachedArtworkSize_ <= 0) {
        return;
    }
    glBindTexture(GL_TEXTURE_2D, sourceTexture_);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, cachedArtworkSize_, cachedArtworkSize_, 0,
        GL_RGBA, GL_UNSIGNED_BYTE, cachedArtwork_.data());
    UploadFirstArtworkTexture(cachedArtwork_, cachedArtworkSize_, cachedSwapRedBlue_);
}

void AppleMusicRenderer::UploadFirstArtworkTexture(const std::vector<uint8_t> &artwork,
    int32_t size, bool swapRedBlue)
{
    glBindTexture(GL_TEXTURE_2D, previousSourceTexture_);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, size, size, 0,
        GL_RGBA, GL_UNSIGNED_BYTE, artwork.data());
    artworkWidth_ = size;
    artworkHeight_ = size;
    swapRedBlue_ = swapRedBlue;
    previousSwapRedBlue_ = swapRedBlue;
    artworkTransitionProgress_ = 1.0f;
    artworkTransitionSeconds_ = 0.0;
    initialRevealProgress_ = 0.0f;
    initialRevealSeconds_ = 0.0;
    initialRevealJustStarted_ = true;
    artworkTransitionJustStarted_ = false;
    previousFrameValid_ = false;
    sceneDirty_ = true;
    hasUploadedArtwork_ = true;
}

void AppleMusicRenderer::Render(double timestampSeconds)
{
    std::lock_guard<std::recursive_mutex> renderLock(renderMutex_);
    if (eglDisplay_ == EGL_NO_DISPLAY || eglSurface_ == EGL_NO_SURFACE ||
        eglContext_ == EGL_NO_CONTEXT) {
        return;
    }
    bool paused = false;
    float speed = 1.0f;
    bool resetClock = false;
    double backgroundFrameInterval = 1.0 / 15.0;
    double transitionFrameInterval = 1.0 / 60.0;
    double transitionDuration = 0.8;
    double initialRevealDurationRatio = 0.5;
    float blurRadiusActualPixels = 86.0f;
    float bufferScale = 1.0f;
    float overscan = 1.16f;
    bool artworkPending = false;
    bool geometryPending = false;
    {
        std::lock_guard<std::mutex> lock(stateMutex_);
        paused = paused_;
        speed = speed_;
        resetClock = resetClock_;
        backgroundFrameInterval = backgroundFrameIntervalSeconds_;
        transitionFrameInterval = transitionFrameIntervalSeconds_;
        transitionDuration = artworkTransitionDurationSeconds_;
        initialRevealDurationRatio = initialRevealDurationRatio_;
        blurRadiusActualPixels = blurRadiusActualPixels_;
        bufferScale = renderScale_;
        overscan = overscan_;
        artworkPending = artworkPending_;
        geometryPending = geometryDirty_;
        resetClock_ = false;
    }
    if (paused) {
        return;
    }
    const bool transitioning = artworkPending ||
        artworkTransitionProgress_ < 1.0f ||
        (hasUploadedArtwork_ && initialRevealProgress_ < 1.0f);
    const double presentationInterval =
        transitioning ? transitionFrameInterval : backgroundFrameInterval;
    const bool geometryRetryDue = DynamicBackgroundRenderPolicy::GeometryRetryDue(
        geometryPending,
        timestampSeconds,
        nextGeometryRetryTimestampSeconds_
    );
    if (geometryPending && !geometryRetryDue) {
        return;
    }
    if (!DynamicBackgroundRenderPolicy::ShouldPresent(
        timestampSeconds,
        lastPresentedTimestampSeconds_,
        presentationInterval,
        artworkPending,
        geometryRetryDue)) {
        return;
    }
    if (!eglMakeCurrent(eglDisplay_, eglSurface_, eglSurface_, eglContext_)) {
        return;
    }
    bool geometryApplied = !geometryPending;
    if (geometryRetryDue) {
        geometryApplied = ApplyPendingConfiguration();
        if (geometryApplied) {
            nextGeometryRetryTimestampSeconds_ = 0.0;
        } else if (timestampSeconds > 0.0) {
            nextGeometryRetryTimestampSeconds_ =
                timestampSeconds + GEOMETRY_RETRY_INTERVAL_SECONDS;
        }
    }
    if (!DynamicBackgroundRenderPolicy::CanRenderFrame(
        geometryPending,
        geometryRetryDue,
        geometryApplied)) {
        return;
    }
    UploadPendingArtwork();
    if (!hasUploadedArtwork_) {
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glViewport(0, 0, bufferWidth_, bufferHeight_);
        glDisable(GL_BLEND);
        glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        eglSwapBuffers(eglDisplay_, eglSurface_);
        if (timestampSeconds > 0.0) {
            lastPresentedTimestampSeconds_ = timestampSeconds;
        }
        return;
    }

    double delta = 0.0;
    if (resetClock || lastTimestampSeconds_ <= 0.0 || timestampSeconds <= 0.0) {
        lastTimestampSeconds_ = timestampSeconds;
        lastAnimationTimestampSeconds_ = timestampSeconds;
    } else {
        delta = DynamicBackgroundRenderPolicy::ClampedDelta(
            timestampSeconds,
            lastTimestampSeconds_
        );
        lastTimestampSeconds_ = timestampSeconds;
    }
    if (initialRevealJustStarted_) {
        delta = 0.0;
        initialRevealJustStarted_ = false;
    }
    if (artworkTransitionJustStarted_) {
        delta = 0.0;
        artworkTransitionJustStarted_ = false;
    }
    const bool animationDue = timestampSeconds <= 0.0 ||
        lastAnimationTimestampSeconds_ <= 0.0 ||
        timestampSeconds - lastAnimationTimestampSeconds_ >=
            backgroundFrameInterval * 0.95;
    if (animationDue) {
        if (timestampSeconds > 0.0 && lastAnimationTimestampSeconds_ > 0.0) {
            const double animationDelta = DynamicBackgroundRenderPolicy::ClampedDelta(
                timestampSeconds,
                lastAnimationTimestampSeconds_
            );
            animationSeconds_ += animationDelta * static_cast<double>(speed);
        }
        lastAnimationTimestampSeconds_ = timestampSeconds;
        if (speed > 0.0f) {
            sceneDirty_ = true;
        }
    }
    if (artworkTransitionProgress_ < 1.0f) {
        artworkTransitionSeconds_ += delta;
        artworkTransitionProgress_ = static_cast<float>(std::clamp(
            artworkTransitionSeconds_ / transitionDuration, 0.0, 1.0));
    }
    if (hasUploadedArtwork_ && initialRevealProgress_ < 1.0f) {
        initialRevealSeconds_ += delta;
        const double revealDuration = std::max(
            transitionDuration * initialRevealDurationRatio, 0.01);
        initialRevealProgress_ = static_cast<float>(std::clamp(
            initialRevealSeconds_ / revealDuration, 0.0, 1.0));
    }

    if (sceneDirty_ || !hasRenderedFrame_) {
        RenderScene();
        lastBlurredTexture_ = RenderBlur(blurRadiusActualPixels, bufferScale);
        hasRenderedFrame_ = lastBlurredTexture_ != 0;
        sceneDirty_ = false;
    }
    if (!hasRenderedFrame_) {
        return;
    }
    const GLuint previousTexture = previousFrameValid_ ?
        previousFrameTarget_.texture : lastBlurredTexture_;
    const float transitionProgress = previousFrameValid_ ?
        artworkTransitionProgress_ : 1.0f;
    RenderFinal(lastBlurredTexture_, previousTexture, transitionProgress,
        overscan, initialRevealProgress_);
    eglSwapBuffers(eglDisplay_, eglSurface_);
    if (timestampSeconds > 0.0) {
        lastPresentedTimestampSeconds_ = timestampSeconds;
    }
}

void AppleMusicRenderer::RenderScene()
{
    glDisable(GL_BLEND);
    glBindFramebuffer(GL_FRAMEBUFFER, targets_[0].framebuffer);
    glViewport(0, 0, bufferWidth_, bufferHeight_);
    glUseProgram(sceneProgram_);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, sourceTexture_);
    glUniform1i(sceneTextureLocation_, 0);
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, previousSourceTexture_);
    glUniform1i(scenePreviousTextureLocation_, 1);
    glUniform2f(sceneResolutionLocation_,
        static_cast<float>(bufferWidth_), static_cast<float>(bufferHeight_));
    glUniform2f(sceneTextureSizeLocation_,
        static_cast<float>(artworkWidth_), static_cast<float>(artworkHeight_));
    glUniform1f(sceneTimeLocation_, static_cast<float>(animationSeconds_));
    glUniform1f(sceneSwapRedBlueLocation_,
        swapRedBlue_ ? 1.0f : 0.0f);
    glUniform1f(scenePreviousSwapRedBlueLocation_,
        previousSwapRedBlue_ ? 1.0f : 0.0f);
    // Artwork crossfades are composed from cached blurred frames in RenderFinal.
    // Rendering only the current source keeps the nine-pass blur on the
    // background cadence while the lightweight final blend can run at 60 fps.
    glUniform1f(sceneArtworkTransitionLocation_, 1.0f);
    DrawFullscreen();
}

GLuint AppleMusicRenderer::RenderBlur(float actualPixelRadius, float bufferScale)
{
    glUseProgram(blurProgram_);
    glUniform2f(blurTexelLocation_,
        1.0f / static_cast<float>(bufferWidth_),
        1.0f / static_cast<float>(bufferHeight_));
    int32_t sourceIndex = 0;
    for (int32_t index = 0; index < BLUR_PASSES; ++index) {
        const int32_t destinationIndex = 1 - sourceIndex;
        glBindFramebuffer(GL_FRAMEBUFFER, targets_[destinationIndex].framebuffer);
        glViewport(0, 0, bufferWidth_, bufferHeight_);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, targets_[sourceIndex].texture);
        glUniform1i(blurInputLocation_, 0);
        const float progress = static_cast<float>(index + 1) /
            static_cast<float>(BLUR_PASSES);
        const float offset = (
            0.55f + std::pow(progress, 1.55f) * actualPixelRadius * 0.34f
        ) * bufferScale;
        glUniform1f(blurOffsetLocation_, offset);
        DrawFullscreen();
        sourceIndex = destinationIndex;
    }
    return targets_[sourceIndex].texture;
}

void AppleMusicRenderer::RenderFinal(GLuint texture, GLuint previousTexture,
    float artworkTransition, float overscan, float revealProgress)
{
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glViewport(0, 0, bufferWidth_, bufferHeight_);
    glUseProgram(finalProgram_);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, texture);
    glUniform1i(finalInputLocation_, 0);
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, previousTexture);
    glUniform1i(finalPreviousInputLocation_, 1);
    glUniform1f(finalArtworkTransitionLocation_, artworkTransition);
    glUniform2f(finalResolutionLocation_,
        static_cast<float>(bufferWidth_), static_cast<float>(bufferHeight_));
    glUniform1f(finalOverscanLocation_, overscan);
    glUniform1f(finalRevealLocation_, revealProgress);
    DrawFullscreen();
}

void AppleMusicRenderer::DrawFullscreen()
{
    glDrawArrays(GL_TRIANGLES, 0, 6);
}

GLuint AppleMusicRenderer::CompileShader(GLenum type, const char *source)
{
    const GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader);
    GLint compiled = GL_FALSE;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
    if (compiled == GL_TRUE) {
        return shader;
    }
    char message[1024] = {};
    glGetShaderInfoLog(shader, sizeof(message), nullptr, message);
    OH_LOG_Print(LOG_APP, LOG_ERROR, APP_LOG_DOMAIN, APP_LOG_TAG,
        "Shader compile failed: %{public}s", message);
    glDeleteShader(shader);
    return 0;
}

GLuint AppleMusicRenderer::LinkProgram(const char *vertexSource, const char *fragmentSource)
{
    const GLuint vertex = CompileShader(GL_VERTEX_SHADER, vertexSource);
    const GLuint fragment = CompileShader(GL_FRAGMENT_SHADER, fragmentSource);
    if (vertex == 0 || fragment == 0) {
        glDeleteShader(vertex);
        glDeleteShader(fragment);
        return 0;
    }
    const GLuint program = glCreateProgram();
    glAttachShader(program, vertex);
    glAttachShader(program, fragment);
    glLinkProgram(program);
    glDeleteShader(vertex);
    glDeleteShader(fragment);
    GLint linked = GL_FALSE;
    glGetProgramiv(program, GL_LINK_STATUS, &linked);
    if (linked == GL_TRUE) {
        return program;
    }
    char message[1024] = {};
    glGetProgramInfoLog(program, sizeof(message), nullptr, message);
    OH_LOG_Print(LOG_APP, LOG_ERROR, APP_LOG_DOMAIN, APP_LOG_TAG,
        "Program link failed: %{public}s", message);
    glDeleteProgram(program);
    return 0;
}

bool AppleMusicRenderer::CreatePrograms()
{
    sceneProgram_ = LinkProgram(VERTEX_SHADER, SCENE_FRAGMENT_SHADER);
    blurProgram_ = LinkProgram(VERTEX_SHADER, BLUR_FRAGMENT_SHADER);
    finalProgram_ = LinkProgram(VERTEX_SHADER, FINAL_FRAGMENT_SHADER);
    if (sceneProgram_ == 0 || blurProgram_ == 0 || finalProgram_ == 0) {
        return false;
    }
    sceneTextureLocation_ = glGetUniformLocation(sceneProgram_, "u_texture");
    scenePreviousTextureLocation_ = glGetUniformLocation(sceneProgram_, "u_previousTexture");
    sceneResolutionLocation_ = glGetUniformLocation(sceneProgram_, "u_resolution");
    sceneTextureSizeLocation_ = glGetUniformLocation(sceneProgram_, "u_textureSize");
    sceneTimeLocation_ = glGetUniformLocation(sceneProgram_, "u_time");
    sceneSwapRedBlueLocation_ = glGetUniformLocation(sceneProgram_, "u_swapRedBlue");
    scenePreviousSwapRedBlueLocation_ =
        glGetUniformLocation(sceneProgram_, "u_previousSwapRedBlue");
    sceneArtworkTransitionLocation_ =
        glGetUniformLocation(sceneProgram_, "u_artworkTransition");
    blurInputLocation_ = glGetUniformLocation(blurProgram_, "u_input");
    blurTexelLocation_ = glGetUniformLocation(blurProgram_, "u_texel");
    blurOffsetLocation_ = glGetUniformLocation(blurProgram_, "u_offset");
    finalInputLocation_ = glGetUniformLocation(finalProgram_, "u_input");
    finalPreviousInputLocation_ =
        glGetUniformLocation(finalProgram_, "u_previousInput");
    finalArtworkTransitionLocation_ =
        glGetUniformLocation(finalProgram_, "u_artworkTransition");
    finalResolutionLocation_ = glGetUniformLocation(finalProgram_, "u_resolution");
    finalOverscanLocation_ = glGetUniformLocation(finalProgram_, "u_overscan");
    finalRevealLocation_ = glGetUniformLocation(finalProgram_, "u_reveal");
    return true;
}

bool AppleMusicRenderer::CreateSourceTextures()
{
    const uint8_t fallback[] = { 24, 18, 40, 255 };
    GLuint textures[2] = {};
    glGenTextures(2, textures);
    sourceTexture_ = textures[0];
    previousSourceTexture_ = textures[1];
    for (const GLuint texture : textures) {
        glBindTexture(GL_TEXTURE_2D, texture);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, fallback);
    }
    return sourceTexture_ != 0 && previousSourceTexture_ != 0;
}

bool AppleMusicRenderer::CreateRenderTarget(RenderTarget &target)
{
    glGenTextures(1, &target.texture);
    glBindTexture(GL_TEXTURE_2D, target.texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, bufferWidth_, bufferHeight_, 0,
        GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glGenFramebuffers(1, &target.framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, target.framebuffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
        target.texture, 0);
    return glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
}

bool AppleMusicRenderer::CreateRenderTargets()
{
    if (bufferWidth_ <= 0 || bufferHeight_ <= 0) {
        return false;
    }
    RenderTarget replacementTargets[2];
    RenderTarget replacementPreviousFrame;
    const bool createdFirst = CreateRenderTarget(replacementTargets[0]);
    const bool createdSecond = CreateRenderTarget(replacementTargets[1]);
    const bool createdPrevious = CreateRenderTarget(replacementPreviousFrame);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    if (!createdFirst || !createdSecond || !createdPrevious) {
        DestroyRenderTarget(replacementTargets[0]);
        DestroyRenderTarget(replacementTargets[1]);
        DestroyRenderTarget(replacementPreviousFrame);
        return false;
    }
    DestroyRenderTargets();
    targets_[0] = replacementTargets[0];
    targets_[1] = replacementTargets[1];
    previousFrameTarget_ = replacementPreviousFrame;
    return true;
}

void AppleMusicRenderer::DestroyRenderTarget(RenderTarget &target)
{
    if (target.framebuffer != 0) {
        glDeleteFramebuffers(1, &target.framebuffer);
        target.framebuffer = 0;
    }
    if (target.texture != 0) {
        glDeleteTextures(1, &target.texture);
        target.texture = 0;
    }
}

void AppleMusicRenderer::DestroyRenderTargets()
{
    for (auto &target : targets_) {
        DestroyRenderTarget(target);
    }
    DestroyRenderTarget(previousFrameTarget_);
}

bool AppleMusicRenderer::CopyCurrentFrameToPrevious()
{
    if (!hasRenderedFrame_ || lastBlurredTexture_ == 0 ||
        previousFrameTarget_.framebuffer == 0) {
        return false;
    }
    GLuint sourceFramebuffer = 0;
    for (const auto &target : targets_) {
        if (target.texture == lastBlurredTexture_) {
            sourceFramebuffer = target.framebuffer;
            break;
        }
    }
    if (sourceFramebuffer == 0) {
        return false;
    }
    while (glGetError() != GL_NO_ERROR) {
    }
    glBindFramebuffer(GL_READ_FRAMEBUFFER, sourceFramebuffer);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, previousFrameTarget_.framebuffer);
    glBlitFramebuffer(
        0, 0, bufferWidth_, bufferHeight_,
        0, 0, bufferWidth_, bufferHeight_,
        GL_COLOR_BUFFER_BIT, GL_NEAREST);
    const bool copied = glGetError() == GL_NO_ERROR;
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    return copied;
}

void AppleMusicRenderer::DeleteProgram(GLuint &program)
{
    if (program != 0) {
        glDeleteProgram(program);
        program = 0;
    }
}

void AppleMusicRenderer::DestroyPrograms()
{
    DeleteProgram(sceneProgram_);
    DeleteProgram(blurProgram_);
    DeleteProgram(finalProgram_);
    sceneTextureLocation_ = -1;
    scenePreviousTextureLocation_ = -1;
    sceneResolutionLocation_ = -1;
    sceneTextureSizeLocation_ = -1;
    sceneTimeLocation_ = -1;
    sceneSwapRedBlueLocation_ = -1;
    scenePreviousSwapRedBlueLocation_ = -1;
    sceneArtworkTransitionLocation_ = -1;
    blurInputLocation_ = -1;
    blurTexelLocation_ = -1;
    blurOffsetLocation_ = -1;
    finalInputLocation_ = -1;
    finalPreviousInputLocation_ = -1;
    finalArtworkTransitionLocation_ = -1;
    finalResolutionLocation_ = -1;
    finalOverscanLocation_ = -1;
    finalRevealLocation_ = -1;
}

void AppleMusicRenderer::Release()
{
    std::lock_guard<std::recursive_mutex> renderLock(renderMutex_);
    if (eglDisplay_ != EGL_NO_DISPLAY && eglContext_ != EGL_NO_CONTEXT) {
        eglMakeCurrent(eglDisplay_, eglSurface_, eglSurface_, eglContext_);
        DestroyRenderTargets();
        DestroyPrograms();
        const GLuint sourceTextures[2] = { sourceTexture_, previousSourceTexture_ };
        glDeleteTextures(2, sourceTextures);
        sourceTexture_ = 0;
        previousSourceTexture_ = 0;
        eglMakeCurrent(eglDisplay_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    }
    if (eglDisplay_ != EGL_NO_DISPLAY && eglSurface_ != EGL_NO_SURFACE) {
        eglDestroySurface(eglDisplay_, eglSurface_);
    }
    if (eglDisplay_ != EGL_NO_DISPLAY && eglContext_ != EGL_NO_CONTEXT) {
        eglDestroyContext(eglDisplay_, eglContext_);
    }
    if (eglDisplay_ != EGL_NO_DISPLAY) {
        eglTerminate(eglDisplay_);
    }
    eglDisplay_ = EGL_NO_DISPLAY;
    eglSurface_ = EGL_NO_SURFACE;
    eglContext_ = EGL_NO_CONTEXT;
    eglConfig_ = nullptr;
    window_ = nullptr;
    bufferWidth_ = 0;
    bufferHeight_ = 0;
    lastBlurredTexture_ = 0;
    hasRenderedFrame_ = false;
    previousFrameValid_ = false;
    sceneDirty_ = true;
    hasUploadedArtwork_ = false;
    artworkTransitionProgress_ = 1.0f;
    artworkTransitionSeconds_ = 0.0;
    artworkTransitionJustStarted_ = false;
    initialRevealProgress_ = 0.0f;
    initialRevealSeconds_ = 0.0;
    initialRevealJustStarted_ = false;
    lastAnimationTimestampSeconds_ = 0.0;
    lastPresentedTimestampSeconds_ = 0.0;
    nextGeometryRetryTimestampSeconds_ = 0.0;
}

} // namespace wplayer
