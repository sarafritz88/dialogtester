import sys

snippet = """<script>
(function() {
  if (!("serviceWorker" in navigator)) return;
  navigator.serviceWorker.register("/dialogTest/coi-serviceworker.js", {scope: "/dialogTest/"})
    .then(function(reg) {
      if (!reg.active) {
        var w = reg.installing || reg.waiting;
        if (w) {
          w.addEventListener("statechange", function(e) {
            if (e.target.state === "activated") { window.location.reload(); }
          });
        }
      }
    });
})();
</script>"""

html_path = sys.argv[1]
with open(html_path, "r") as f:
    html = f.read()

html = html.replace("</head>", snippet + "\n</head>", 1)

with open(html_path, "w") as f:
    f.write(html)

print("Service worker injected into", html_path)
