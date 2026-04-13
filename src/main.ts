import { Renderer } from './renderer';
import { UI } from './ui';

async function main(): Promise<void> {
  const ui = new UI();

  if (!navigator.gpu) {
    ui.showError(
      'WebGPU is not supported in this browser. ' +
      'Please use Chrome 113+, Edge 113+, or another WebGPU-capable browser.'
    );
    return;
  }

  try {
    ui.setStatus('Initializing WebGPU...', 5);

    let adapter = await navigator.gpu.requestAdapter({ powerPreference: 'high-performance' });
    if (!adapter) {
      adapter = await navigator.gpu.requestAdapter();
    }

    if (!adapter) {
      ui.showError(
        'No suitable WebGPU adapter found. ' +
        'Your GPU may not support the required features.'
      );
      return;
    }

    try {
      const adapterInfo = await (adapter as unknown as { requestAdapterInfo(): Promise<{ vendor: string; device: string }> }).requestAdapterInfo();
      console.log('WebGPU Adapter:', adapterInfo.vendor, adapterInfo.device);
    } catch {
      console.log('WebGPU adapter info unavailable');
    }

    const requiredFeatures: GPUFeatureName[] = [];

    if (adapter.features.has('float32-filterable')) {
      requiredFeatures.push('float32-filterable');
    }

    const device = await adapter.requestDevice({
      requiredFeatures,
    });

    device.lost.then((info) => {
      console.error('WebGPU device lost:', info.message, info.reason);
      if (info.reason !== 'destroyed') {
        ui.showError(`WebGPU device lost: ${info.message}. Please refresh the page.`);
      }
    });

    ui.setStatus('Configuring canvas...', 10);

    const canvas = document.getElementById('canvas') as HTMLCanvasElement;
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;

    const context = canvas.getContext('webgpu');
    if (!context) {
      ui.showError('Failed to get WebGPU canvas context.');
      return;
    }

    const format = navigator.gpu.getPreferredCanvasFormat();
    context.configure({
      device,
      format,
      alphaMode: 'opaque',
    });

    window.addEventListener('resize', () => {
      canvas.width = window.innerWidth;
      canvas.height = window.innerHeight;
      context.configure({ device, format, alphaMode: 'opaque' });
      renderer.onResize(canvas.width, canvas.height);
    });

    const renderer = new Renderer(device, context, format, canvas, ui);
    await renderer.init();

    ui.hideLoading();
    ui.showUI();

    ui.onTimeOfDayChange((tod) => renderer.setTimeOfDay(tod));

    let lastTime = performance.now();
    let frameCount = 0;
    let fpsAccum = 0;

    function frame(timestamp: number): void {
      const dt = Math.min((timestamp - lastTime) / 1000, 0.05);
      lastTime = timestamp;

      frameCount++;
      fpsAccum += dt;

      if (fpsAccum >= 1.0) {
        const fps = Math.round(frameCount / fpsAccum);
        const frameMs = ((fpsAccum / frameCount) * 1000).toFixed(1);
        ui.updateStats(fps, parseFloat(frameMs), renderer.getCameraPosition());
        frameCount = 0;
        fpsAccum = 0;
      }

      renderer.render(timestamp / 1000, dt);
      requestAnimationFrame(frame);
    }

    requestAnimationFrame(frame);

  } catch (err) {
    console.error('Fatal error during initialization:', err);
    ui.showError(
      `Initialization failed: ${err instanceof Error ? err.message : String(err)}`
    );
  }
}

main();
