#ifndef WPLAYER_BACKGROUND_PLUGIN_MANAGER_H
#define WPLAYER_BACKGROUND_PLUGIN_MANAGER_H

#include <ace/xcomponent/native_interface_xcomponent.h>
#include <napi/native_api.h>

namespace wplayer {

class PluginManager {
public:
    static void Export(napi_env env, napi_value exports);

private:
    static napi_value SetArtwork(napi_env env, napi_callback_info info);
    static napi_value SetPaused(napi_env env, napi_callback_info info);
    static napi_value SetSpeed(napi_env env, napi_callback_info info);
    static napi_value SetRenderScale(napi_env env, napi_callback_info info);
    static napi_value SetFrameRates(napi_env env, napi_callback_info info);
    static napi_value SetWorkTextureSize(napi_env env, napi_callback_info info);
    static napi_value SetBlurRadius(napi_env env, napi_callback_info info);
    static napi_value SetOverscan(napi_env env, napi_callback_info info);
};

} // namespace wplayer

#endif
