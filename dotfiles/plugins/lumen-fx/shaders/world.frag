#version 440
// Lumen Grid world: a live 3D wallpaper. The camera glides forward over an endless,
// reflective grid floor; light cycles race along the lanes trailing tall light walls
// (reflected in the floor); a jagged mountain range glows on the horizon under a hazy
// sky with drifting particles. Everything is drawn in the theme color.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float load;       // 0..1 CPU load: travel speed and pulse
    float agent;      // 0 idle, 1 Claude working, 2 Claude waiting
    float horizon;    // unused (kept for the plugin's bindings)
    vec2 size;
    vec4 color;       // theme accent
    vec4 alert;       // unused
    float surge;      // extra distance travelled (workspace switches make the camera surge)
    float music;      // 0..1 audio output level: the Grid pulses with music
};

float hash(float n) { return fract(sin(n) * 43758.5453); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(float x) { float i = floor(x), f = fract(x); return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f)); }

// grid line intensity for a coordinate, antialiased, with a soft glow
float gridLine(float v, float width) {
    float d = abs(fract(v - 0.5) - 0.5);
    float w = fwidth(v);
    return smoothstep(width + w, width, d) + 0.35 * exp(-d / max(w * 6.0, 1e-4));
}

// Light cycles: each rides a lane (x), heading away from the camera (+z) at its own
// speed; it leaves a wall of light behind it. Returns head z for cycle i.
float cycleLane(int i) { return float(i * 2 - 2) * 3.0 + (i == 1 ? 1.0 : 0.0); }
float cycleHead(int i, float travel) {
    float speed = 1.0 + 0.45 * float(i);          // relative to the camera (slow drift)
    float loop = 70.0;
    return travel + 6.0 + mod(time * speed + float(i) * 23.0, loop);
}
const float WALL_H = 0.55;
const float TRAIL = 26.0;

// intersect a ray with the light walls; returns glow (0 if missed), writes hit distance
float walls(vec3 ro, vec3 rd, float travel, out float tHit) {
    tHit = 1e9;
    float glow = 0.0;
    for (int i = 0; i < 3; i++) {
        float lane = cycleLane(i);
        if (abs(rd.x) < 1e-4) continue;
        float t = (lane - ro.x) / rd.x;
        if (t <= 0.0) continue;
        vec3 p = ro + rd * t;
        float head = cycleHead(i, travel);
        float behind = head - p.z;                       // 0 at the head, grows along the trail
        if (p.y < 0.0 || p.y > WALL_H || behind < 0.0 || behind > TRAIL) continue;
        float fadeTail = 1.0 - behind / TRAIL;
        float body = 0.22 + 0.25 * (p.y / WALL_H);                       // translucent sheet, brighter up top
        float top = exp(-(WALL_H - p.y) * 60.0);                          // hot top edge
        float g = (body + 1.4 * top) * (0.25 + 0.75 * fadeTail) + 3.0 * exp(-behind * 2.5);  // bright head
        if (t < tHit) { tHit = t; glow = g; }
    }
    return glow;
}

void main() {
    vec2 uv = (qt_TexCoord0 * size - 0.5 * size) / size.y;   // centered, y down
    uv.y = -uv.y;
    vec3 tint = color.rgb;
    vec3 hot = mix(tint, vec3(1.0), 0.45);

    float speed = 0.55 + 0.35 * load;              // slow, calm glide
    float travel = time * speed + surge;
    float busy = agent > 0.5 ? 1.0 : 0.0;
    float waiting = agent > 1.5 ? 1.0 : 0.0;
    float beat = 0.5 + 0.5 * sin(time * (0.7 + 2.0 * waiting));
    float m = clamp(music, 0.0, 1.0);

    // camera: low over the floor, gliding forward with a gentle sway
    vec3 ro = vec3(0.6 * sin(time * 0.04), 1.05 + 0.08 * sin(time * 0.06), travel);
    vec3 fw = normalize(vec3(0.05 * sin(time * 0.025), -0.16, 1.0));
    vec3 rt = normalize(cross(vec3(0.0, 1.0, 0.0), fw));
    vec3 up = cross(fw, rt);
    vec3 rd = normalize(fw * 1.35 + rt * uv.x + up * uv.y);

    vec3 col = vec3(0.0);

    // ---- sky ----
    float horizonY = -fw.y / max(1e-3, length(fw.xz)) * 0.0;   // horizon sits where rd.y == 0
    float h = rd.y;
    vec3 sky = mix(vec3(0.012, 0.016, 0.02), vec3(0.0), smoothstep(0.0, 0.5, h));
    sky += tint * 0.08 * exp(-max(h, 0.0) * 9.0);                 // haze over the horizon
    // drifting particles
    vec2 sp = vec2(atan(rd.x, rd.z) * 60.0, h * 60.0 + time * 0.3);
    vec2 cell = floor(sp);
    float star = step(0.985, hash2(cell)) * smoothstep(0.35, 0.0, length(fract(sp) - 0.5));
    sky += tint * star * 0.5 * smoothstep(0.0, 0.08, h);

    // mountains: a jagged ridge line just above the horizon, with glowing crests
    float az = atan(rd.x, rd.z) * 3.0;
    float ridge = 0.035 + 0.05 * noise(az * 2.0 + 10.0) + 0.025 * noise(az * 7.0) + 0.01 * noise(az * 23.0);
    if (h > 0.0 && h < ridge) {
        sky = vec3(0.006, 0.008, 0.01);
        float crest = exp(-(ridge - h) * 260.0);
        sky += tint * (0.12 + 0.5 * crest) * (0.6 + 0.4 * noise(az * 13.0 + time * 0.2));
    }
    col = sky;

    // ---- floor ----
    float tWall;
    float wallGlow = walls(ro, rd, travel, tWall);
    if (rd.y < 0.0) {
        float t = -ro.y / rd.y;
        vec3 p = ro + rd * t;
        float fog = exp(-t * 0.028);
        float g = max(gridLine(p.x * 0.5, 0.012), gridLine(p.z * 0.5, 0.012));
        float pulse = 0.65 + 0.35 * beat * (0.4 + load + waiting) + 0.9 * m;
        vec3 floorCol = vec3(0.006, 0.008, 0.01) + tint * g * 0.6 * pulse;
        // reflections: the horizon glow and the light walls, mirrored in the glossy floor
        vec3 rr = vec3(rd.x, -rd.y, rd.z);
        float refl = exp(-abs(rr.y) * 14.0) * 0.25;
        float tR;
        float wallRefl = walls(p + vec3(0.0, 0.001, 0.0), rr, travel, tR);
        floorCol += tint * refl + hot * wallRefl * 0.35 * exp(-tR * 0.03);
        col = mix(col, floorCol, fog) + tint * (1.0 - fog) * 0.05;
        if (wallGlow > 0.0 && tWall < t) col += hot * wallGlow * exp(-tWall * 0.012) * (1.0 + 1.2 * m);
    } else if (wallGlow > 0.0) {
        col += hot * wallGlow * exp(-tWall * 0.012) * (1.0 + 1.2 * m);
    }

    // horizon line glow (brighter while Claude works, pulsing while it waits)
    col += tint * exp(-abs(h) * (70.0 - 40.0 * m)) * (0.25 + 0.25 * busy + 0.25 * beat * waiting + 1.1 * m);
    // music also lifts the mountain crests a little
    col += tint * 0.12 * m * exp(-abs(h - 0.05) * 30.0) * step(0.0, h);

    // vignette and a whisper of scanlines
    vec2 q = qt_TexCoord0;
    col *= 0.55 + 0.45 * pow(16.0 * q.x * q.y * (1.0 - q.x) * (1.0 - q.y), 0.25);
    col *= 0.97 + 0.03 * sin(qt_TexCoord0.y * size.y * 1.6);

    fragColor = vec4(col, 1.0) * qt_Opacity;
}
