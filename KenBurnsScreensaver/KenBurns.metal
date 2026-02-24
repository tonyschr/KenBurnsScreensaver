#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct KenBurnsUniforms {
    float2 srcOrigin;    // normalized origin of the crop rect
    float2 srcSize;      // normalized size of the crop rect
    float  alpha;        // for cross-dissolve
};

vertex VertexOut kenBurnsVertex(uint vid [[vertex_id]],
                                 constant float4* vertices [[buffer(0)]]) {
    VertexOut out;
    float4 v = vertices[vid];
    out.position = float4(v.xy, 0.0, 1.0);
    out.texCoord = v.zw;
    return out;
}

fragment float4 kenBurnsFragment(VertexOut in [[stage_in]],
                                  texture2d<float> tex [[texture(0)]],
                                  constant KenBurnsUniforms& u [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    // Map texCoord [0,1] into the animated crop window
    float2 uv = u.srcOrigin + in.texCoord * u.srcSize;
    float4 color = tex.sample(s, uv);
    color.a *= u.alpha;
    return color;
}
