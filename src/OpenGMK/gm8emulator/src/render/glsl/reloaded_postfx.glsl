// Pokemon Reloaded Android: mobile GLES 3.0 postprocessing.
// Screen-space approximation; does not create true object-cast shadows.
in vec2 v_uv;
out vec4 out_colour;
uniform sampler2D u_scene;
uniform vec2 u_texel;
uniform float u_time;
uniform int u_quality;
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
vec3 highlight(vec2 uv) {
    vec3 c = texture(u_scene, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
    float strength = smoothstep(0.61, 0.93, luma(c));
    return max(c - vec3(0.53), vec3(0.0)) * strength;
}
void main() {
    vec2 uv = clamp(v_uv, vec2(0.0), vec2(1.0));
    vec4 src = texture(u_scene, uv);
    float scene_light = (
        luma(texture(u_scene, vec2(0.18, 0.19)).rgb) +
        luma(texture(u_scene, vec2(0.82, 0.19)).rgb) +
        luma(texture(u_scene, vec2(0.50, 0.50)).rgb) +
        luma(texture(u_scene, vec2(0.18, 0.81)).rgb) +
        luma(texture(u_scene, vec2(0.82, 0.81)).rgb)
    ) * 0.2;
    float night = 1.0 - smoothstep(0.18, 0.60, scene_light);
    vec3 grade_day = src.rgb * vec3(1.038, 1.013, 0.988);
    vec3 grade_night = src.rgb * vec3(0.925, 0.972, 1.056);
    vec3 col = mix(grade_day, grade_night, night);
    float upper = luma(texture(u_scene, uv + vec2(0.0, 2.0) * u_texel).rgb);
    float side = luma(texture(u_scene, uv + vec2(1.7, 0.0) * u_texel).rgb);
    float contact = clamp((upper - luma(src.rgb)) * 0.29 + (side - luma(src.rgb)) * 0.10, 0.0, 0.13);
    col *= 1.0 - contact * (u_quality == 1 ? 0.55 : 1.0);
    vec3 glow = highlight(uv) * 0.23;
    glow += highlight(uv + u_texel * vec2(2.0, 0.0)) * 0.16;
    glow += highlight(uv - u_texel * vec2(2.0, 0.0)) * 0.16;
    glow += highlight(uv + u_texel * vec2(0.0, 2.0)) * 0.16;
    glow += highlight(uv - u_texel * vec2(0.0, 2.0)) * 0.16;
    if (u_quality >= 2) {
        glow += highlight(uv + u_texel * vec2(5.0, 5.0)) * 0.08;
        glow += highlight(uv + u_texel * vec2(-5.0, 5.0)) * 0.08;
        glow += highlight(uv + u_texel * vec2(5.0, -5.0)) * 0.08;
        glow += highlight(uv + u_texel * vec2(-5.0, -5.0)) * 0.08;
        glow += highlight(uv + u_texel * vec2(9.0, 0.0)) * 0.045;
        glow += highlight(uv - u_texel * vec2(9.0, 0.0)) * 0.045;
    }
    col += glow * (u_quality == 1 ? 0.13 : 0.19);
    if (u_quality >= 2) {
        vec2 sun = vec2(0.03, 1.09);
        float beams = 0.0;
        for (int i = 1; i <= 4; ++i) {
            float t = float(i) * 0.13;
            beams += luma(highlight(mix(uv, sun, t))) * (1.0 - t);
        }
        float fluctuation = 0.97 + 0.03 * sin(u_time * 0.31);
        col += vec3(1.0, 0.81, 0.55) * min(beams, 0.30) * 0.11 * (1.0 - night) * fluctuation;
    }
    col = clamp((col - 0.5) * 1.024 + 0.5, vec3(0.0), vec3(1.0));
    out_colour = vec4(col, 1.0);
}
