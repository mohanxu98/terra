struct Globals {
    viewProj    : mat4x4f,
    invViewProj : mat4x4f,
    sunDir      : vec3f,
    _pad0       : f32,
    cameraPos   : vec3f,
    _pad1       : f32,
    time        : f32,
    timeOfDay   : f32,
    seaLevel    : f32,
    _pad2       : f32,
};
@group(0) @binding(0) var<uniform> globals : Globals;

const SEA_LEVEL : f32 = 5.0;

struct VOut {
    @builtin(position) clip_pos : vec4f,
    @location(0)       ndc_xy   : vec2f,
};

@vertex
fn vs_main(@builtin(vertex_index) vi: u32) -> VOut {
    var p = array<vec2f, 3>(
        vec2f(-1.0, -1.0),
        vec2f( 3.0, -1.0),
        vec2f(-1.0,  3.0),
    );
    var out: VOut;
    out.clip_pos = vec4f(p[vi], 0.5, 1.0);
    out.ndc_xy   = p[vi];
    return out;
}

fn aces(x: vec3f) -> vec3f {
    let a = 2.51f; let b = 0.03f; let c = 2.43f; let d = 0.59f; let e = 0.14f;
    return clamp((x*(a*x+b))/(x*(c*x+d)+e), vec3f(0.0), vec3f(1.0));
}

fn skyColor(dir: vec3f, sunDir: vec3f) -> vec3f {
    let zenith       = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);
    let sunElevation = clamp(sunDir.y, -0.1, 1.0);
    let nightSky     = vec3f(0.01, 0.01, 0.05);
    let dawnSky      = vec3f(0.70, 0.35, 0.15);
    let daySkyTop    = vec3f(0.08, 0.25, 0.72);
    let daySkyHz     = vec3f(0.40, 0.65, 0.90);
    let dayMix       = smoothstep(-0.05, 0.15, sunElevation);
    let dawnMix      = smoothstep(-0.15, 0.0, sunElevation)
                     * (1.0 - smoothstep(0.1, 0.3, sunElevation));
    var sky           = mix(nightSky, mix(daySkyHz, daySkyTop, zenith), dayMix);
    sky               = mix(sky, dawnSky, dawnMix * (1.0 - zenith) * 0.6);
    return sky;
}

struct FOut {
    @builtin(frag_depth) depth : f32,
    @location(0)         color : vec4f,
};

@fragment
fn fs_main(in: VOut) -> FOut {
    let near_h  = globals.invViewProj * vec4f(in.ndc_xy, 0.0, 1.0);
    let near_w  = near_h.xyz / near_h.w;
    let ray_dir = normalize(near_w - globals.cameraPos);

    if (ray_dir.y >= -0.0001) { discard; }
    let t = (SEA_LEVEL - globals.cameraPos.y) / ray_dir.y;
    if (t <= 0.0) { discard; }

    let world_pos = globals.cameraPos + t * ray_dir;

    let clip  = globals.viewProj * vec4f(world_pos, 1.0);
    let depth = clip.z / clip.w;

    let sunDir       = globals.sunDir;
    let sunElevation = sunDir.y;
    let dayFactor    = smoothstep(-0.05, 0.15, sunElevation);

    let sunColorDay  = vec3f(1.4, 1.2, 0.9);
    let sunColorDawn = vec3f(1.5, 0.6, 0.2);
    let sunColor     = mix(sunColorDawn, sunColorDay,
                           smoothstep(0.0, 0.2, sunElevation)) * dayFactor;

    let N     = vec3f(0.0, 1.0, 0.0);
    let V     = -ray_dir;
    let NdotV = max(dot(N, V), 0.0);

    let F0      = 0.02;
    let fresnel = F0 + (1.0 - F0) * pow(1.0 - NdotV, 5.0);

    let reflDir = reflect(ray_dir, N);
    let skyRefl = skyColor(reflDir, sunDir) * fresnel;

    let deepBlue = vec3f(0.02, 0.09, 0.20);
    let ambient  = deepBlue * (0.12 + 0.18 * dayFactor) * (1.0 - fresnel);

    let refl = reflect(-sunDir, N);
    let spec = pow(max(dot(refl, V), 0.0), 512.0) * dayFactor * 3.0;

    var color = ambient + skyRefl + spec * sunColor;

    let fogFac   = 1.0 - exp(-t * 0.00005);
    let fogColor = skyColor(ray_dir, sunDir);
    color        = mix(color, fogColor, clamp(fogFac, 0.0, 1.0));

    color = aces(color);
    color = pow(clamp(color, vec3f(0.0), vec3f(1.0)), vec3f(1.0 / 2.2));

    var out: FOut;
    out.depth = clamp(depth, 0.0, 1.0);
    out.color = vec4f(color, 1.0);
    return out;
}
