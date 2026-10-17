#version 440
// Lumen live grid: a perspective floor rushing toward you below the horizon, light
// cycles racing along its lines, and a horizon that glows with the system's activity.
// Transparent above the horizon so the wallpaper shows through.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float load;       // 0..1 CPU load: grid speed and pulse
    float agent;      // 0 idle, 1 Claude working, 2 Claude waiting
    float horizon;    // 0..1 from the top
    vec2 size;
    vec4 color;       // theme accent
    vec4 alert;       // attention color
};

float line(float v, float width) {
    float d = abs(fract(v - 0.5) - 0.5) / max(fwidth(v), 1e-4);
    return 1.0 - clamp(d - width, 0.0, 1.0);
}

// A light cycle in lane `lane` (world x), riding toward the horizon; returns its light at (x, z).
float cycle(float x, float z, float lane, float speed, float phase) {
    float head = mod(time * speed + phase, 40.0) + 1.0;     // depth of the head
    float trail = 6.0;
    float along = head - z;                                  // 0 at the head, grows behind it
    float onLane = 1.0 - smoothstep(0.0, 0.035 * z, abs(x - lane));
    float inTrail = step(0.0, along) * (1.0 - smoothstep(0.0, trail, along));
    float headGlow = exp(-abs(along) * 6.0);
    return onLane * (inTrail * 0.9 + headGlow * 2.0);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float aspect = size.x / size.y;
    vec3 c = vec3(0.0);
    float a = 0.0;

    // everything stays in the theme color; Claude waiting makes the horizon pulse harder
    vec3 tint = color.rgb;
    float busy = agent > 0.5 ? 1.0 : 0.0;
    float waiting = agent > 1.5 ? 1.0 : 0.0;
    float beat = 0.5 + 0.5 * sin(time * (1.2 + 3.0 * load + 3.0 * waiting));

    // horizon glow: brighter while Claude works, pulsing faster with CPU load
    float dh = uv.y - horizon;
    float glow = exp(-abs(dh) * (dh < 0.0 ? 60.0 : 25.0)) * (0.35 + 0.35 * busy + 0.2 * beat * (0.3 + load + 1.5 * waiting));
    c += tint * glow;
    a += glow;

    if (dh > 0.0) {
        float z = 0.12 / dh;                                 // depth
        float x = (uv.x - 0.5) * aspect * z;                 // world x
        float speed = 1.2 + 3.5 * load;
        float fade = exp(-z * 0.09);                         // dim toward the horizon

        float g = max(line(x * 2.0, 0.2), line(z * 2.0 - time * speed, 0.2));
        float grid = g * fade * (0.28 + 0.12 * beat * load);
        c += color.rgb * grid;
        a += grid;

        // light cycles, all in the theme color
        float lc = cycle(x, z, -2.5, 3.0 + 2.0 * load, 0.0) + cycle(x, z, 1.67, 2.3 + 2.0 * load, 17.0);
        float rv = cycle(x, z, 4.17, 2.7, 29.0);
        vec3 hot = mix(color.rgb, vec3(1.0), 0.35);
        c += hot * (lc * 1.4 + rv * 1.2) * fade;
        a += (lc + rv) * fade;
    }

    a = clamp(a, 0.0, 1.0);
    fragColor = vec4(c, a) * qt_Opacity;
}
