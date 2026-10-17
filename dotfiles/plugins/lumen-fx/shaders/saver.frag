#version 440
// Lumen screensaver: Sentinels patrol over the grid. Wireframe outlines in the
// attention color, a search beam under each, a grid floor rushing below.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    vec2 size;
    vec4 color;   // theme accent (grid)
    vec4 alert;   // attention color (Sentinels)
};

float sdBox(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}
float sdSeg(vec2 p, vec2 a, vec2 b, float r) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// A Sentinel seen from the front: a wide wing bar with swept tips, a cockpit,
// and two legs that splay down to feet. Unit width ~1, y up.
float sentinel(vec2 p) {
    p.x = abs(p.x);                                         // symmetric
    float d = sdBox(p - vec2(0.0, 0.33), vec2(0.40, 0.055));
    d = min(d, sdSeg(p, vec2(0.38, 0.33), vec2(0.52, 0.42), 0.035));     // swept wing tip
    d = min(d, sdBox(p - vec2(0.0, 0.42), vec2(0.11, 0.05)));           // cockpit
    d = min(d, sdSeg(p, vec2(0.0, 0.28), vec2(0.0, 0.16), 0.03));        // keel
    d = min(d, sdSeg(p, vec2(0.36, 0.29), vec2(0.30, -0.42), 0.045));    // leg
    d = min(d, sdBox(p - vec2(0.30, -0.45), vec2(0.07, 0.025)));        // foot
    return d;
}

float hash(float n) { return fract(sin(n) * 43758.5453); }

void main() {
    vec2 uv = qt_TexCoord0;
    float aspect = size.x / size.y;
    vec3 c = vec3(0.0);
    float horizon = 0.62;

    // grid floor
    float dh = uv.y - horizon;
    c += color.rgb * exp(-abs(dh) * (dh < 0.0 ? 50.0 : 22.0)) * 0.55;
    if (dh > 0.0) {
        float z = 0.12 / dh;
        float x = (uv.x - 0.5) * aspect * z;
        vec2 g = abs(fract(vec2(x * 2.0, z * 2.0 - time * 1.4) - 0.5) - 0.5) / fwidth(vec2(x * 2.0, z * 2.0));
        float grid = 1.0 - clamp(min(g.x, g.y) - 0.2, 0.0, 1.0);
        c += color.rgb * grid * exp(-z * 0.08) * 0.35;
    }

    // three Sentinels on staggered patrols: each comes in from the far haze,
    // grows as it nears, drifts across, and leaves the frame
    vec2 sp = vec2((uv.x - 0.5) * aspect, horizon - uv.y);   // screen space, y up from the horizon
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float period = 16.0 + 4.0 * fi;
        float t = fract((time + fi * 7.3) / period);         // 0..1 along its patrol
        float side = hash(fi + floor((time + fi * 7.3) / period)) * 2.0 - 1.0;
        float depth = mix(9.0, 1.1, t);                       // far -> near
        float scale = 0.55 / depth;
        vec2 pos = vec2(side * 0.9 * aspect * (1.0 - t * 0.4) + sin(time * 0.3 + fi) * 0.08,
                        0.12 + 0.30 / depth + 0.01 * sin(time * 1.7 + fi * 2.0));
        vec2 lp = (sp - pos) / scale;
        float d = sentinel(lp) * scale;                     // distance in screen units
        float edge = exp(-abs(d) * size.y * 0.9);             // crisp wireframe line
        float halo = exp(-max(d, 0.0) * size.y * 0.06) * 0.25;
        float fill = d < 0.0 ? 0.12 : 0.0;
        float fadeIn = smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.88, 1.0, t));
        vec3 hot = mix(alert.rgb, vec3(1.0), 0.3);
        c += (hot * edge + alert.rgb * (halo + fill)) * fadeIn;

        // search beam: a soft cone from the cockpit down to the floor
        vec2 bp = sp - (pos + vec2(0.0, 0.16 * scale));
        float cone = (bp.y < 0.0) ? exp(-abs(bp.x) / max(-bp.y * 0.35 + 0.004, 1e-3) * 1.6) : 0.0;
        c += alert.rgb * cone * 0.10 * fadeIn * step(-(pos.y + 0.02), bp.y);
    }

    fragColor = vec4(c, 1.0) * qt_Opacity;
}
