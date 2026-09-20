/* Adds a copy button to every fenced code block.
 *
 * Jekyll/Rouge emits either `<div class="highlight"><pre>` or a bare `<pre>`.
 * Both are handled by walking <pre> elements and wrapping each one, so this does
 * not depend on the highlighter's markup staying the same.
 *
 * navigator.clipboard is unavailable on insecure origins and in some embedded
 * webviews, so the button is only added when a copy path actually exists. A
 * button that silently does nothing is worse than no button.
 */
(function () {
  "use strict";

  function canCopy() {
    return !!(navigator.clipboard && navigator.clipboard.writeText);
  }

  function label(text) {
    return '<svg width="13" height="13" viewBox="0 0 16 16" fill="none" ' +
           'stroke="currentColor" stroke-width="1.6" aria-hidden="true">' +
           '<rect x="5.5" y="5.5" width="8" height="9" rx="1.5"/>' +
           '<path d="M10.5 3.5h-7a1 1 0 0 0-1 1v8"/></svg><span>' + text + '</span>';
  }

  function wire(pre) {
    if (pre.parentElement && pre.parentElement.classList.contains("dcl-code")) return;

    var shell = document.createElement("div");
    shell.className = "dcl-code";
    pre.parentNode.insertBefore(shell, pre);
    shell.appendChild(pre);

    var btn = document.createElement("button");
    btn.type = "button";
    btn.className = "dcl-copy";
    btn.setAttribute("aria-label", "Copy code to clipboard");
    btn.innerHTML = label("Copy");
    shell.appendChild(btn);

    btn.addEventListener("click", function () {
      var code = pre.querySelector("code");
      var text = (code || pre).innerText.replace(/\n+$/, "");

      navigator.clipboard.writeText(text).then(function () {
        btn.classList.add("copied");
        btn.innerHTML = label("Copied");
        window.setTimeout(function () {
          btn.classList.remove("copied");
          btn.innerHTML = label("Copy");
        }, 1600);
      }).catch(function () {
        btn.innerHTML = label("Press ⌘C");
        window.setTimeout(function () { btn.innerHTML = label("Copy"); }, 2000);
      });
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    if (!canCopy()) return;
    var pres = document.querySelectorAll(".wrap pre");
    for (var i = 0; i < pres.length; i++) wire(pres[i]);
  });
})();
