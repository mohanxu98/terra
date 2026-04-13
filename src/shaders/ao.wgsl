const HEIGHT_SCALE : f32 = 600.0;
const SPACING      : f32 = 4096.0 / 511.0;
const SIZE         : i32 = 512;
const RADIUS       : i32 = 20;
const HALF_PI      : f32 = 1.5707963;

@group(0) @binding(0) var heightTex : texture_2d<f32>;
@group(0) @binding(1) var aoTex     : texture_storage_2d<rgba16float, write>;

fn loadH(coord: vec2i) -> f32 {
    return textureLoad(heightTex, clamp(coord, vec2i(0), vec2i(SIZE - 1)), 0).r * HEIGHT_SCALE;
}

@compute @workgroup_size(8, 8)
fn build_ao(@builtin(global_invocation_id) id: vec3u) {
    let coord = vec2i(id.xy);
    if (coord.x >= SIZE || coord.y >= SIZE) { return; }

    let h_self = loadH(coord);

    let dirs = array<vec2f, 8>(
        vec2f( 1.0,      0.0     ),
        vec2f( 0.707107, 0.707107),
        vec2f( 0.0,      1.0     ),
        vec2f(-0.707107, 0.707107),
        vec2f(-1.0,      0.0     ),
        vec2f(-0.707107,-0.707107),
        vec2f( 0.0,     -1.0     ),
        vec2f( 0.707107,-0.707107),
    );

    var occlusion : f32 = 0.0;

    for (var d = 0; d < 8; d++) {
        var max_tan : f32 = -1e9;

        for (var r = 1; r <= RADIUS; r++) {
            let nc = coord + vec2i(
                i32(round(dirs[d].x * f32(r))),
                i32(round(dirs[d].y * f32(r))),
            );
            let h_n  = loadH(nc);
            let dh   = h_n - h_self;
            let dist = f32(r) * length(dirs[d]) * SPACING;
            max_tan  = max(max_tan, dh / dist);
        }

        let angle = atan(max_tan);
        occlusion += clamp(angle / HALF_PI, 0.0, 1.0);
    }

    occlusion /= 8.0;
    let ao_factor = clamp(1.0 - occlusion, 0.0, 1.0);

    textureStore(aoTex, coord, vec4f(ao_factor, 0.0, 0.0, 1.0));
}
