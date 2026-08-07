/* Shared Club Kit docs shell — theme + light helpers */
(function () {
  const THEME_KEY = "clubkit-docs-theme";
  const themeToggle = document.getElementById("themeToggle");

  function currentTheme() {
    return document.documentElement.getAttribute("data-theme") === "dark" ? "dark" : "light";
  }

  function applyTheme(theme) {
    const next = theme === "dark" ? "dark" : "light";
    document.documentElement.setAttribute("data-theme", next);
    try {
      localStorage.setItem(THEME_KEY, next);
    } catch (_) {
      /* ignore */
    }
    if (themeToggle) {
      themeToggle.setAttribute(
        "aria-label",
        next === "dark" ? "Switch to light mode" : "Switch to dark mode"
      );
      themeToggle.title = next === "dark" ? "Light mode" : "Dark mode";
    }
  }

  if (themeToggle) {
    themeToggle.addEventListener("click", function () {
      applyTheme(currentTheme() === "dark" ? "light" : "dark");
    });
    applyTheme(currentTheme());
  }

  /* Old single-page bookmarks → setup.html */
  if (
    location.pathname.replace(/\\/g, "/").endsWith("/docs/") ||
    /\/docs\/index\.html$/i.test(location.pathname.replace(/\\/g, "/"))
  ) {
    const hash = location.hash || "";
    if (
      hash &&
      hash !== "#" &&
      document.body &&
      document.body.getAttribute("data-page") === "home"
    ) {
      location.replace("setup.html" + hash);
    }
  }
})();
