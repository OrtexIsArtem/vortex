// Marks each [data-reveal] element as it reaches the screen; global.css fades it in. Without this script nothing hides.
document.documentElement.classList.add('reveal-ready');
const reveal = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add('is-in');
      reveal.unobserve(entry.target);
    }
  },
  { rootMargin: '0px 0px -12% 0px' },
);
document.querySelectorAll('[data-reveal]').forEach((element) => reveal.observe(element));
