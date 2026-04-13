const HEIGHT_SCALE : f32 = 600.0;
const SPACING      : f32 = 4096.0 / 511.0;
const SIZE         : i32 = 512;

@group(0) @binding(0) var heightTex : texture_2d<f32>;
@group(0) @binding(1) var normalTex : texture_storage_2d<rgba16float, write>;

@compute @workgroup_size(8, 8)
fn build_normals(@builtin(global_invocation_id) id: vec3u) {
    let coord = vec2i(id.xy);
    if (coord.x >= SIZE || coord.y >= SIZE) { return; }

    let cs = vec2i(SIZE - 1);

    let hTL = textureLoad(heightTex, clamp(coord + vec2i(-1, -1), vec2i(0), cs), 0).r * HEIGHT_SCALE;
    let hT  = textureLoad(heightTex, clamp(coord + vec2i( 0, -1), vec2i(0), cs), 0).r * HEIGHT_SCALE;
    let hTR = textureLoad(heightTex, clamp(coord + vec2i( 1, -1), vec2i(0), cs), 0).r * HEIGHT_SCALE;
    let hL  = textureLoad(heightTex, clamp(coord + vec2i(-1,  0), vec2i(0), cs), 0).r * HEIGHT_SCALE;
    let hR  = textureLoad(heightTex, clamp(coord + vec2i( 1,  0), vec2i(0), cs), 0).r * HEIGHT_SCALE;
    let hBL = textureLoad(heightTex, clamp(coord + vec2i(-1,  1), vec2i(0), cs), 0).r * HEIGHT_SCALE;
    let hB  = textureLoad(heightTex, clamp(coord + vec2i( 0,  1), vec2i(0), cs), 0).r * HEIGHT_SCALE;
    let hBR = textureLoad(heightTex, clamp(coord + vec2i( 1,  1), vec2i(0), cs), 0).r * HEIGHT_SCALE;

    let Gx = (hTR + 2.0 * hR + hBR) - (hTL + 2.0 * hL + hBL);
    let Gz = (hBL + 2.0 * hB + hBR) - (hTL + 2.0 * hT + hTR);

    let n = normalize(vec3f(-Gx, 8.0 * SPACING, -Gz));

    textureStore(normalTex, coord, vec4f(n * 0.5 + 0.5, 1.0));
}
