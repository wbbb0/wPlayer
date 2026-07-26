#ifndef WPLAYER_APPLE_MUSIC_RENDERER_H
#define WPLAYER_APPLE_MUSIC_RENDERER_H

#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <native_window/external_window.h>
#include <cstddef>
#include <cstdint>
#include <mutex>
#include <vector>

namespace wplayer {

class AppleMusicRenderer {
public:
    AppleMusicRenderer() = default;
    ~AppleMusicRenderer();

    bool Initialize(OHNativeWindow *window, uint64_t width, uint64_t height);
    void Resize(uint64_t width, uint64_t height);
    void Release();
    void Render(double timestampSeconds);

    void SetArtwork(const uint8_t *bytes, size_t byteCount, int32_t width, int32_t height,
        bool swapRedBlue);
    void SetPaused(bool paused);
    void SetSpeed(float speed);
    void SetRenderScale(float scale);
    void SetFrameRates(float backgroundFps, float transitionFps,
        float transitionDurationSeconds, float initialRevealDurationRatio);
    void SetWorkTextureSize(int32_t size);
    void SetBlurRadius(float actualPixelRadius);
    void SetOverscan(float overscan);

private:
    struct RenderTarget {
        GLuint texture = 0;
        GLuint framebuffer = 0;
    };

    bool CreatePrograms();
    bool CreateSourceTextures();
    bool CreateRenderTargets();
    bool CreateRenderTarget(RenderTarget &target);
    void DestroyRenderTarget(RenderTarget &target);
    void DestroyRenderTargets();
    void DestroyPrograms();
    void UploadPendingArtwork();
    void RestoreCachedArtwork();
    void UploadFirstArtworkTexture(const std::vector<uint8_t> &artwork,
        int32_t size, bool swapRedBlue);
    bool ApplyPendingConfiguration();
    bool CopyCurrentFrameToPrevious();
    void DrawFullscreen();
    void RenderScene();
    GLuint RenderBlur(float actualPixelRadius, float bufferScale);
    void RenderFinal(GLuint texture, GLuint previousTexture, float artworkTransition,
        float overscan, float revealProgress);
    GLuint CompileShader(GLenum type, const char *source);
    GLuint LinkProgram(const char *vertexSource, const char *fragmentSource);
    void DeleteProgram(GLuint &program);

    OHNativeWindow *window_ = nullptr;
    uint64_t logicalWidth_ = 0;
    uint64_t logicalHeight_ = 0;
    int32_t bufferWidth_ = 0;
    int32_t bufferHeight_ = 0;
    float renderScale_ = 0.465f;
    bool geometryDirty_ = true;

    EGLDisplay eglDisplay_ = EGL_NO_DISPLAY;
    EGLSurface eglSurface_ = EGL_NO_SURFACE;
    EGLContext eglContext_ = EGL_NO_CONTEXT;
    EGLConfig eglConfig_ = nullptr;

    GLuint sceneProgram_ = 0;
    GLuint blurProgram_ = 0;
    GLuint finalProgram_ = 0;
    GLint sceneTextureLocation_ = -1;
    GLint scenePreviousTextureLocation_ = -1;
    GLint sceneResolutionLocation_ = -1;
    GLint sceneTextureSizeLocation_ = -1;
    GLint sceneTimeLocation_ = -1;
    GLint sceneSwapRedBlueLocation_ = -1;
    GLint scenePreviousSwapRedBlueLocation_ = -1;
    GLint sceneArtworkTransitionLocation_ = -1;
    GLint blurInputLocation_ = -1;
    GLint blurTexelLocation_ = -1;
    GLint blurOffsetLocation_ = -1;
    GLint finalInputLocation_ = -1;
    GLint finalPreviousInputLocation_ = -1;
    GLint finalArtworkTransitionLocation_ = -1;
    GLint finalResolutionLocation_ = -1;
    GLint finalOverscanLocation_ = -1;
    GLint finalRevealLocation_ = -1;
    GLuint sourceTexture_ = 0;
    GLuint previousSourceTexture_ = 0;
    RenderTarget targets_[2];
    RenderTarget previousFrameTarget_;
    GLuint lastBlurredTexture_ = 0;
    bool hasRenderedFrame_ = false;
    bool previousFrameValid_ = false;
    bool sceneDirty_ = true;

    std::mutex stateMutex_;
    std::recursive_mutex renderMutex_;
    std::vector<uint8_t> pendingArtwork_;
    int32_t pendingArtworkWidth_ = 0;
    int32_t pendingArtworkHeight_ = 0;
    bool pendingSwapRedBlue_ = false;
    bool artworkPending_ = false;
    std::vector<uint8_t> cachedArtwork_;
    int32_t cachedArtworkSize_ = 0;
    bool cachedSwapRedBlue_ = false;
    int32_t artworkWidth_ = 1;
    int32_t artworkHeight_ = 1;
    int32_t workTextureSize_ = 256;
    bool swapRedBlue_ = false;
    bool previousSwapRedBlue_ = false;
    bool hasUploadedArtwork_ = false;
    float artworkTransitionProgress_ = 1.0f;
    double artworkTransitionSeconds_ = 0.0;
    bool artworkTransitionJustStarted_ = false;
    float initialRevealProgress_ = 0.0f;
    double initialRevealSeconds_ = 0.0;
    bool initialRevealJustStarted_ = false;
    bool paused_ = false;
    float speed_ = 1.0f;
    double backgroundFrameIntervalSeconds_ = 1.0 / 15.0;
    double transitionFrameIntervalSeconds_ = 1.0 / 60.0;
    double artworkTransitionDurationSeconds_ = 0.8;
    double initialRevealDurationRatio_ = 0.5;
    float blurRadiusActualPixels_ = 86.0f;
    float overscan_ = 1.16f;
    bool resetClock_ = true;
    double lastTimestampSeconds_ = 0.0;
    double lastAnimationTimestampSeconds_ = 0.0;
    double lastPresentedTimestampSeconds_ = 0.0;
    double nextGeometryRetryTimestampSeconds_ = 0.0;
    double animationSeconds_ = 0.0;
};

} // namespace wplayer

#endif
