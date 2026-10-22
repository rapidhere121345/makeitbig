(function () {
  "use strict";

  var labels = { windows: "Windows", linux: "Linux" };
  var latestPanel = document.getElementById("latest-panel");
  var latestId = document.getElementById("latest-id");
  var latestMeta = document.getElementById("latest-meta");
  var latestDownloads = document.getElementById("latest-downloads");
  var historyBody = document.getElementById("history-body");
  var keepCount = document.getElementById("keep-count");

  function embeddedIndex() {
    var node = document.getElementById("release-index");
    if (!node || !node.textContent.trim()) return null;
    try { return JSON.parse(node.textContent); } catch (error) { return null; }
  }

  function dateLabel(value) {
    if (typeof value !== "string") return "Unknown time";
    return value.length >= 16 ? value.slice(0, 16).replace("T", " ") + " UTC" : value;
  }

  function sizeLabel(value) {
    if (typeof value !== "number") return "";
    if (value < 1024) return value + " B";
    if (value < 1024 * 1024) return (value / 1024).toFixed(1) + " KiB";
    if (value < 1024 * 1024 * 1024) return (value / 1024 / 1024).toFixed(1) + " MiB";
    return (value / 1024 / 1024 / 1024).toFixed(1) + " GiB";
  }

  function linkFor(build, platform) {
    var file = build && build.files && build.files[platform];
    if (!file || !file.path) return null;
    return { href: "builds/" + encodeURIComponent(build.id) + "/" + file.path, file: file };
  }

  function downloadLink(build, platform, prominent) {
    var entry = linkFor(build, platform);
    var node = document.createElement(entry ? "a" : "span");
    node.className = prominent ? "download-button" : "file-link";
    node.textContent = entry ? labels[platform] + " · " + (sizeLabel(entry.file.size) || entry.file.name) : labels[platform] + " · Not available";
    if (entry) {
      node.href = entry.href;
      node.download = "";
      node.title = entry.file.sha256 || entry.file.name;
    } else {
      node.className += " is-disabled";
    }
    return node;
  }

  function render(data) {
    var builds = Array.isArray(data && data.builds) ? data.builds : [];
    keepCount.textContent = data && data.keep_builds ? data.keep_builds : "20";
    historyBody.textContent = "";
    if (!builds.length) {
      var empty = document.createElement("tr");
      var cell = document.createElement("td");
      cell.colSpan = 4;
      cell.textContent = "No builds yet. After exporting, run scripts/release.sh all.";
      empty.appendChild(cell);
      historyBody.appendChild(empty);
      latestPanel.hidden = true;
      return;
    }

    var latest = builds[0];
    latestPanel.hidden = false;
    latestId.textContent = latest.id;
    latestMeta.textContent = dateLabel(latest.created_at) + (latest.git_revision ? " · " + latest.git_revision : "") + (latest.note ? " · " + latest.note : "");
    latestDownloads.textContent = "";
    latestDownloads.appendChild(downloadLink(latest, "windows", true));
    latestDownloads.appendChild(downloadLink(latest, "linux", true));

    builds.forEach(function (build) {
      var row = document.createElement("tr");
      var idCell = document.createElement("td");
      var idCode = document.createElement("code");
      idCode.textContent = build.id;
      idCell.appendChild(idCode);
      row.appendChild(idCell);
      var timeCell = document.createElement("td");
      timeCell.textContent = dateLabel(build.created_at);
      row.appendChild(timeCell);
      ["windows", "linux"].forEach(function (platform) {
        var fileCell = document.createElement("td");
        fileCell.appendChild(downloadLink(build, platform, false));
        row.appendChild(fileCell);
      });
      historyBody.appendChild(row);
    });
  }

  function showError() {
    historyBody.textContent = "";
    var row = document.createElement("tr");
    var cell = document.createElement("td");
    cell.colSpan = 4;
    cell.textContent = "The release index is temporarily unavailable. Please try again later.";
    row.appendChild(cell);
    historyBody.appendChild(row);
  }

  var data = embeddedIndex();
  if (data) {
    render(data);
  } else if (window.fetch) {
    window.fetch("index.json").then(function (response) {
      if (!response.ok) throw new Error("index request failed");
      return response.json();
    }).then(render).catch(showError);
  } else {
    showError();
  }
}());
