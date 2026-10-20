// The Decay win animation's dissolve (spec "Win animations"): fractal value noise against a rising
// threshold eats the card away along ragged, organic edges, with a thin burnt-orange rim just
// ahead of each hole. On the GPU, so it is continuous at the display's full frame rate.
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float valueNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float a = hash21(i), b = hash21(i + float2(1, 0)), c = hash21(i + float2(0, 1)), d = hash21(i + float2(1, 1));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float v = 0.0, amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        v += amplitude * valueNoise(p);
        p = p * 2.03 + 17.0;
        amplitude *= 0.5;
    }
    return v / 0.9375;                          // 0…1
}

/// - progress: 0 untouched … 1 gone. - seed: a different pattern per card. - scale: noise cell
///   size, in points.
[[ stitchable ]] half4 dissolve(float2 position, SwiftUI::Layer layer, float progress, float seed, float scale) {
    half4 color = layer.sample(position);
    const float rim = 0.07;
    float threshold = mix(-rim, 1.0, progress);
    float n = fbm(position / max(scale, 1.0) + seed * 7.31);
    if (n < threshold) return half4(0);
    if (n < threshold + rim) {
        half t = half((n - threshold) / rim);
        half3 ember = half3(0.8, 0.333, 0.0) * color.a;  // premultiplied burnt orange
        return half4(mix(ember, color.rgb, t), color.a);
    }
    return color;
}
