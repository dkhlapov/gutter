#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 inkColor;
    vec2 radius; // the outline's width, in texture coordinates along each axis
    float paperLum; // the lightness of the paper the icon sits on, 0 to 1
};

layout(binding = 1) uniform sampler2D source;

// The source over an ink silhouette grown by `radius`, anti-aliased: a light icon keeps an ink edge on light paper.
void main() {
    vec4 src = texture(source, qt_TexCoord0);
    // Coverage, not a yes/no: three rings of samples out to the outline's width. The share of them that land on the
    // icon falls off smoothly with the distance from its edge, so the outline's own edge is anti-aliased instead of
    // a staircase.
    float cover = src.a;
    // The icon's own lightness, from the pixels around this one (premultiplied, so the sum is already weighted by alpha).
    vec3 around = src.rgb;
    float weight = src.a;
    for (int ring = 1; ring <= 3; ring++) {
        float r = float(ring) / 3.0;
        for (int i = 0; i < 12; i++) {
            float t = float(i) * 0.52359878 + float(ring) * 0.3; // 2 pi / 12, each ring turned a little
            vec4 n = texture(source, qt_TexCoord0 + vec2(cos(t), sin(t)) * radius * r);
            cover += n.a;
            around += n.rgb;
            weight += n.a;
        }
    }
    float a = smoothstep(0.02, 0.3, cover / 37.0);
    // An icon that already contrasts with the paper (a dark icon on light paper, a light one on dark) needs no
    // outline: an ink edge would only fill its gaps with a blob. One that sits close to the paper's own lightness
    // (a light icon on light paper) gets the ink edge.
    float lum = weight > 0.0 ? dot(around / weight, vec3(0.299, 0.587, 0.114)) : paperLum;
    float needs = smoothstep(0.3, 0.55, 1.0 - abs(lum - paperLum) * 1.0);
    a *= needs;
    // Premultiplied: the source keeps its own colour, the ink shows only where the source is clear.
    fragColor = (src + inkColor * a * (1.0 - src.a)) * qt_Opacity;
}
