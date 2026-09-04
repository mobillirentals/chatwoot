import { ref } from 'vue';

// image usa onload/onerror (o unico jeito de saber que os bytes carregaram); video/audio
// usam loadedmetadata/error via um elemento fora do DOM (o mesmo elemento so serve pra
// testar a URL, o bubble monta seu proprio <video>/<audio> depois que isLoaded vira true).
const probeMediaLoad = (type, url) => {
  return new Promise((resolve, reject) => {
    if (type === 'video' || type === 'audio') {
      const el = document.createElement(type);
      el.preload = 'metadata';
      el.onloadedmetadata = resolve;
      el.onerror = () => reject(new Error(`Failed to load ${type}`));
      el.src = url;
      return;
    }

    const img = new Image();
    img.onload = resolve;
    img.onerror = () => reject(new Error('Failed to load image'));
    img.src = url;
  });
};

export const useLoadWithRetry = (config = {}) => {
  const maxRetry = config.max_retry || 3;
  const backoff = config.backoff || 1000;
  const type = config.type || 'image';

  const isLoaded = ref(false);
  const hasError = ref(false);

  const loadWithRetry = async url => {
    const attemptLoad = async () => {
      await probeMediaLoad(type, url);
      isLoaded.value = true;
      hasError.value = false;
    };

    const sleep = ms => {
      return new Promise(resolve => {
        setTimeout(resolve, ms);
      });
    };

    const retry = async (attempt = 0) => {
      try {
        await attemptLoad();
      } catch (error) {
        if (attempt + 1 >= maxRetry) {
          hasError.value = true;
          isLoaded.value = false;
          return;
        }
        await sleep(backoff * (attempt + 1));
        await retry(attempt + 1);
      }
    };

    await retry();
  };

  return {
    isLoaded,
    hasError,
    loadWithRetry,
  };
};
