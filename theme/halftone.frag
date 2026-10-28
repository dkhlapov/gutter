#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

// The first two members are the ones Qt's default vertex shader writes; the rest are Halftone's properties.
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 dotColor;
    float dotRadius;
    float grid;
    vec2 size;
};

void main() {
    vec2 px = qt_TexCoord0 * size;
    vec2 local = mod(px, vec2(grid)) - vec2(grid * 0.5);
    float d = length(local);
    // One pixel of edge smoothing keeps the dots round without blurring them.
    float a = 1.0 - smoothstep(dotRadius - 0.5, dotRadius + 0.5, d);
    // Qt passes colour uniforms premultiplied, so alpha is already in dotColor.rgb.
    fragColor = dotColor * a * qt_Opacity;
}
