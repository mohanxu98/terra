import terrainShaderSource from '../shaders/terrain.wgsl?raw';

export class Terrain {
  private pipeline!: GPURenderPipeline;
  private vertexBuffer!: GPUBuffer;
  private indexBuffer!: GPUBuffer;
  private indexCount!: number;
  private bindGroup!: GPUBindGroup;
  private heightmapSampler!: GPUSampler;

  private readonly GRID = 512;
  private readonly WORLD_SCALE = 4096;
  private readonly HEIGHT_SCALE = 600;

  constructor(
    private device: GPUDevice,
    private format: GPUTextureFormat,
    private heightmapTex: GPUTexture,
    private globalsBuffer: GPUBuffer,
  ) {}

  async init(): Promise<void> {
    // r32float textures need a non-filtering sampler
    this.heightmapSampler = this.device.createSampler({
      label: 'Heightmap Sampler',
      magFilter: 'nearest',
      minFilter: 'nearest',
      addressModeU: 'clamp-to-edge',
      addressModeV: 'clamp-to-edge',
    });

    this.buildMesh();
    await this.createPipeline();
    this.createBindGroup();
  }

  private buildMesh(): void {
    const N = this.GRID;
    const half = this.WORLD_SCALE / 2;

    // Each vertex: x, z, u, v (4 floats = 16 bytes)
    const vertData = new Float32Array(N * N * 4);
    for (let j = 0; j < N; j++) {
      for (let i = 0; i < N; i++) {
        const idx = (j * N + i) * 4;
        vertData[idx + 0] = (i / (N - 1)) * this.WORLD_SCALE - half;
        vertData[idx + 1] = (j / (N - 1)) * this.WORLD_SCALE - half;
        vertData[idx + 2] = i / (N - 1);
        vertData[idx + 3] = j / (N - 1);
      }
    }

    this.vertexBuffer = this.device.createBuffer({
      label: 'Terrain Vertex Buffer',
      size: vertData.byteLength,
      usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
    });
    this.device.queue.writeBuffer(this.vertexBuffer, 0, vertData);

    const quadCount = (N - 1) * (N - 1);
    const indices = new Uint32Array(quadCount * 6);
    let idx = 0;
    for (let j = 0; j < N - 1; j++) {
      for (let i = 0; i < N - 1; i++) {
        const tl = j * N + i;
        const tr = tl + 1;
        const bl = tl + N;
        const br = bl + 1;
        indices[idx++] = tl; indices[idx++] = bl; indices[idx++] = br;
        indices[idx++] = tl; indices[idx++] = br; indices[idx++] = tr;
      }
    }
    this.indexCount = idx;

    this.indexBuffer = this.device.createBuffer({
      label: 'Terrain Index Buffer',
      size: indices.byteLength,
      usage: GPUBufferUsage.INDEX | GPUBufferUsage.COPY_DST,
    });
    this.device.queue.writeBuffer(this.indexBuffer, 0, indices);
  }

  private async createPipeline(): Promise<void> {
    const shaderModule = this.device.createShaderModule({
      label: 'Terrain Shader',
      code: terrainShaderSource,
    });

    const bgl = this.device.createBindGroupLayout({
      label: 'Terrain BGL',
      entries: [
        { binding: 0, visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT, buffer: { type: 'uniform' } },
        { binding: 1, visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT, texture: { sampleType: 'unfilterable-float' } },
        { binding: 2, visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT, sampler: { type: 'non-filtering' } },
      ],
    });

    this.pipeline = await this.device.createRenderPipelineAsync({
      label: 'Terrain Pipeline',
      layout: this.device.createPipelineLayout({
        label: 'Terrain Pipeline Layout',
        bindGroupLayouts: [bgl],
      }),
      vertex: {
        module: shaderModule,
        entryPoint: 'vs_main',
        buffers: [{
          arrayStride: 16,
          attributes: [
            { shaderLocation: 0, offset: 0, format: 'float32x2' }, // xz
            { shaderLocation: 1, offset: 8, format: 'float32x2' }, // uv
          ],
        }],
      },
      fragment: {
        module: shaderModule,
        entryPoint: 'fs_main',
        targets: [{ format: this.format }],
      },
      primitive: { topology: 'triangle-list', cullMode: 'back' },
      depthStencil: {
        format: 'depth24plus',
        depthWriteEnabled: true,
        depthCompare: 'less',
      },
    });
  }

  private createBindGroup(): void {
    this.bindGroup = this.device.createBindGroup({
      label: 'Terrain Bind Group',
      layout: this.pipeline.getBindGroupLayout(0),
      entries: [
        { binding: 0, resource: { buffer: this.globalsBuffer } },
        { binding: 1, resource: this.heightmapTex.createView() },
        { binding: 2, resource: this.heightmapSampler },
      ],
    });
  }

  encode(pass: GPURenderPassEncoder): void {
    pass.setPipeline(this.pipeline);
    pass.setBindGroup(0, this.bindGroup);
    pass.setVertexBuffer(0, this.vertexBuffer);
    pass.setIndexBuffer(this.indexBuffer, 'uint32');
    pass.drawIndexed(this.indexCount);
  }

  getWorldScale(): number { return this.WORLD_SCALE; }
  getHeightScale(): number { return this.HEIGHT_SCALE; }
}
