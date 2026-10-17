#version 440
// Lumen derez / rez, drawn over a window's rectangle.
//   mode 0 (derez, on close): the window breaks into glowing cells that flare and die in random order
//   mode 1 (rez, on open):    a light scan sweeps down, leaving a wireframe grid that fades as the window settles
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;   // 0..1
    float mode;
    float cell;       // cell size in px
    float seed;
    vec2 size;        // rect size in px
    vec4 color;
    vec4 hole;        // desktop background color: what a dead cell leaves behind
};

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21) + seed);
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void main() {
    vec2 px = qt_TexCoord0 * size;
    vec2 id = floor(px / cell);
    vec2 f = fract(px / cell);
    float r = hash(id);
    // thin gaps between cells read as voxels
    float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)) * cell;
    float gap = smoothstep(0.0, 1.2, edge);
    float rim = 1.0 - smoothstep(0.0, 1.5, min(min(px.x, size.x - px.x), min(px.y, size.y - px.y)));
    vec3 hot = mix(color.rgb, vec3(1.0), 0.55);
    float a = 0.0;
    vec3 c = color.rgb;

    if (mode < 0.5) {
        // The window itself is still on screen (Hyprland fades it out underneath, in step).
        // Each cell dies at its own moment, top rows a little earlier: it flares, then
        // turns into a hole, so the window is eaten away cell by cell.
        float die = 0.02 + 0.5 * (0.75 * r + 0.25 * (1.0 - qt_TexCoord0.y));
        float t = progress - die;
        if (t < 0.0) {
            a = 0.3 * rim * (1.0 - progress);                           // intact: just a lit edge
        } else {
            float flare = exp(-t * 12.0) * gap;
            float holeA = (1.0 - exp(-t * 12.0)) * (1.0 - smoothstep(0.55, 0.8, progress));  // gone before the window is
            a = flare + holeA * (1.0 - flare);
            c = (hot * flare + hole.rgb * holeA * (1.0 - flare)) / max(a, 1e-4);
        }
    } else {
        float scan = progress * 1.25;                  // scan line position (0 top .. 1 bottom), overshoots to finish
        float y = qt_TexCoord0.y;
        float behind = scan - y;
        float lineGrid = 1.0 - smoothstep(0.0, 1.0, edge);  // cell borders only
        if (behind >= 0.0) {
            float fade = exp(-behind * 5.0) * (1.0 - smoothstep(0.75, 1.0, progress));
            a = lineGrid * 0.6 * fade + (r > 0.93 ? 0.35 * fade : 0.0);
        }
        float beam = exp(-abs(behind) * size.y * 0.35);  // the bright scan line itself
        a = max(a, beam * (1.0 - smoothstep(0.8, 1.0, progress)));
        c = mix(color.rgb, hot, beam);
        a = max(a, rim * 0.8 * (1.0 - progress));
    }
    fragColor = vec4(c * a, a) * qt_Opacity;
}
