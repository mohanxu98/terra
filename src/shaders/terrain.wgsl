// Terrain vertex + fragment shader

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
@group(0) @binding(1) var heightmapTex : texture_2d<f32>;
@group(0) @binding(2) var heightmapSampler : sampler;

const HEIGHT_SCALE : f32 = 600.0;
const WORLD_HALF   : f32 = 2048.0;
const INV_GRID     : f32 = 1.0 / 511.0;   // 512 grid -> 511 intervals
const TEXEL_SIZE   : f32 = 1.0 / 512.0;

struct VertexInput {
    @location(0) xz : vec2f,
    @location(1) uv : vec2f,
};

struct VertexOutput {
    @builtin(position) clip_pos : vec4f,
    @location(0) world_pos  : vec3f,
    @location(1) uv         : vec2f,
    @location(2) normal     : vec3f,
    @location(3) fog_factor : f32,
};

fn sampleHeight(uv: vec2f) -> f32 {
    return textureLoad(heightmapTex, vec2i(uv * 512.0), 0).r * HEIGHT_SCALE;
}

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    let uv = in.uv;

    // Sample height at this vertex
    let h = sampleHeight(uv);
    let world_pos = vec3f(in.xz.x, h, in.xz.y);

    out.clip_pos  = globals.viewProj * vec4f(world_pos, 1.0);
    out.world_pos = world_pos;
    out.uv = uv;

    // Compute normal from finite differences
    let d = TEXEL_SIZE;
    let hR = sampleHeight(uv + vec2f(d, 0.0));
    let hL = sampleHeight(uv - vec2f(d, 0.0));
    let hU = sampleHeight(uv + vec2f(0.0, d));
    let hD = sampleHeight(uv - vec2f(0.0, d));
    let scale = 4096.0 * TEXEL_SIZE; // world spacing between samples
    let normal = normalize(vec3f(hL - hR, 2.0 * scale, hD - hU));
    out.normal = normal;

    // Fog
    let dist = length(world_pos - globals.cameraPos);
    out.fog_factor = 1.0 - exp(-dist * 0.00012);

    return out;
}

// Simple atmosphere color approximation for fog
fn skyColor(dir: vec3f, sunDir: vec3f, tod: f32) -> vec3f {
    let zenith = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);
    let sunElevation = clamp(sunDir.y, -0.1, 1.0);

    // Night / day sky gradient
    let nightSky  = vec3f(0.01, 0.01, 0.05);
    let dawnSky   = vec3f(0.7, 0.35, 0.15);
    let daySkyTop = vec3f(0.08, 0.25, 0.72);
    let daySkyHz  = vec3f(0.4, 0.65, 0.9);

    let dayMix  = smoothstep(-0.05, 0.15, sunElevation);
    let dawnMix = smoothstep(-0.15, 0.0, sunElevation) * (1.0 - smoothstep(0.1, 0.3, sunElevation));

    var sky = mix(nightSky, mix(daySkyHz, daySkyTop, zenith), dayMix);
    sky = mix(sky, dawnSky, dawnMix * (1.0 - zenith) * 0.6);
    return sky;
}

// ACES approximate tone mapping
fn aces(x: vec3f) -> vec3f {
    let a = 2.51f;
    let b = 0.03f;
    let c = 2.43f;
    let d = 0.59f;
    let e = 0.14f;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3f(0.0), vec3f(1.0));
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    let sunDir = globals.sunDir;
    let tod    = globals.timeOfDay;

    // Surface normal
    let N = normalize(in.normal);

    // --- Lighting ---
    let sunElevation = sunDir.y;
    let dayFactor = smoothstep(-0.05, 0.15, sunElevation);

    // Sun color shifts with elevation
    let sunColorDay  = vec3f(1.4, 1.2, 0.9);
    let sunColorDawn = vec3f(1.5, 0.6, 0.2);
    let sunColor = mix(sunColorDawn, sunColorDay, smoothstep(0.0, 0.2, sunElevation)) * dayFactor;

    // Ambient: sky + ground bounce
    let ambientSky    = vec3f(0.15, 0.25, 0.45) * dayFactor + vec3f(0.01, 0.01, 0.03) * (1.0 - dayFactor);
    let ambientGround = vec3f(0.05, 0.08, 0.04) * dayFactor;
    let ambient = mix(ambientGround, ambientSky, N.y * 0.5 + 0.5);

    // Diffuse
    let NdotL = max(dot(N, sunDir), 0.0);
    let diffuse = NdotL * sunColor * 1.2;

    // Slope-based terrain color
    let altitude = clamp(in.world_pos.y / HEIGHT_SCALE, 0.0, 1.0);
    let slope = 1.0 - N.y; // 0 = flat, 1 = vertical

    // Colors
    let deepWater = vec3f(0.05, 0.12, 0.18);
    let sand      = vec3f(0.76, 0.70, 0.50);
    let grass     = vec3f(0.25, 0.45, 0.15);
    let shrub     = vec3f(0.30, 0.38, 0.20);
    let rock      = vec3f(0.45, 0.40, 0.35);
    let snow      = vec3f(0.92, 0.95, 1.00);

    // Blend by altitude
    var terrain_color: vec3f;
    let seaLine = globals.seaLevel / HEIGHT_SCALE;
    if (altitude < seaLine + 0.02) {
        terrain_color = mix(deepWater, sand, smoothstep(seaLine - 0.01, seaLine + 0.02, altitude));
    } else if (altitude < 0.2) {
        terrain_color = mix(sand, grass, smoothstep(0.05, 0.2, altitude));
    } else if (altitude < 0.55) {
        terrain_color = mix(grass, shrub, smoothstep(0.2, 0.55, altitude));
    } else if (altitude < 0.75) {
        terrain_color = mix(shrub, rock, smoothstep(0.55, 0.75, altitude));
    } else {
        terrain_color = mix(rock, snow, smoothstep(0.75, 0.95, altitude));
    }

    // Rock on steep slopes
    terrain_color = mix(terrain_color, rock, smoothstep(0.3, 0.6, slope));
    // Snow on steep high slopes (less snow)
    if (altitude > 0.7) {
        terrain_color = mix(terrain_color, snow * 0.9, smoothstep(0.5, 0.7, slope) * smoothstep(0.7, 0.85, altitude));
    }

    // Lighting
    var color = terrain_color * (ambient + diffuse);

    // Specular on wet-looking areas (low altitude, near sea)
    if (altitude < 0.12) {
        let V = normalize(globals.cameraPos - in.world_pos);
        let H = normalize(sunDir + V);
        let spec = pow(max(dot(N, H), 0.0), 32.0) * 0.3 * dayFactor;
        color += spec * sunColor;
    }

    // Fog
    let fogColor = skyColor(normalize(in.world_pos - globals.cameraPos), sunDir, tod);
    color = mix(color, fogColor, clamp(in.fog_factor, 0.0, 1.0));

    // Tone map
    color = aces(color);

    // Gamma
    color = pow(clamp(color, vec3f(0.0), vec3f(1.0)), vec3f(1.0 / 2.2));

    return vec4f(color, 1.0);
}
