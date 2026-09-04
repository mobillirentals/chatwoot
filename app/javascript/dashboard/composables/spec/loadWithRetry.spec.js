import { useLoadWithRetry } from '../loadWithRetry';

describe('useLoadWithRetry', () => {
  afterEach(() => {
    vi.restoreAllMocks();
    vi.useRealTimers();
  });

  it('resolves as loaded on the first successful attempt (default type: image)', async () => {
    vi.stubGlobal(
      'Image',
      class {
        set src(_value) {
          queueMicrotask(() => this.onload?.());
        }
      }
    );

    const { isLoaded, hasError, loadWithRetry } = useLoadWithRetry();
    await loadWithRetry('https://example.com/a.jpg');

    expect(isLoaded.value).toBe(true);
    expect(hasError.value).toBe(false);
  });

  it('probes video/audio via a detached media element instead of Image', async () => {
    const created = [];
    vi.spyOn(document, 'createElement').mockImplementation(tag => {
      const el = { tagName: tag };
      Object.defineProperty(el, 'src', {
        set: () => {
          queueMicrotask(() => el.onloadedmetadata?.());
        },
      });
      created.push(el);
      return el;
    });

    const { isLoaded, hasError, loadWithRetry } = useLoadWithRetry({
      type: 'video',
    });
    await loadWithRetry('https://example.com/a.mp4');

    expect(created).toHaveLength(1);
    expect(created[0].tagName).toBe('video');
    expect(isLoaded.value).toBe(true);
    expect(hasError.value).toBe(false);
  });

  it('retries with backoff and recovers once the resource becomes loadable', async () => {
    let attempts = 0;
    vi.spyOn(document, 'createElement').mockImplementation(() => {
      const el = {};
      Object.defineProperty(el, 'src', {
        set: () => {
          attempts += 1;
          queueMicrotask(() => {
            if (attempts < 2) el.onerror?.();
            else el.onloadedmetadata?.();
          });
        },
      });
      return el;
    });

    // backoff bem curto (timers reais) em vez de fake timers — evita a interação
    // instavel entre vi.useFakeTimers() e o queueMicrotask usado pelo mock acima.
    const { isLoaded, hasError, loadWithRetry } = useLoadWithRetry({
      type: 'audio',
      backoff: 5,
    });
    await loadWithRetry('https://example.com/a.mp3');

    expect(attempts).toBe(2);
    expect(isLoaded.value).toBe(true);
    expect(hasError.value).toBe(false);
  });

  it('gives up after max_retry attempts and surfaces hasError', async () => {
    vi.spyOn(document, 'createElement').mockImplementation(() => {
      const el = {};
      Object.defineProperty(el, 'src', {
        set: () => {
          queueMicrotask(() => el.onerror?.());
        },
      });
      return el;
    });

    const { isLoaded, hasError, loadWithRetry } = useLoadWithRetry({
      type: 'video',
      max_retry: 2,
      backoff: 5,
    });
    await loadWithRetry('https://example.com/a.mp4');

    expect(isLoaded.value).toBe(false);
    expect(hasError.value).toBe(true);
  });
});
