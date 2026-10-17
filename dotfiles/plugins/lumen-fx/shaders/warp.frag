#version 440
// Warp streaks for a workspace switch: light lines rush outward from the center of the
// screen and fade, like the light cycle accelerating through the Grid.
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

float hash(float n) { return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453); }

void main() {
    vec2 p = (qt_TexCoord0 - 0.5) * vec2(size.x / size.y, 1.0);
    float r = length(p);
    float ang = atan(p.y, p.x);
    float lanes = 140.0;
    float id = floor((ang + 3.14159) / 6.28318 * lanes);
    float h = hash(id);
    // each streak: a short dash rushing outward, starting at its own moment
    float start = h * 0.35;
    float t = clamp((progress - start) / 0.55, 0.0, 1.0);
    float head = mix(0.05, 1.3, t * t);
    float len = 0.12 + 0.25 * hash(id + 7.0);
    float along = smoothstep(head - len, head, r) * (1.0 - smoothstep(head, head + 0.01, r));
    float laneW = abs(fract((ang + 3.14159) / 6.28318 * lanes) - 0.5);
    float thin = 1.0 - smoothstep(0.06, 0.18, laneW);
    float show = step(0.55, hash(id + 3.0)) * (t > 0.0 && t < 1.0 ? 1.0 : 0.0);
    float a = along * thin * show * (1.0 - progress) * smoothstep(0.08, 0.3, r);
    vec3 col = mix(color.rgb, vec3(1.0), 0.4) * a;
    // a quick flash of the theme light at the very start
    float flash = (1.0 - smoothstep(0.0, 0.25, progress)) * 0.08;
    fragColor = vec4(col + color.rgb * flash, a + flash) * qt_Opacity;
}
