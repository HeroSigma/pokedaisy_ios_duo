#include <metal_stdlib>
using namespace metal;

// A full-viewport quad (PixelView sets the viewport to the picture's aspect-fit box).
struct PdVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex PdVertexOut pd_vertex(uint vid [[vertex_id]]) {
    float2 corners[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    PdVertexOut out;
    out.position = float4(corners[vid], 0, 1);
    out.uv = float2((corners[vid].x + 1) * 0.5, 1 - (corners[vid].y + 1) * 0.5);
    return out;
}

// Sharp bilinear (libretro's sharp-bilinear-simple): nearest inside each texel, linear only across a screen pixel at its
// edges, so pixel art scaled by a non-whole factor keeps square, even pixels without shimmer.
fragment float4 pd_fragment(PdVertexOut in [[stage_in]], texture2d<float> tex [[texture(0)]],
                            constant float2& scale [[buffer(0)]]) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    float2 size = float2(tex.get_width(), tex.get_height());
    float2 texel = in.uv * size;
    float2 floored = floor(texel);
    float2 s = fract(texel);
    float2 region = 0.5 - 0.5 / max(scale, float2(1.0));
    float2 centre = s - 0.5;
    float2 f = (centre - clamp(centre, -region, region)) * max(scale, float2(1.0)) + 0.5;
    float4 c = tex.sample(linearSampler, (floored + f) / size);
    return float4(c.rgb, 1.0);
}
