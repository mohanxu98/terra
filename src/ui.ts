export class UI {
  private loadingOverlay: HTMLElement;
  private loadingBar: HTMLElement;
  private loadingStatus: HTMLElement;
  private errorOverlay: HTMLElement;
  private errorMessage: HTMLElement;
  private uiPanel: HTMLElement;
  private stats: HTMLElement;
  private controlsHint: HTMLElement;
  private fpsEl: HTMLElement;
  private frameTimeEl: HTMLElement;
  private camPosEl: HTMLElement;
  private todSlider: HTMLInputElement;
  private todDisplay: HTMLElement;
  private todCallback: ((value: number) => void) | null = null;

  constructor() {
    this.loadingOverlay = document.getElementById('loading-overlay')!;
    this.loadingBar = document.getElementById('loading-bar')!;
    this.loadingStatus = document.getElementById('loading-status')!;
    this.errorOverlay = document.getElementById('error-overlay')!;
    this.errorMessage = document.getElementById('error-message')!;
    this.uiPanel = document.getElementById('ui-panel')!;
    this.stats = document.getElementById('stats')!;
    this.controlsHint = document.getElementById('controls-hint')!;
    this.fpsEl = document.getElementById('fps')!;
    this.frameTimeEl = document.getElementById('frame-time')!;
    this.camPosEl = document.getElementById('cam-pos')!;
    this.todSlider = document.getElementById('tod-slider') as HTMLInputElement;
    this.todDisplay = document.getElementById('tod-display')!;

    this.todSlider.addEventListener('input', () => {
      const val = parseFloat(this.todSlider.value);
      this.updateTodDisplay(val);
      if (this.todCallback) this.todCallback(val);
    });
  }

  setStatus(message: string, progress: number): void {
    this.loadingStatus.textContent = message;
    this.loadingBar.style.width = `${progress}%`;
  }

  showError(message: string): void {
    this.loadingOverlay.style.display = 'none';
    this.errorMessage.innerHTML = message;
    this.errorOverlay.classList.add('visible');
  }

  hideLoading(): void {
    this.loadingOverlay.classList.add('fade-out');
    setTimeout(() => {
      this.loadingOverlay.style.display = 'none';
      (window as unknown as { _stopGrain?: () => void })._stopGrain?.();
    }, 800);
  }

  showUI(): void {
    this.uiPanel.classList.add('visible');
    this.stats.classList.add('visible');
    this.controlsHint.classList.add('visible');
  }

  updateStats(fps: number, frameMs: number, camPos: [number, number, number]): void {
    this.fpsEl.textContent = String(fps);
    this.frameTimeEl.textContent = frameMs.toFixed(1);
    this.camPosEl.textContent =
      `${camPos[0].toFixed(0)}, ${camPos[1].toFixed(0)}, ${camPos[2].toFixed(0)}`;
  }

  onTimeOfDayChange(callback: (value: number) => void): void {
    this.todCallback = callback;
    callback(parseFloat(this.todSlider.value));
  }

  getTimeOfDay(): number {
    return parseFloat(this.todSlider.value);
  }

  private updateTodDisplay(value: number): void {
    const hours = (value * 24) % 24;
    const h = Math.floor(hours);
    const m = Math.floor((hours - h) * 60);
    this.todDisplay.textContent = `${h.toString().padStart(2, '0')}:${m.toString().padStart(2, '0')}`;
  }
}
