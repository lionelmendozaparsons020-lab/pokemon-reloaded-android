// Pokemon Reloaded Android: pixel-accurate GLES 3.0 sun/atmosphere shader.
// Roof/tree/building shadows are drawn in world space by game/draw.rs, NOT
// synthesised from colour blurring. No HDR, no depth map, no ray tracing.
in vec2 v_uv;
out vec4 out_colour;
uniform sampler2D u_scene;
uniform vec2 u_texel;
uniform float u_time;
uniform int u_quality;
uniform vec2 u_sun_dir;
uniform float u_shadow_strength;

vec4 pixel(vec2 uv) {
    // Nearest-neighbour fetch avoids the blurring that broke previous builds.
    ivec2 size = textureSize(u_scene, 0);
    ivec2 xy = clamp(ivec2(floor(clamp(uv, vec2(0.0), vec2(0.999999)) *
                                   vec2(size))), ivec2(0), size - ivec2(1));
    return texelFetch(u_scene, xy, 0);
}
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
float brightness(vec2 uv) { return luma(pixel(uv).rgb); }
float luminous(vec2 uv) {
    vec3 rgb = pixel(uv).rgb;
    float lum = luma(rgb);
    float max_channel = max(rgb.r, max(rgb.g, rgb.b));
    // Only truly bright light sources; ordinary pastel tiles must not glow.
    return smoothstep(0.78, 0.97, lum) * smoothstep(0.78, 0.98, max_channel);
}
void main() {
    vec2 uv = clamp(v_uv, vec2(0.0), vec2(0.999999));
    vec3 src = pixel(uv).rgb;
    float original = luma(src);
    float scene_light =
        (brightness(vec2(0.18, 0.19)) + brightness(vec2(0.82, 0.19)) +
         brightness(vec2(0.50, 0.50)) + brightness(vec2(0.18, 0.81)) +
         brightness(vec2(0.82, 0.81))) * 0.2;
    // Respect the game's own ambient darkness; do not turn nights purple.
    float night = 1.0 - smoothstep(0.14, 0.47, scene_light);
    float sunlight = 1.0 - night;
    float strength = clamp(u_shadow_strength, 0.0, 1.0);
    vec2 dir = normalize(u_sun_dir + vec2(0.00001, 0.00001));
    // A tiny 4-neighbour normal estimate for pixel-art surfaces.
    // It is contrast-aware, has no Gaussian blur, and stays sharp on sprites.
    float nl = brightness(uv - vec2(u_texel.x, 0.0));
    float nr = brightness(uv + vec2(u_texel.x, 0.0));
    float nt = brightness(uv - vec2(0.0, u_texel.y));
    float nb = brightness(uv + vec2(0.0, u_texel.y));
    vec2 slope = vec2(nl - nr, nt - nb);
    float facing = clamp(dot(slope, -dir), -0.34, 0.34);
    float relief = (u_quality >= 2 ? 0.20 : 0.09) * facing * sunlight * strength;

    // A physically motivated but *stylised* day tint: sunlight warms highlights
    // and a subdued cool ambient keeps dark areas readable.
    vec3 daylight = src * vec3(1.025, 1.009, 0.983);
    vec3 nocturnal = src * vec3(0.98, 0.995, 1.01);
    vec3 col = mix(daylight, nocturnal, night);
    col *= 1.0 + relief;

    // Crisp one-pixel contact occlusion at hard roof/wall borders. This does
    // not pretend to identify geometry; object shadows are handled separately.
    float gradient = abs(nl - nr) + abs(nt - nb);
    float contact = smoothstep(0.18, 0.75, gradient) *
                    max(0.0, -facing) * (u_quality >= 2 ? 0.17 : 0.07);
    col *= 1.0 - contact * strength * sunlight;

    // Selective small light-source halo at premium preset only.
    // It never replaces the original pixel with a blurred neighbour.
    if (u_quality >= 2) {
        float halo =
            luminous(uv + u_texel * vec2(-2.0, 0.0)) +
            luminous(uv + u_texel * vec2( 2.0, 0.0)) +
            luminous(uv + u_texel * vec2(0.0, -2.0)) +
            luminous(uv + u_texel * vec2(0.0,  2.0));
        vec3 warmth = mix(vec3(1.0, 0.84, 0.64), vec3(0.68, 0.80, 1.0), night);
        col += halo * 0.018 * warmth;
    }
    out_colour = vec4(clamp(col, 0.0, 1.0), 1.0);
}
