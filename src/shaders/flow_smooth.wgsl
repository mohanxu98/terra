@group(0) @binding(0) var accumTex         : texture_2d<f32>;
@group(0) @binding(1) var smoothedAccumTex : texture_storage_2d<r32float, write>;

fn w1d(d: i32) -> f32 {
    if (d == 0)      { return 6.0 / 16.0; }
    if (abs(d) == 1) { return 4.0 / 16.0; }
    return 1.0 / 16.0;
}

@compute @workgroup_size(8, 8)
fn smooth_flow(@builtin(global_invocation_id) gid: vec3u) {
    let coord = vec2i(gid.xy);
    let size  = vec2i(textureDimensions(accumTex));
    if (coord.x >= size.x || coord.y >= size.y) { return; }

    var total = 0.0;
    for (var dy = -2; dy <= 2; dy++) {
        for (var dx = -2; dx <= 2; dx++) {
            let nc = clamp(coord + vec2i(dx, dy), vec2i(0), size - 1);
            total += textureLoad(accumTex, nc, 0).r * w1d(dx) * w1d(dy);
        }
    }

    textureStore(smoothedAccumTex, coord, vec4f(total, 0.0, 0.0, 0.0));
}
