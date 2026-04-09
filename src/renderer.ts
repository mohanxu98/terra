import { Camera } from './camera';
import { UI } from './ui';
import { Terrain } from './terrain/terrain';
import { Heightmap } from './terrain/heightmap';

// Shared globals uniform buffer layout (std140):
// offset   0: mat4x4f viewProj       (64 bytes)
// offset  64: mat4x4f invViewProj    (64 bytes)
// offset 128: vec3f   sunDir         (12 bytes) + 4 pad
// offset 144: vec3f   cameraPos      (12 bytes) + 4 pad
// offset 160: f32     time
// offset 164: f32     timeOfDay      (0–1)
// offset 168: f32     seaLevel
// offset 172: f32     pad
// Total: 176 bytes
export const GLOBALS_BUFFER_SIZE = 176;

export class Renderer {
  private camera: Camera;
  private globalsBuffer!: GPUBuffer;
  private depthTexture!: GPUTexture;
  private depthView!: GPUTextureView;

  private terrain!: Terrain;
  private timeOfDay = 0.45;

  constructor(
    private device: GPUDevice,
    private context: GPUCanvasContext,
    private format: GPUTextureFormat,
    private canvas: HTMLCanvasElement,
    private ui: UI,
  ) {
    this.camera = new Camera(canvas);
  }

  async init(): Promise<void> {
    this.ui.setStatus('Allocating GPU resources...', 15);

    this.globalsBuffer = this.device.createBuffer({
      label: 'Globals Uniform Buffer',
      size: GLOBALS_BUFFER_SIZE,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    });

    this.createDepthTexture();

    this.ui.setStatus('Generating terrain heightmap...', 40);

    // Seed from URL param: ?seed=12345  (default 137)
    const urlSeed = new URLSearchParams(window.location.search).get('seed');
    const seed = urlSeed ? (parseInt(urlSeed, 10) || 137) : 137;

    // Generate heightmap on CPU and upload directly to a GPU texture
    const heightmap = new Heightmap(512, 512, seed);
    const heightData = heightmap.generate();

    const heightmapTex = this.device.createTexture({
      label: 'Heightmap Texture',
      size: { width: 512, height: 512 },
      format: 'r32float',
      usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
    });

    this.device.queue.writeTexture(
      { texture: heightmapTex },
      heightData,
      { bytesPerRow: 512 * 4 },
      { width: 512, height: 512 },
    );

    this.ui.setStatus('Building terrain mesh...', 70);

    this.terrain = new Terrain(this.device, this.format, heightmapTex, this.globalsBuffer);
    await this.terrain.init();

    this.ui.setStatus('Ready!', 100);
  }

  private createDepthTexture(): void {
    if (this.depthTexture) this.depthTexture.destroy();
    this.depthTexture = this.device.createTexture({
      label: 'Depth Texture',
      size: { width: this.canvas.width, height: this.canvas.height },
      format: 'depth24plus',
      usage: GPUTextureUsage.RENDER_ATTACHMENT,
    });
    this.depthView = this.depthTexture.createView();
  }

  onResize(width: number, height: number): void {
    this.camera.onResize(width, height);
    this.createDepthTexture();
  }

  setTimeOfDay(tod: number): void {
    this.timeOfDay = tod;
  }

  getCameraPosition(): [number, number, number] {
    return this.camera.position;
  }

  render(time: number, dt: number): void {
    this.camera.update(dt);

    // Sun arc: tod=0 → below horizon, tod=0.25 → sunrise, tod=0.5 → overhead noon, tod=0.75 → sunset
    const theta = this.timeOfDay * Math.PI * 2 - Math.PI * 0.5;
    const sunY = Math.sin(theta);
    const sunX = Math.cos(theta) * 0.5;
    const sunZ = -Math.abs(Math.cos(theta)) * 0.866;
    const sunLen = Math.sqrt(sunX * sunX + sunY * sunY + sunZ * sunZ);

    // Write globals buffer
    const globalsData = new ArrayBuffer(GLOBALS_BUFFER_SIZE);
    const f32 = new Float32Array(globalsData);
    const view = new DataView(globalsData);

    const vp = this.camera.viewProjMatrix;
    for (let i = 0; i < 16; i++) f32[i] = vp[i];

    const invVP = this.camera.getInverseViewProj();
    for (let i = 0; i < 16; i++) f32[16 + i] = invVP[i];

    f32[32] = sunX / sunLen;
    f32[33] = sunY / sunLen;
    f32[34] = sunZ / sunLen;
    f32[35] = 0;

    const cp = this.camera.position;
    f32[36] = cp[0];
    f32[37] = cp[1];
    f32[38] = cp[2];
    f32[39] = 0;

    view.setFloat32(160, time, true);
    view.setFloat32(164, this.timeOfDay, true);
    view.setFloat32(168, 0.0, true);
    view.setFloat32(172, 0.0, true);

    this.device.queue.writeBuffer(this.globalsBuffer, 0, globalsData);

    const encoder = this.device.createCommandEncoder({ label: 'Frame Encoder' });

    const renderPass = encoder.beginRenderPass({
      label: 'Main Render Pass',
      colorAttachments: [{
        view: this.context.getCurrentTexture().createView(),
        clearValue: { r: 0.45, g: 0.65, b: 0.85, a: 1.0 }, // sky blue
        loadOp: 'clear',
        storeOp: 'store',
      }],
      depthStencilAttachment: {
        view: this.depthView,
        depthClearValue: 1.0,
        depthLoadOp: 'clear',
        depthStoreOp: 'store',
      },
    });

    this.terrain.encode(renderPass);

    renderPass.end();
    this.device.queue.submit([encoder.finish()]);
  }
}
