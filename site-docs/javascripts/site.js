(() => {
  const THEME_IMAGE_SELECTOR = "img[data-light-src][data-dark-src]";

  const isDarkMode = () => document.body?.dataset.mdColorScheme === "slate";

  // Screenshots carry a light and a dark source and follow the site theme.
  const syncThemeImages = () => {
    document.querySelectorAll(THEME_IMAGE_SELECTOR).forEach((image) => {
      const nextSrc = isDarkMode() ? image.dataset.darkSrc : image.dataset.lightSrc;
      if (nextSrc && image.getAttribute("src") !== nextSrc) {
        image.src = nextSrc;
      }
    });
  };

  const initThemeImages = () => {
    if (!document.body || document.body.dataset.themeImagesReady === "true") {
      return;
    }
    document.body.dataset.themeImagesReady = "true";
    new MutationObserver(syncThemeImages).observe(document.body, {
      attributes: true,
      attributeFilter: ["data-md-color-scheme"]
    });
    syncThemeImages();
  };

  // The launch video plays muted and loops. Reduced motion shows the poster with a play button.
  const initShowcaseVideo = () => {
    const frame = document.querySelector(".os-video");
    const video = frame?.querySelector("video");
    const sound = frame?.querySelector(".os-video__sound");
    const play = frame?.querySelector(".os-video__play");
    if (!frame || !video || frame.dataset.ready === "true") {
      return;
    }
    frame.dataset.ready = "true";

    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const setPlaying = (playing) => frame.classList.toggle("is-playing", playing);
    video.addEventListener("play", () => setPlaying(true));
    video.addEventListener("pause", () => setPlaying(false));

    if (!reduceMotion) {
      video.play().catch(() => setPlaying(false));
    }

    play?.addEventListener("click", () => {
      video.play();
    });

    sound?.addEventListener("click", () => {
      video.muted = !video.muted;
      if (!video.muted && video.paused) {
        video.play();
      }
      sound.setAttribute("aria-pressed", String(!video.muted));
      sound.querySelector(".os-video__sound-label").textContent = video.muted ? "Sound on" : "Sound off";
    });

    // Pause while scrolled away so the page stays light.
    if ("IntersectionObserver" in window && !reduceMotion) {
      new IntersectionObserver((entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting && frame.classList.contains("was-playing")) {
            frame.classList.remove("was-playing");
            video.play().catch(() => {});
          } else if (!entry.isIntersecting && !video.paused) {
            frame.classList.add("was-playing");
            video.pause();
          }
        });
      }, { threshold: 0.15 }).observe(frame);
    }
  };

  // Copy buttons next to commands.
  const initCopyButtons = () => {
    document.querySelectorAll("[data-copy]").forEach((button) => {
      if (button.dataset.ready === "true") {
        return;
      }
      button.dataset.ready = "true";
      button.addEventListener("click", async () => {
        try {
          await navigator.clipboard.writeText(button.dataset.copy);
          button.classList.add("is-copied");
          button.setAttribute("aria-label", "Copied");
          setTimeout(() => {
            button.classList.remove("is-copied");
            button.setAttribute("aria-label", "Copy command");
          }, 1600);
        } catch {
          button.setAttribute("aria-label", "Copy failed");
        }
      });
    });
  };

  const init = () => {
    initThemeImages();
    initShowcaseVideo();
    initCopyButtons();
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init, { once: true });
  } else {
    init();
  }
})();
