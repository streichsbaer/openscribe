(() => {
  const INTERVAL_MS = 5000;

  const initHomeCarousel = () => {
    const carousel = document.querySelector(".hero-carousel");
    const lightbox = document.querySelector(".hero-lightbox");

    if (!carousel || !lightbox || carousel.dataset.ready === "true") {
      return;
    }

    carousel.dataset.ready = "true";

    const slides = Array.from(carousel.querySelectorAll(".hero-carousel-slide"));
    const captions = Array.from(carousel.querySelectorAll(".hero-carousel-caption"));
    const dots = Array.from(carousel.querySelectorAll(".hero-carousel-dot"));
    const slideImages = slides.map((slide) => slide.querySelector("img")).filter(Boolean);
    const lightboxImage = lightbox.querySelector("img");
    const lightboxCaption = lightbox.querySelector(".hero-lightbox-caption");
    const closeButton = lightbox.querySelector(".hero-lightbox-close");
    const closeTargets = Array.from(lightbox.querySelectorAll("[aria-label='Close enlarged screenshot']"));
    const pageRoots = [];
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

    if (!slides.length || slides.length !== captions.length || slides.length !== dots.length) {
      return;
    }

    document.body.appendChild(lightbox);
    Array.from(document.body.children).forEach((element) => {
      if (element !== lightbox) {
        pageRoots.push(element);
      }
    });

    let activeIndex = 0;
    let timerId = null;
    let restoreFocusTarget = null;

    const isLightboxOpen = () => !lightbox.hidden;
    const isDarkMode = () => document.body.dataset.mdColorScheme === "slate";

    const syncThemeImages = () => {
      const useDarkImages = isDarkMode();

      slideImages.forEach((image) => {
        const nextSrc = useDarkImages ? image.dataset.darkSrc : image.dataset.lightSrc;

        if (nextSrc && image.getAttribute("src") !== nextSrc) {
          image.src = nextSrc;
        }
      });

      if (isLightboxOpen()) {
        syncLightbox();
      }
    };

    const getFocusableElements = () =>
      Array.from(
        lightbox.querySelectorAll(
          'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
        )
      ).filter((element) => !element.hidden && element.getAttribute("aria-hidden") !== "true");

    const setBackgroundState = (isActive) => {
      pageRoots.forEach((element) => {
        if (isActive) {
          if (!element.hasAttribute("data-home-carousel-managed")) {
            const previousAriaHidden = element.getAttribute("aria-hidden");
            element.dataset.homeCarouselManaged = "true";
            if (previousAriaHidden !== null) {
              element.dataset.homeCarouselAriaHidden = previousAriaHidden;
            }
          }

          element.inert = true;
          element.setAttribute("aria-hidden", "true");
        } else if (element.dataset.homeCarouselManaged === "true") {
          element.inert = false;
          if ("homeCarouselAriaHidden" in element.dataset) {
            element.setAttribute("aria-hidden", element.dataset.homeCarouselAriaHidden);
            delete element.dataset.homeCarouselAriaHidden;
          } else {
            element.removeAttribute("aria-hidden");
          }
          delete element.dataset.homeCarouselManaged;
        }
      });
    };

    const syncLightbox = () => {
      const slide = slides[activeIndex];
      const image = slide.querySelector("img");
      const caption = captions[activeIndex];

      if (!image || !lightboxImage || !lightboxCaption) {
        return;
      }

      lightboxImage.src = image.currentSrc || image.src;
      lightboxImage.alt = image.alt;
      lightboxCaption.textContent = caption.textContent || "";
    };

    const render = (nextIndex) => {
      activeIndex = (nextIndex + slides.length) % slides.length;

      slides.forEach((slide, index) => {
        const isActive = index === activeIndex;
        slide.classList.toggle("is-active", isActive);
        slide.tabIndex = isActive ? 0 : -1;
        slide.setAttribute("aria-hidden", String(!isActive));
      });

      captions.forEach((caption, index) => {
        caption.classList.toggle("is-active", index === activeIndex);
      });

      dots.forEach((dot, index) => {
        const isActive = index === activeIndex;
        dot.classList.toggle("is-active", isActive);
        dot.setAttribute("aria-pressed", String(isActive));
      });

      if (isLightboxOpen()) {
        syncLightbox();
      }
    };

    const stopAutoplay = () => {
      if (timerId !== null) {
        window.clearInterval(timerId);
        timerId = null;
      }
    };

    const startAutoplay = () => {
      if (reducedMotion.matches) {
        return;
      }

      if (isLightboxOpen()) {
        return;
      }

      stopAutoplay();
      timerId = window.setInterval(() => {
        render((activeIndex + 1) % slides.length);
      }, INTERVAL_MS);
    };

    const openLightbox = () => {
      stopAutoplay();
      restoreFocusTarget = document.activeElement instanceof HTMLElement ? document.activeElement : null;
      syncLightbox();
      setBackgroundState(true);
      lightbox.hidden = false;
      document.body.classList.add("hero-lightbox-open");
      closeButton?.focus();
    };

    const closeLightbox = () => {
      if (lightbox.hidden) {
        return;
      }

      lightbox.hidden = true;
      setBackgroundState(false);
      document.body.classList.remove("hero-lightbox-open");
      startAutoplay();
      const focusTarget = restoreFocusTarget;

      window.requestAnimationFrame(() => {
        const fallbackSlide = slides[activeIndex];
        const preferredTarget =
          focusTarget &&
          focusTarget.isConnected &&
          focusTarget !== document.body &&
          focusTarget !== document.documentElement
            ? focusTarget
            : fallbackSlide;

        preferredTarget?.focus();

        if (
          document.activeElement === document.body ||
          document.activeElement === document.documentElement ||
          document.activeElement === closeButton
        ) {
          fallbackSlide?.focus();
        }
      });

      restoreFocusTarget = null;
    };

    const stepSlide = (direction) => {
      render(activeIndex + direction);
    };

    const handleLightboxKeydown = (event) => {
      if (!isLightboxOpen()) {
        return;
      }

      if (event.key === "Escape") {
        event.preventDefault();
        closeLightbox();
      } else if (event.key === "ArrowRight") {
        event.preventDefault();
        stepSlide(1);
      } else if (event.key === "ArrowLeft") {
        event.preventDefault();
        stepSlide(-1);
      } else if (event.key === "Tab") {
        const focusableElements = getFocusableElements();

        if (!focusableElements.length) {
          event.preventDefault();
          closeButton?.focus();
          return;
        }

        const firstElement = focusableElements[0];
        const lastElement = focusableElements[focusableElements.length - 1];

        if (event.shiftKey && document.activeElement === firstElement) {
          event.preventDefault();
          lastElement.focus();
        } else if (!event.shiftKey && document.activeElement === lastElement) {
          event.preventDefault();
          firstElement.focus();
        }
      }
    };

    slides.forEach((slide, index) => {
      slide.addEventListener("click", openLightbox);
      slide.addEventListener("focus", () => render(index));
    });

    dots.forEach((dot, index) => {
      dot.addEventListener("click", () => {
        render(index);
        startAutoplay();
      });
    });

    closeTargets.forEach((target) => {
      target.addEventListener("click", closeLightbox);
    });

    document.addEventListener("keydown", handleLightboxKeydown);

    carousel.addEventListener("mouseenter", stopAutoplay);
    carousel.addEventListener("mouseleave", startAutoplay);
    carousel.addEventListener("focusin", stopAutoplay);
    carousel.addEventListener("focusout", (event) => {
      if (!carousel.contains(event.relatedTarget)) {
        startAutoplay();
      }
    });

    reducedMotion.addEventListener("change", () => {
      if (reducedMotion.matches) {
        stopAutoplay();
      } else {
        startAutoplay();
      }
    });

    new MutationObserver(syncThemeImages).observe(document.body, {
      attributes: true,
      attributeFilter: ["data-md-color-scheme"]
    });

    syncThemeImages();
    render(activeIndex);
    startAutoplay();
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initHomeCarousel, { once: true });
  } else {
    initHomeCarousel();
  }
})();
