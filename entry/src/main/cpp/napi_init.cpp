#include "plugin_manager.h"

#include <napi/native_api.h>

namespace wplayer {
namespace {

napi_value Init(napi_env env, napi_value exports)
{
    PluginManager::Export(env, exports);
    return exports;
}

napi_module BACKGROUND_MODULE = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "wplayerbackground",
    .nm_priv = nullptr,
    .reserved = { 0 }
};

} // namespace

extern "C" __attribute__((constructor)) void RegisterWPlayerBackgroundModule()
{
    napi_module_register(&BACKGROUND_MODULE);
}

} // namespace wplayer
