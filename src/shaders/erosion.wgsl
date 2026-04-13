const K           : f32 = 0.00005;
const K_VAR       : f32 = 0.0;
const STRATA_FREQ : f32 = 30.0;
const M           : f32 = 0.65;
const DT          : f32 = 1.0;

const KT          : f32 = 0.010;
const DEPO_RATE   : f32 = 0.08;
const TRANS_ALPHA : f32 = 0.50;

const KT_ZONE1    : f32 = 0.025;
const KT_ZONE2    : f32 = 0.010;
const KT_ZONE3    : f32 = 0.012;

const UPLIFT_RATE : f32 = 0.0003;

const SQRT2       : f32 = 1.41421356;
const SIZE        : i32 = 512;

@group(0) @binding(0) var heightTex : texture_storage_2d<r32float, read_write>;
@group(0) @binding(1) var sedTex    : texture_storage_2d<r32float, read_write>;
@group(0) @binding(2) var accumTex  : texture_storage_2d<r32float, read_write>;
@group(0) @binding(3) var<storage, read_write> flowBuf : array<f32>;

fn inBounds(c: vec2i) -> bool {
    return c.x >= 0 && c.x < SIZE && c.y >= 0 && c.y < SIZE;
}

fn totalH(c: vec2i) -> f32 {
    return textureLoad(heightTex, c).r + textureLoad(sedTex, c).r;
}

fn d8Off(i: i32) -> vec2i {
    if (i == 0) { return vec2i(-1,  0); }
    if (i == 1) { return vec2i( 1,  0); }
    if (i == 2) { return vec2i( 0, -1); }
    if (i == 3) { return vec2i( 0,  1); }
    if (i == 4) { return vec2i(-1, -1); }
    if (i == 5) { return vec2i( 1, -1); }
    if (i == 6) { return vec2i(-1,  1); }
    return            vec2i( 1,  1);
}

fn d8Dist(i: i32) -> f32 {
    if (i >= 4) { return SQRT2; }
    return 1.0;
}

fn d8Rev(i: i32) -> i32 {
    if (i == 0) { return 1; }
    if (i == 1) { return 0; }
    if (i == 2) { return 3; }
    if (i == 3) { return 2; }
    if (i == 4) { return 7; }
    if (i == 5) { return 6; }
    if (i == 6) { return 5; }
    return 4;
}

fn getMFDFrac(coord: vec2i, dir: i32) -> f32 {
    return flowBuf[(coord.y * SIZE + coord.x) * 8 + dir];
}

fn getPrimaryDir(coord: vec2i) -> i32 {
    let base = (coord.y * SIZE + coord.x) * 8;
    var best : f32 = 0.0;
    var dir  : i32 = 8;
    for (var i = 0; i < 8; i++) {
        let f = flowBuf[base + i];
        if (f > best) { best = f; dir = i; }
    }
    return dir;
}

fn strataK(b: f32) -> f32 {
    return K + K_VAR * sin(b * STRATA_FREQ);
}

fn islandMask(coord: vec2i) -> f32 {
    let cx   = f32(SIZE) * 0.5;
    let cy   = f32(SIZE) * 0.5;
    let dx   = f32(coord.x) - cx;
    let dy   = f32(coord.y) - cy;
    let maxD = cx * SQRT2;
    let dist = sqrt(dx * dx + dy * dy) / maxD;
    let f    = 1.0 - pow(max(0.0, dist * 1.2 - 0.1), 1.3);
    return max(0.0, f);
}

@compute @workgroup_size(8, 8)
fn mfd_direction(@builtin(global_invocation_id) id: vec3u) {
    let coord  = vec2i(id.xy);
    if (coord.x >= SIZE || coord.y >= SIZE) { return; }

    let h_self = totalH(coord);
    var d      : array<f32, 8>;
    var sum    = 0.0;

    for (var i = 0; i < 8; i++) {
        let nc = coord + d8Off(i);
        if (!inBounds(nc)) { continue; }
        let slope = (h_self - totalH(nc)) / d8Dist(i);
        if (slope > 0.0) {
            d[i]  = slope;
            sum  += slope;
        }
    }

    if (sum < 1e-7) {
        var best_slope : f32 = -1e9;
        var best_i     : i32 = 0;
        for (var i = 0; i < 8; i++) {
            let nc = coord + d8Off(i);
            if (!inBounds(nc)) { continue; }
            let slope = (h_self - totalH(nc)) / d8Dist(i);
            if (slope > best_slope) { best_slope = slope; best_i = i; }
        }
        d[best_i] = 1.0;
        sum       = 1.0;
    }

    let inv  = 1.0 / sum;
    let base = (coord.y * SIZE + coord.x) * 8;
    for (var i = 0; i < 8; i++) {
        flowBuf[base + i] = d[i] * inv;
    }
}

@compute @workgroup_size(8, 8)
fn accum_init(@builtin(global_invocation_id) id: vec3u) {
    let coord = vec2i(id.xy);
    if (coord.x >= SIZE || coord.y >= SIZE) { return; }
    textureStore(accumTex, coord, vec4f(1.0, 0.0, 0.0, 0.0));
}

@compute @workgroup_size(8, 8)
fn flow_accumulate(@builtin(global_invocation_id) id: vec3u) {
    let coord = vec2i(id.xy);
    if (coord.x >= SIZE || coord.y >= SIZE) { return; }

    var total = 1.0;
    for (var i = 0; i < 8; i++) {
        let nc = coord + d8Off(i);
        if (!inBounds(nc)) { continue; }
        let frac = getMFDFrac(nc, d8Rev(i));
        total   += textureLoad(accumTex, nc).r * frac;
    }
    textureStore(accumTex, coord, vec4f(total, 0.0, 0.0, 0.0));
}

@compute @workgroup_size(8, 8)
fn spe_erode(@builtin(global_invocation_id) id: vec3u) {
    let coord  = vec2i(id.xy);
    if (coord.x >= SIZE || coord.y >= SIZE) { return; }

    let dir_i = getPrimaryDir(coord);
    if (dir_i == 8) { return; }

    let receiver = coord + d8Off(dir_i);
    if (!inBounds(receiver)) { return; }

    let h_self = totalH(coord);
    let b_self = textureLoad(heightTex, coord).r;
    let h_recv = totalH(receiver);
    let A      = textureLoad(accumTex, coord).r;
    let dist   = d8Dist(dir_i);

    let k_local  = strataK(b_self);
    let factor   = DT * k_local * pow(A, M) / dist;
    let h_new    = (h_self + factor * h_recv) / (1.0 + factor);
    let erosion  = max(0.0, h_self - h_new);
    let detached = min(erosion, b_self);

    let s_self = textureLoad(sedTex, coord).r;
    textureStore(heightTex, coord, vec4f(max(0.0, b_self - detached), 0.0, 0.0, 0.0));
    textureStore(sedTex,    coord, vec4f(s_self + detached,           0.0, 0.0, 0.0));
}

@compute @workgroup_size(8, 8)
fn sed_transport(@builtin(global_invocation_id) id: vec3u) {
    let coord  = vec2i(id.xy);
    if (coord.x >= SIZE || coord.y >= SIZE) { return; }

    let s_self = textureLoad(sedTex, coord).r;

    let base = (coord.y * SIZE + coord.x) * 8;
    var out_sum : f32 = 0.0;
    for (var i = 0; i < 8; i++) { out_sum += flowBuf[base + i]; }
    let outgoing = s_self * TRANS_ALPHA * min(out_sum, 1.0);

    var incoming : f32 = 0.0;
    for (var i = 0; i < 8; i++) {
        let nc = coord + d8Off(i);
        if (!inBounds(nc)) { continue; }
        let frac  = getMFDFrac(nc, d8Rev(i));
        incoming += textureLoad(sedTex, nc).r * TRANS_ALPHA * frac;
    }

    textureStore(sedTex, coord, vec4f(max(0.0, s_self - outgoing + incoming), 0.0, 0.0, 0.0));
}

@compute @workgroup_size(8, 8)
fn sed_deposit(@builtin(global_invocation_id) id: vec3u) {
    let coord  = vec2i(id.xy);
    if (coord.x >= SIZE || coord.y >= SIZE) { return; }

    let s_self = textureLoad(sedTex,    coord).r;
    let b_self = textureLoad(heightTex, coord).r;
    if (s_self < 0.0001) { return; }

    let h_self = b_self + s_self;
    let A      = textureLoad(accumTex, coord).r;

    var slope_sum : f32 = 0.0;
    var slope_cnt : f32 = 0.0;
    for (var i = 0; i < 4; i++) {
        let nc = coord + d8Off(i);
        if (!inBounds(nc)) { continue; }
        let dh = h_self - totalH(nc);
        if (dh > 0.0) { slope_sum += dh; slope_cnt += 1.0; }
    }
    let avg_slope = select(0.0, slope_sum / slope_cnt, slope_cnt > 0.0);

    let tc      = KT * pow(A, M) * avg_slope;
    let excess  = max(0.0, s_self - tc);
    let deposit = DEPO_RATE * excess;

    textureStore(heightTex, coord, vec4f(b_self + deposit,           0.0, 0.0, 0.0));
    textureStore(sedTex,    coord, vec4f(max(0.0, s_self - deposit), 0.0, 0.0, 0.0));
}

@compute @workgroup_size(8, 8)
fn uplift_bedrock(@builtin(global_invocation_id) id: vec3u) {
    let coord = vec2i(id.xy);
    if (coord.x >= SIZE || coord.y >= SIZE) { return; }
    let b    = textureLoad(heightTex, coord).r;
    let mask = islandMask(coord);
    textureStore(heightTex, coord, vec4f(min(1.0, b + UPLIFT_RATE * mask), 0.0, 0.0, 0.0));
}

@compute @workgroup_size(8, 8)
fn thermal_zone1(@builtin(global_invocation_id) id: vec3u) {
    let coord  = vec2i(id.xy);
    if (coord.x >= SIZE || coord.y >= SIZE) { return; }
    let h_self = totalH(coord);
    if (h_self >= 0.2) { return; }
    let b_self = textureLoad(heightTex, coord).r;
    let dirs   = array<vec2i, 4>(vec2i(-1,0), vec2i(1,0), vec2i(0,-1), vec2i(0,1));
    var transfer : f32 = 0.0;
    for (var i = 0; i < 4; i++) {
        let nc = coord + dirs[i];
        if (!inBounds(nc)) { continue; }
        let diff = h_self - totalH(nc);
        if (diff > KT_ZONE1) { transfer += 0.2 * (diff - KT_ZONE1); }
    }
    if (transfer > 0.0) {
        textureStore(heightTex, coord, vec4f(max(0.0, b_self - transfer), 0.0, 0.0, 0.0));
    }
}

@compute @workgroup_size(8, 8)
fn thermal_zone2(@builtin(global_invocation_id) id: vec3u) {
    let coord  = vec2i(id.xy);
    if (coord.x >= SIZE || coord.y >= SIZE) { return; }
    let h_self = totalH(coord);
    if (h_self < 0.2 || h_self >= 0.5) { return; }
    let b_self = textureLoad(heightTex, coord).r;
    let dirs   = array<vec2i, 4>(vec2i(-1,0), vec2i(1,0), vec2i(0,-1), vec2i(0,1));
    var transfer : f32 = 0.0;
    for (var i = 0; i < 4; i++) {
        let nc = coord + dirs[i];
        if (!inBounds(nc)) { continue; }
        let diff = h_self - totalH(nc);
        if (diff > KT_ZONE2) { transfer += 0.1 * (diff - KT_ZONE2); }
    }
    if (transfer > 0.0) {
        textureStore(heightTex, coord, vec4f(max(0.0, b_self - transfer), 0.0, 0.0, 0.0));
    }
}

@compute @workgroup_size(8, 8)
fn thermal_zone3(@builtin(global_invocation_id) id: vec3u) {
    let coord  = vec2i(id.xy);
    if (coord.x >= SIZE || coord.y >= SIZE) { return; }
    let h_self = totalH(coord);
    if (h_self < 0.5 || h_self >= 0.72) { return; }
    let b_self = textureLoad(heightTex, coord).r;
    let dirs   = array<vec2i, 4>(vec2i(-1,0), vec2i(1,0), vec2i(0,-1), vec2i(0,1));
    var transfer : f32 = 0.0;
    for (var i = 0; i < 4; i++) {
        let nc = coord + dirs[i];
        if (!inBounds(nc)) { continue; }
        let diff = h_self - totalH(nc);
        if (diff > KT_ZONE3) { transfer += 0.12 * (diff - KT_ZONE3); }
    }
    if (transfer > 0.0) {
        textureStore(heightTex, coord, vec4f(max(0.0, b_self - transfer), 0.0, 0.0, 0.0));
    }
}

@compute @workgroup_size(8, 8)
fn flatten_lowlands(@builtin(global_invocation_id) id: vec3u) {
    let coord  = vec2i(id.xy);
    if (coord.x >= SIZE || coord.y >= SIZE) { return; }
    let h_self = totalH(coord);
    if (h_self >= 0.22) { return; }
    let b_self = textureLoad(heightTex, coord).r;
    let dirs8  = array<vec2i, 8>(
        vec2i(-1,0), vec2i(1,0), vec2i(0,-1), vec2i(0,1),
        vec2i(-1,-1), vec2i(1,-1), vec2i(-1,1), vec2i(1,1),
    );
    var sum : f32 = 0.0; var cnt : f32 = 0.0;
    for (var i = 0; i < 8; i++) {
        let nc = coord + dirs8[i];
        if (!inBounds(nc)) { continue; }
        sum += totalH(nc); cnt += 1.0;
    }
    if (cnt > 0.0) {
        let h_target = h_self + 0.4 * (sum / cnt - h_self);
        textureStore(heightTex, coord, vec4f(max(0.0, b_self + (h_target - h_self)), 0.0, 0.0, 0.0));
    }
}

@compute @workgroup_size(8, 8)
fn bake_sediment(@builtin(global_invocation_id) id: vec3u) {
    let coord = vec2i(id.xy);
    if (coord.x >= SIZE || coord.y >= SIZE) { return; }
    let b = textureLoad(heightTex, coord).r;
    let s = textureLoad(sedTex,    coord).r;
    textureStore(heightTex, coord, vec4f(b + s, 0.0, 0.0, 0.0));
    textureStore(sedTex,    coord, vec4f(0.0,   0.0, 0.0, 0.0));
}
