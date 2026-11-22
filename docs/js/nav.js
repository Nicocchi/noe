(function () {
    var here = location.pathname.split("/").pop() || "index.html";
    document.querySelectorAll(".sidebar nav a").forEach(function (a) {
        var href = a.getAttribute("href");
        if (href === here || (here === "" && href === "index.html")) {
            a.classList.add("active");
        }
    });

    document.querySelectorAll("pre").forEach(function (pre) {
        var btn = document.createElement("button");
        btn.className = "copy";
        btn.type = "button";
        btn.textContent = "Copy";
        btn.addEventListener("click", function () {
            var text = pre.querySelector("code") ? pre.querySelector("code").innerText : pre.innerText;
            navigator.clipboard.writeText(text).then(function () {
                btn.textContent = "Copied";
                setTimeout(function () { btn.textContent = "Copy"; }, 1200);
            });
        });
        pre.appendChild(btn);
    });

    var filter = document.getElementById("filter");
    if (filter) {
        filter.addEventListener("input", function () {
            var q = filter.value.toLowerCase();
            document.querySelectorAll("table.filterable tbody tr").forEach(function (row) {
                row.style.display = row.innerText.toLowerCase().indexOf(q) >= 0 ? "" : "none";
            });
        });
    }
})();
