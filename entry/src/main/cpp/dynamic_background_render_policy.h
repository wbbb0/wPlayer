#ifndef WPLAYER_DYNAMIC_BACKGROUND_RENDER_POLICY_H
#define WPLAYER_DYNAMIC_BACKGROUND_RENDER_POLICY_H

#include <cstdint>

namespace wplayer {

class DynamicBackgroundRenderPolicy {
public:
    static constexpr uint64_t MAX_LOGICAL_SURFACE_DIMENSION = 16384;

    static constexpr bool IsLogicalDimensionSupported(uint64_t dimension)
    {
        return dimension > 0 && dimension <= MAX_LOGICAL_SURFACE_DIMENSION;
    }

    static constexpr bool GeometryRetryDue(bool geometryPending,
        double timestampSeconds, double nextRetryTimestampSeconds)
    {
        return geometryPending &&
            (timestampSeconds <= 0.0 || nextRetryTimestampSeconds <= 0.0 ||
                timestampSeconds >= nextRetryTimestampSeconds);
    }

    static constexpr bool CanRenderFrame(bool geometryPending,
        bool geometryRetryDue, bool geometryApplied)
    {
        return !geometryPending || (geometryRetryDue && geometryApplied);
    }

    static constexpr bool ShouldPresent(double timestampSeconds,
        double lastPresentedTimestampSeconds, double presentationIntervalSeconds,
        bool artworkPending, bool geometryPending)
    {
        return artworkPending || geometryPending ||
            timestampSeconds <= 0.0 || lastPresentedTimestampSeconds <= 0.0 ||
            timestampSeconds - lastPresentedTimestampSeconds >=
                presentationIntervalSeconds * 0.95;
    }

    static constexpr double ClampedDelta(double timestampSeconds,
        double previousTimestampSeconds)
    {
        const double delta = timestampSeconds - previousTimestampSeconds;
        return delta <= 0.0 ? 0.0 : (delta >= 0.20 ? 0.20 : delta);
    }

    static constexpr bool CanCommitGeometry(bool nativeGeometryApplied,
        bool renderTargetsCreated, bool configurationStillCurrent)
    {
        return nativeGeometryApplied && renderTargetsCreated && configurationStillCurrent;
    }
};

static_assert(DynamicBackgroundRenderPolicy::ShouldPresent(
    1.01, 1.0, 1.0 / 15.0, true, false));
static_assert(DynamicBackgroundRenderPolicy::ShouldPresent(
    1.01, 1.0, 1.0 / 15.0, false, true));
static_assert(!DynamicBackgroundRenderPolicy::ShouldPresent(
    1.01, 1.0, 1.0 / 15.0, false, false));
static_assert(DynamicBackgroundRenderPolicy::ClampedDelta(2.0, 1.0) == 0.20);
static_assert(!DynamicBackgroundRenderPolicy::CanCommitGeometry(true, false, true));
static_assert(!DynamicBackgroundRenderPolicy::CanCommitGeometry(true, true, false));
static_assert(DynamicBackgroundRenderPolicy::CanCommitGeometry(true, true, true));
static_assert(DynamicBackgroundRenderPolicy::IsLogicalDimensionSupported(1));
static_assert(!DynamicBackgroundRenderPolicy::IsLogicalDimensionSupported(0));
static_assert(!DynamicBackgroundRenderPolicy::IsLogicalDimensionSupported(16385));
static_assert(!DynamicBackgroundRenderPolicy::GeometryRetryDue(true, 1.0, 1.5));
static_assert(DynamicBackgroundRenderPolicy::GeometryRetryDue(true, 1.5, 1.5));
static_assert(!DynamicBackgroundRenderPolicy::CanRenderFrame(true, false, false));
static_assert(!DynamicBackgroundRenderPolicy::CanRenderFrame(true, true, false));
static_assert(DynamicBackgroundRenderPolicy::CanRenderFrame(true, true, true));
static_assert(DynamicBackgroundRenderPolicy::CanRenderFrame(false, false, false));

} // namespace wplayer

#endif
