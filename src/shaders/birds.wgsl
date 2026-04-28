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

@group(0) @binding(0) var<uniform>       globals : Globals;
@group(0) @binding(1) var<storage, read> birds   : array<vec4f>;

struct VertIn {
    @location(0)             vertex  : vec4f,   // xyz = local pos, w = flap weight
    @builtin(instance_index) instIdx : u32,
};

struct VertOut {
    @builtin(position) clip     : vec4f,
    @location(0)       worldPos : vec3f,
    @location(1)       normal   : vec3f,
};

@vertex
fn vs_main(in: VertIn) -> VertOut {
    let i   = in.instIdx * 2u;
    let pos = birds[i].xyz;
    let fwd = normalize(birds[i + 1u].xyz);

    // Build orthonormal frame: right, up, fwd
    let world_up = vec3f(0.0, 1.0, 0.0);
    let alt_up   = vec3f(1.0, 0.0, 0.0);
    let ref_up   = select(world_up, alt_up, abs(dot(fwd, world_up)) > 0.99);
    let right    = normalize(cross(ref_up, fwd));
    let up       = normalize(cross(fwd, right));

    let scale      = 11.0;
    let flapAmp    = 0.4;
    let flapSpeed  = 11.0;
    let flapOffset = sin(globals.time * flapSpeed + f32(in.instIdx) * 0.713) * in.vertex.w * flapAmp;

    let lp       = vec3f(in.vertex.x, in.vertex.y + flapOffset, in.vertex.z);
    let worldPos = pos + right * (lp.x * scale) + up * (lp.y * scale) + fwd * (lp.z * scale);

    var out: VertOut;
    out.clip     = globals.viewProj * vec4f(worldPos, 1.0);
    out.worldPos = worldPos;
    out.normal   = up;
    return out;
}

@fragment
fn fs_main(in: VertOut) -> @location(0) vec4f {
    let sunDir    = globals.sunDir;
    let dayFactor = smoothstep(-0.05, 0.2, sunDir.y);

    let NdotL   = abs(dot(normalize(in.normal), sunDir));
    let diffuse = NdotL * dayFactor * 0.45;
    let ambient = mix(0.04, 0.18, dayFactor);

    let base  = vec3f(0.09, 0.07, 0.06);
    let color = base * (ambient + diffuse);
    return vec4f(color, 1.0);
}
