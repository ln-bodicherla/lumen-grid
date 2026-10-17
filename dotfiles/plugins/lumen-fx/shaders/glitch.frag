#version 440
// Holo-glitch: drawn over a just-focused window using a snapshot of that window.
// Color split, horizontal band jumps and scanline flicker, strongest at the start,
// then it fades away to reveal the real window, like a hologram locking in.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;   // 0..1
    float seed;
    vec2 size;
    vec4 color;       // theme accent
};
layout(binding = 1) uniform sampler2D source;

float hash(float n) { return fract(sin(n * 91.345 + seed * 17.0) * 43758.5453); }

void main() {
    vec2 uv = qt_TexCoord0;
    float k = 1.0 - progress;                       // glitch strength
    // horizontal bands jump sideways, re-rolled a few times during the effect
    float step3 = floor(progress * 5.0);
    float band = floor(uv.y * 24.0);
    float jump = (hash(band + step3 * 13.0) - 0.5) * 0.09 * k * step(0.5, hash(band * 3.1 + step3));
    vec2 p = vec2(uv.x + jump, uv.y);
    // color split
    float split = 0.014 * k;
    float r = texture(source, p + vec2(split, 0.0)).r;
    float g = texture(source, p).g;
    float b = texture(source, p - vec2(split, 0.0)).b;
    vec3 col = vec3(r, g, b);
    // scanlines and a flicker of the theme light
    col *= 1.0 - 0.28 * k * (0.5 + 0.5 * sin(uv.y * size.y * 1.4));
    col += color.rgb * 0.18 * k * step(0.82, hash(band + step3 * 5.0));
    // fully over the window at first, gone by the end
    float a = smoothstep(1.0, 0.55, progress);
    fragColor = vec4(col * a, a) * qt_Opacity;
}
