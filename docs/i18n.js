/**
 * Club Kit docs i18n
 * - Locales: docs/locales/{id,en,ja,es}.js → sets window.ClubKitLocale
 * - Attributes:
 *   data-i18n="key"              → textContent
 *   data-i18n-html="key"         → innerHTML
 *   data-i18n-aria-label="key"   → aria-label
 *   data-i18n-title="key"        → title
 *   data-i18n-meta="title|description" on <title> or <meta name="description">
 */
(function () {
  var LANG_KEY = "clubkit-docs-lang";
  var SUPPORTED = { id: true, en: true, ja: true, es: true };
  var cache = {};
  var current = "id";
  var activeStrings = null;

  function normalize(lang) {
    if (!lang) return "id";
    lang = String(lang).toLowerCase().slice(0, 2);
    return SUPPORTED[lang] ? lang : "id";
  }

  function savedLang() {
    try {
      return normalize(localStorage.getItem(LANG_KEY));
    } catch (_) {
      return "id";
    }
  }

  function persist(lang) {
    try {
      localStorage.setItem(LANG_KEY, lang);
    } catch (_) {
      /* ignore */
    }
  }

  function t(key, strings) {
    if (!key || !strings) return null;
    if (Object.prototype.hasOwnProperty.call(strings, key)) return strings[key];
    return null;
  }

  // docs.js owns theme state but writes hardcoded EN labels on toggle;
  // re-localize theme labels whenever data-theme flips (see init observer).
  function refreshThemeLabels(strings) {
    var themeToggle = document.getElementById("themeToggle");
    if (!themeToggle || !strings) return;
    if (!strings["theme.toLight"] || !strings["theme.toDark"]) return;
    var dark = document.documentElement.getAttribute("data-theme") === "dark";
    themeToggle.setAttribute("aria-label", dark ? strings["theme.toLight"] : strings["theme.toDark"]);
    themeToggle.title = dark ? strings["theme.light"] || strings["theme.toLight"] : strings["theme.dark"] || strings["theme.toDark"];
  }

  function applyStrings(strings) {
    if (!strings) return;
    activeStrings = strings;

    document.querySelectorAll("[data-i18n]").forEach(function (el) {
      var v = t(el.getAttribute("data-i18n"), strings);
      if (v != null) el.textContent = v;
    });

    document.querySelectorAll("[data-i18n-html]").forEach(function (el) {
      var v = t(el.getAttribute("data-i18n-html"), strings);
      if (v != null) el.innerHTML = v;
    });

    document.querySelectorAll("[data-i18n-aria-label]").forEach(function (el) {
      var v = t(el.getAttribute("data-i18n-aria-label"), strings);
      if (v != null) el.setAttribute("aria-label", v);
    });

    document.querySelectorAll("[data-i18n-title]").forEach(function (el) {
      var v = t(el.getAttribute("data-i18n-title"), strings);
      if (v != null) el.setAttribute("title", v);
    });

    document.querySelectorAll("[data-i18n-meta]").forEach(function (el) {
      var key = el.getAttribute("data-i18n-meta");
      var v = t(key, strings);
      if (v == null) return;
      if (el.tagName === "TITLE") el.textContent = v;
      else if (el.getAttribute("name") === "description") el.setAttribute("content", v);
    });

    document.documentElement.lang = current;

    document.querySelectorAll("#langSwitch [data-lang]").forEach(function (btn) {
      var on = btn.getAttribute("data-lang") === current;
      btn.classList.toggle("is-active", on);
      btn.setAttribute("aria-pressed", on ? "true" : "false");
    });

    refreshThemeLabels(strings);
  }

  function loadLocaleScript(lang) {
    return new Promise(function (resolve, reject) {
      if (cache[lang] && cache[lang].strings) {
        window.ClubKitLocale = cache[lang];
        resolve(cache[lang]);
        return;
      }
      var prev = window.ClubKitLocale;
      window.ClubKitLocale = undefined;
      var s = document.createElement("script");
      s.src = "locales/" + lang + ".js";
      s.async = false;
      s.onload = function () {
        var loc = window.ClubKitLocale;
        if (!loc || !loc.strings) {
          window.ClubKitLocale = prev;
          reject(new Error("Locale missing strings: " + lang));
          return;
        }
        cache[lang] = loc;
        resolve(loc);
      };
      s.onerror = function () {
        window.ClubKitLocale = prev;
        reject(new Error("Failed to load locale: " + lang));
      };
      document.head.appendChild(s);
    });
  }

  function setLang(lang) {
    lang = normalize(lang);
    return loadLocaleScript(lang)
      .then(function (loc) {
        current = lang;
        persist(lang);
        applyStrings(loc.strings);
        try {
          window.dispatchEvent(new CustomEvent("clubkit:langchange", { detail: { lang: lang } }));
        } catch (_) {
          /* ignore */
        }
        return loc;
      })
      .catch(function (err) {
        if (lang !== "id") return setLang("id");
        console.warn("[clubkit-i18n]", err);
      });
  }

  function bindSwitcher() {
    var root = document.getElementById("langSwitch");
    if (!root) return;
    root.addEventListener("click", function (e) {
      var btn = e.target.closest("[data-lang]");
      if (!btn) return;
      var lang = btn.getAttribute("data-lang");
      if (!lang || lang === current) return;
      setLang(lang);
    });
  }

  function init() {
    bindSwitcher();
    setLang(savedLang());
    if (window.MutationObserver) {
      new MutationObserver(function (muts) {
        for (var i = 0; i < muts.length; i++) {
          if (muts[i].attributeName === "data-theme") {
            refreshThemeLabels(activeStrings);
            break;
          }
        }
      }).observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
    }
  }

  window.ClubKitI18n = {
    setLang: setLang,
    getLang: function () {
      return current;
    },
    t: function (key) {
      var loc = cache[current] || window.ClubKitLocale;
      return loc && loc.strings ? t(key, loc.strings) : null;
    },
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
