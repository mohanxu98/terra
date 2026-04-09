// Fractional Brownian Motion (fBm) heightmap generator
// Uses gradient noise (Perlin-style) for smooth terrain

function fade(t: number): number {
  return t * t * t * (t * (t * 6 - 15) + 10);
}

function lerp(a: number, b: number, t: number): number {
  return a + t * (b - a);
}

function grad(hash: number, x: number, y: number): number {
  const h = hash & 7;
  const u = h < 4 ? x : y;
  const v = h < 4 ? y : x;
  return ((h & 1) ? -u : u) + ((h & 2) ? -v : v);
}

class PermutationTable {
  private p: Uint8Array;

  constructor(seed: number = 42) {
    this.p = new Uint8Array(512);
    const perm = new Uint8Array(256);
    for (let i = 0; i < 256; i++) perm[i] = i;

    // Fisher-Yates shuffle with seeded LCG
    let s = seed | 0;
    for (let i = 255; i > 0; i--) {
      s = (s * 1664525 + 1013904223) & 0xffffffff;
      const j = ((s >>> 0) % (i + 1));
      const tmp = perm[i];
      perm[i] = perm[j];
      perm[j] = tmp;
    }

    for (let i = 0; i < 512; i++) {
      this.p[i] = perm[i & 255];
    }
  }

  noise2D(x: number, y: number): number {
    const xi = Math.floor(x) & 255;
    const yi = Math.floor(y) & 255;
    const xf = x - Math.floor(x);
    const yf = y - Math.floor(y);

    const u = fade(xf);
    const v = fade(yf);

    const aa = this.p[this.p[xi]     + yi];
    const ab = this.p[this.p[xi]     + yi + 1];
    const ba = this.p[this.p[xi + 1] + yi];
    const bb = this.p[this.p[xi + 1] + yi + 1];

    return lerp(
      lerp(grad(aa, xf,   yf  ), grad(ba, xf-1, yf  ), u),
      lerp(grad(ab, xf,   yf-1), grad(bb, xf-1, yf-1), u),
      v
    );
  }
}

export class Heightmap {
  private data: Float32Array<ArrayBuffer>;

  constructor(private width: number, private height: number, private seed: number = 137) {
    this.data = new Float32Array(width * height);
  }

  generate(): Float32Array<ArrayBuffer> {
    const perm = new PermutationTable(this.seed);

    const octaves = 8;
    const lacunarity = 2.0;
    const persistence = 0.5;
    const baseFrequency = 1.5;

    // Center of the island
    const cx = this.width / 2;
    const cy = this.height / 2;
    const maxDist = Math.sqrt(cx * cx + cy * cy);

    let globalMin = Infinity;
    let globalMax = -Infinity;

    // First pass: fBm
    for (let y = 0; y < this.height; y++) {
      for (let x = 0; x < this.width; x++) {
        const nx = (x / this.width) * 4.0;
        const ny = (y / this.height) * 4.0;

        let val = 0;
        let amp = 1.0;
        let freq = baseFrequency;
        let maxAmp = 0;

        for (let o = 0; o < octaves; o++) {
          val += perm.noise2D(nx * freq, ny * freq) * amp;
          maxAmp += amp;
          amp *= persistence;
          freq *= lacunarity;
        }
        val /= maxAmp; // normalize to roughly [-1, 1]

        // Radial falloff (island shape)
        const dx = x - cx;
        const dy = y - cy;
        const dist = Math.sqrt(dx * dx + dy * dy) / maxDist;
        // Smooth falloff near edges
        const falloff = 1.0 - Math.pow(Math.max(0, dist * 1.2 - 0.1), 2.0);
        const smoothFalloff = Math.max(0, falloff);

        val = val * 0.5 + 0.5; // to [0, 1]
        val *= smoothFalloff;

        // Bump up mountains a bit
        val = Math.pow(val, 0.9);

        this.data[y * this.width + x] = val;

        if (val < globalMin) globalMin = val;
        if (val > globalMax) globalMax = val;
      }
    }

    // Normalize to [0, 1]
    const range = globalMax - globalMin;
    if (range > 0) {
      for (let i = 0; i < this.data.length; i++) {
        this.data[i] = (this.data[i] - globalMin) / range;
      }
    }

    return this.data;
  }

  getWidth(): number { return this.width; }
  getHeight(): number { return this.height; }
  getData(): Float32Array<ArrayBuffer> { return this.data; }
}
