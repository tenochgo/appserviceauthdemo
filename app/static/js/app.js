/* app.js — global vanilla JS enhancements */

(function () {
  "use strict";

  // Active nav link
  const path = window.location.pathname;
  document.querySelectorAll(".nav-link[data-path]").forEach((a) => {
    if (a.dataset.path === path) a.classList.add("active");
  });

  // Footer year
  const yearEl = document.querySelector(".footer-year");
  if (yearEl) yearEl.textContent = new Date().getFullYear();

  // Button ripple effect
  document.addEventListener("click", (e) => {
    const btn = e.target.closest(".btn");
    if (!btn) return;
    const ripple = document.createElement("span");
    const rect = btn.getBoundingClientRect();
    const size = Math.max(rect.width, rect.height);
    ripple.style.cssText = `
      position:absolute;width:${size}px;height:${size}px;
      left:${e.clientX - rect.left - size / 2}px;
      top:${e.clientY - rect.top - size / 2}px;
      background:rgba(255,255,255,.25);border-radius:50%;
      transform:scale(0);animation:ripple .5s linear;pointer-events:none;
    `;
    btn.style.position = "relative";
    btn.style.overflow = "hidden";
    btn.appendChild(ripple);
    ripple.addEventListener("animationend", () => ripple.remove());
  });

  // Inject ripple keyframe once
  if (!document.getElementById("ripple-style")) {
    const s = document.createElement("style");
    s.id = "ripple-style";
    s.textContent = "@keyframes ripple{to{transform:scale(2.5);opacity:0}}";
    document.head.appendChild(s);
  }
})();
