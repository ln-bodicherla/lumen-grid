#version 440
// Disc duel: two light discs fly over the Grid on looping paths, trailing light;
// when they pass close, sparks flare. One in the theme color, one white-hot.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float fade;       // 0..1 fade in / out
    vec2 size;
    vec4 color;       // theme accent
};

vec2 discPos(int i, float t) {
    float aspect = size.x / size.y;
    if (i == 0)
        return vec2(0.42 * aspect * sin(t * 0.61), 0.30 * sin(t * 0.83 + 0.7));
    return vec2(0.40 * aspect * sin(t * 0.57 + 2.4), 0.28 * sin(t * 0.91 + 3.9));
}

float ring(vec2 p, vec2 c, float r, float w) {
    float d = abs(length(p - c) - r);
    return smoothstep(w, 0.0, d) + 0.35 * exp(-d * 90.0);
}

void main() {
    vec2 p = (qt_TexCoord0 - 0.5) * vec2(size.x / size.y, 1.0);
    p.y = -p.y;
    vec3 col = vec3(0.0);
    float a = 0.0;
    vec3 tones[2];
    tones[0] = color.rgb;
    tones[1] = mix(color.rgb, vec3(1.0), 0.75);

    for (int i = 0; i < 2; i++) {
        vec2 c = discPos(i, time);
        vec3 tone = tones[i];
        // trail: fading light points along the recent path
        for (int j = 1; j <= 28; j++) {
            vec2 q = discPos(i, time - float(j) * 0.035);
            float d = length(p - q);
            float k = 1.0 - float(j) / 28.0;
            float g = exp(-d * 260.0) * k * 0.9;
            col += tone * g; a += g;
        }
        // the disc: outer ring, inner ring, core, and a spinning light segment
        float rr = ring(p, c, 0.045, 0.004) + 0.6 * ring(p, c, 0.024, 0.003);
        float core = exp(-length(p - c) * 160.0);
        vec2 v = p - c;
        float ang = atan(v.y, v.x) + time * (i == 0 ? 7.0 : -7.0);
        float seg = smoothstep(0.6, 0.9, sin(ang * 3.0)) * smoothstep(0.012, 0.0, abs(length(v) - 0.045));
        float g = rr + core * 1.5 + seg * 1.2;
        col += tone * g; a += g;
    }
    // sparks where they pass close
    vec2 c0 = discPos(0, time), c1 = discPos(1, time);
    float near = smoothstep(0.18, 0.03, length(c0 - c1));
    vec2 mid = (c0 + c1) * 0.5;
    float burst = near * exp(-length(p - mid) * 18.0);
    col += mix(color.rgb, vec3(1.0), 0.6) * burst * 2.0; a += burst;

    // dark veil so the duel stands out over the wallpaper
    float veil = 0.45;
    vec3 outc = col;
    float outa = clamp(veil + a, 0.0, 1.0);
    fragColor = vec4(outc * fade, outa * fade) * qt_Opacity;
}
