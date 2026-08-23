(function () {
  var LOGO = "/static/logo-icon.png?v=45";
  var BRAND = "Oriphiel AI";
  var scheduled = null;

  function isMobile() {
    return window.matchMedia && window.matchMedia("(max-width: 768px)").matches;
  }

  function ensureDarkTheme() {
    try {
      document.documentElement.classList.add("dark");
      document.documentElement.style.colorScheme = "dark";
    } catch (e) {}
  }

  function ensurePattern() {
    var d = document.getElementById("oriphiel-pattern");
    if (!d) {
      d = document.createElement("div");
      d.id = "oriphiel-pattern";
      d.innerHTML =
        '<img class="oriphiel-wm-img" src="' + LOGO + '" alt="" aria-hidden="true" />';
      document.body.insertBefore(d, document.body.firstChild);
    }
    var img = d.querySelector(".oriphiel-wm-img");
    if (!img) {
      img = document.createElement("img");
      img.className = "oriphiel-wm-img";
      img.alt = "";
      img.setAttribute("aria-hidden", "true");
      d.appendChild(img);
    }
    if ((img.getAttribute("src") || "") !== LOGO) img.setAttribute("src", LOGO);
    if (d.dataset.oriphielReady === "1") return;
    d.dataset.oriphielReady = "1";
    d.style.cssText =
      "position:fixed!important;inset:0!important;z-index:1!important;pointer-events:none!important;overflow:hidden!important;background:transparent!important;";
    img.style.cssText = isMobile()
      ? "position:absolute!important;left:50%!important;top:40%!important;transform:translate(-50%,-50%)!important;width:min(78vw,420px)!important;height:auto!important;opacity:0.12!important;object-fit:contain!important;filter:brightness(1.4) contrast(1.15)!important;"
      : "position:absolute!important;left:50%!important;top:42%!important;transform:translate(-50%,-50%)!important;width:min(72vw,680px)!important;height:auto!important;opacity:0.11!important;object-fit:contain!important;filter:brightness(1.3) contrast(1.1)!important;";
  }

  function ensureTopbar() {
    var bar = document.getElementById("oriphiel-topbar");
    if (!bar) {
      bar = document.createElement("div");
      bar.id = "oriphiel-topbar";
      bar.innerHTML =
        '<img src="' +
        LOGO +
        '" alt="Oriphiel" />' +
        "<div><strong>Oriphiel d.o.o.</strong>" +
        '<span class="oriphiel-tagline"> Privatni AI asistent za web, Google Ads i poslovnu automatizaciju. ' +
        "Lokalni modeli — podaci ostaju kod vas. </span>" +
        '<a href="https://www.oriphiel.hr/" target="_blank" rel="noopener">oriphiel.hr</a></div>';
      document.body.appendChild(bar);
    }
    var ti = bar.querySelector("img");
    if (ti && (ti.getAttribute("src") || "") !== LOGO) ti.setAttribute("src", LOGO);
    if (bar.dataset.oriphielReady === "1") return;
    bar.dataset.oriphielReady = "1";
    bar.style.cssText = isMobile()
      ? "position:fixed!important;top:0!important;left:0!important;right:0!important;z-index:2147483000!important;display:flex!important;align-items:center!important;justify-content:flex-start!important;gap:0.45rem!important;padding:0.55rem 0.75rem 0.55rem 3rem!important;background:rgba(8,8,8,0.98)!important;color:#f5f5f5!important;font-size:0.95rem!important;"
      : "position:fixed!important;top:0!important;left:3.25rem!important;right:0!important;z-index:2147483000!important;display:flex!important;align-items:center!important;justify-content:center!important;gap:0.55rem!important;padding:0.4rem 0.9rem!important;background:rgba(12,12,12,0.96)!important;color:#eee!important;font-size:0.8rem!important;";
  }

  function inComposer(el) {
    if (!el || !el.closest) return true;
    if (el.closest("#oriphiel-topbar,#oriphiel-pattern,aside,form,textarea,input,[contenteditable='true']"))
      return true;
    return false;
  }

  function isModelTitle(text) {
    if (!text) return false;
    var t = text.replace(/\s+/g, " ").trim();
    if (t.length > 48) return false;
    return (
      /^Arena Model$/i.test(t) ||
      /^llama3\.1:8b/i.test(t) ||
      /^qwen2\.5-coder:14b/i.test(t) ||
      /^qwen2\.5:14b/i.test(t)
    );
  }

  function isBrandTitle(text) {
    return /^Oriphiel AI$/i.test((text || "").replace(/\s+/g, " ").trim());
  }

  function styleIcon(img) {
    if (!img) return;
    img.classList.add("oriphiel-model-icon");
    img.setAttribute("data-oriphiel-keep", "1");
    img.alt = "Oriphiel";
    if ((img.getAttribute("src") || "") !== LOGO) {
      img.removeAttribute("srcset");
      img.setAttribute("src", LOGO);
    }
    if (img.dataset.oriphielStyled === "1") return;
    img.dataset.oriphielStyled = "1";
    img.style.cssText =
      "width:36px!important;height:36px!important;min-width:36px!important;min-height:36px!important;" +
      "margin:0 0.55rem 0 0!important;padding:0!important;opacity:1!important;visibility:visible!important;" +
      "filter:brightness(1.5) contrast(1.25)!important;background:transparent!important;" +
      "object-fit:contain!important;display:inline-block!important;vertical-align:middle!important;" +
      "border:0!important;border-radius:0!important;flex:0 0 36px!important;position:static!important;";
  }

  function styleBrand(span) {
    if (!span.classList.contains("oriphiel-hero-name")) span.classList.add("oriphiel-hero-name");
    if ((span.textContent || "").trim() !== BRAND) span.textContent = BRAND;
    if (span.dataset.oriphielStyled === "1") return;
    span.dataset.oriphielStyled = "1";
    span.style.cssText =
      "display:inline-block!important;margin:0!important;padding:0!important;" +
      "font-family:'Sora',system-ui,sans-serif!important;font-size:1.45rem!important;" +
      "font-weight:700!important;letter-spacing:-0.02em!important;" +
      "color:#ffffff!important;vertical-align:middle!important;line-height:1.15!important;" +
      "white-space:nowrap!important;";
  }

  function hideExtra(img) {
    if (!img || img.getAttribute("data-oriphiel-keep") === "1") return;
    img.setAttribute("data-oriphiel-kill", "1");
    img.hidden = true;
    img.style.cssText =
      "display:none!important;width:0!important;height:0!important;max-width:0!important;max-height:0!important;" +
      "margin:0!important;padding:0!important;opacity:0!important;visibility:hidden!important;" +
      "position:absolute!important;left:-9999px!important;pointer-events:none!important;overflow:hidden!important;";
    try {
      img.remove();
    } catch (e) {}
  }

  function isProfileImg(img) {
    if (!img || !img.getAttribute) return false;
    var src = img.getAttribute("src") || "";
    return src.indexOf("/api/v1/models/model/profile/image") >= 0;
  }

  function findOwuiProfileNear(labelEl) {
    var scope = labelEl.parentElement;
    for (var up = 0; up < 8 && scope; up++) {
      var imgs = scope.querySelectorAll("img");
      for (var i = 0; i < imgs.length; i++) {
        var img = imgs[i];
        if (img.classList.contains("oriphiel-wm-img")) continue;
        if (img.closest("#oriphiel-topbar,aside,form,nav")) continue;
        if (isProfileImg(img)) return img;
        // OWUI prazan chat: size-9 / rounded-2xl avatar pored imena modela
        if (
          (img.className || "").indexOf("size-9") >= 0 ||
          (img.className || "").indexOf("rounded-2xl") >= 0
        ) {
          return img;
        }
      }
      scope = scope.parentElement;
    }
    return null;
  }

  function dedupeHeaderLogos(labelEl) {
    if (!labelEl || inComposer(labelEl)) return;
    var parent = labelEl.parentElement;
    if (!parent) return;

    styleBrand(labelEl);

    // Lijevi = OWUI profile; desni = naš injekt — spoji u JEDAN (OWUI profile)
    var profile = findOwuiProfileNear(labelEl);

    // Makni sve injektirane logoe unutar reda s natpisom
    Array.prototype.slice.call(parent.querySelectorAll("img")).forEach(function (img) {
      if (img === profile) return;
      hideExtra(img);
    });

    var keep = profile;
    if (!keep) {
      keep = document.createElement("img");
    }

    keep.removeAttribute("data-oriphiel-kill");
    keep.hidden = false;
    styleIcon(keep);
    try {
      if (keep.parentElement !== parent || keep.nextElementSibling !== labelEl) {
        parent.insertBefore(keep, labelEl);
      }
    } catch (e) {}

    // Sakrij sve ostale profile/logo slike u okolini
    var cluster = parent.parentElement || parent;
    Array.prototype.slice.call(cluster.querySelectorAll("img")).forEach(function (img) {
      if (img === keep) return;
      if (img.classList.contains("oriphiel-wm-img")) return;
      if (img.closest("#oriphiel-topbar,aside,form,nav")) return;
      if (isProfileImg(img) || img.classList.contains("oriphiel-model-icon")) hideExtra(img);
    });

    if (!parent.classList.contains("oriphiel-icon-row")) {
      parent.classList.add("oriphiel-icon-row");
      parent.setAttribute("data-oriphiel-fixed", "1");
      parent.style.setProperty("display", "flex", "important");
      parent.style.setProperty("align-items", "center", "important");
      parent.style.setProperty("justify-content", "center", "important");
      parent.style.setProperty("gap", "0.15rem", "important");
    }
  }

  function fixAllBrandHeaders() {
    var nodes = document.querySelectorAll("span,a,p,h1,h2,h3,button,label");
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      if (!(el instanceof HTMLElement) || inComposer(el)) continue;
      if (el.children.length !== 0) continue;
      var raw = (el.textContent || "").replace(/\s+/g, " ").trim();
      if (!isModelTitle(raw) && !isBrandTitle(raw) && !el.classList.contains("oriphiel-hero-name")) continue;
      dedupeHeaderLogos(el);
    }
  }

  function findSendButton(near) {
    if (!near) return null;
    var root = near.closest("form") || near.parentElement;
    if (!root) return null;
    var buttons = root.querySelectorAll("button");
    for (var i = 0; i < buttons.length; i++) {
      var b = buttons[i];
      if (!b || b.disabled || b.id === "oriphiel-mobile-send") continue;
      var al = ((b.getAttribute("aria-label") || "") + " " + (b.title || "")).toLowerCase();
      if (al.indexOf("send") >= 0 || al.indexOf("pošalji") >= 0) return b;
    }
    return buttons.length ? buttons[buttons.length - 1] : null;
  }

  function bindMobileEnterSend() {
    var areas = document.querySelectorAll("textarea");
    for (var i = 0; i < areas.length; i++) {
      var ta = areas[i];
      if (ta.dataset.oriphielEnterBound === "1") continue;
      ta.dataset.oriphielEnterBound = "1";
      ta.addEventListener(
        "keydown",
        function (e) {
          if (!isMobile()) return;
          if ((e.key || e.code) !== "Enter" && e.keyCode !== 13) return;
          if (e.shiftKey) return;
          e.preventDefault();
          e.stopPropagation();
          var btn = findSendButton(e.target);
          if (btn) btn.click();
        },
        true
      );
    }
  }

  function ensureMobileSendBtn() {
    var existing = document.getElementById("oriphiel-mobile-send");
    if (!isMobile()) {
      if (existing) existing.remove();
      return;
    }
    if (!document.querySelector("textarea")) {
      if (existing) existing.remove();
      return;
    }
    if (!existing) {
      var btn = document.createElement("button");
      btn.id = "oriphiel-mobile-send";
      btn.type = "button";
      btn.textContent = "Pošalji";
      btn.addEventListener("click", function (e) {
        e.preventDefault();
        var area = document.querySelector("textarea");
        if (!area || !(area.value || "").trim()) return;
        var send = findSendButton(area);
        if (send) send.click();
      });
      document.body.appendChild(btn);
    }
  }

  function run() {
    if (!document.body) return;
    ensureDarkTheme();
    ensurePattern();
    ensureTopbar();
    fixAllBrandHeaders();
    bindMobileEnterSend();
    ensureMobileSendBtn();
  }

  function scheduleRun() {
    if (scheduled) return;
    scheduled = setTimeout(function () {
      scheduled = null;
      run();
    }, 300);
  }

  run();
  setInterval(run, 2000);
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", run);
  try {
    new MutationObserver(scheduleRun).observe(document.documentElement, {
      childList: true,
      subtree: true,
    });
  } catch (e) {}
})();
