/* EmareBuild — Frontend Application */

(function () {
  "use strict";

  // ── DOM Elements ──
  const chatMessages = document.getElementById("chatMessages");
  const chatForm = document.getElementById("chatForm");
  const chatInput = document.getElementById("chatInput");
  const sendBtn = document.getElementById("sendBtn");
  const statusBar = document.getElementById("statusBar");
  const previewFrame = document.getElementById("previewFrame");
  const previewPlaceholder = document.getElementById("previewPlaceholder");
  const codeContent = document.getElementById("codeContent");
  const fileList = document.getElementById("fileList");

  const tabs = document.querySelectorAll(".tab");
  const tabContents = {
    preview: document.getElementById("tabPreview"),
    code: document.getElementById("tabCode"),
    files: document.getElementById("tabFiles"),
  };

  // ── State ──
  const sessionId = crypto.randomUUID();
  let ws = null;
  let files = {}; // filename → code
  let activeFile = null;
  let reconnectAttempts = 0;
  let streamingEl = null; // current streaming message element

  // ── WebSocket ──
  function connect() {
    const proto = location.protocol === "https:" ? "wss:" : "ws:";
    ws = new WebSocket(`${proto}//${location.host}/ws/${sessionId}`);

    ws.onopen = function () {
      reconnectAttempts = 0;
      setStatus("Bağlandı", "connected");
    };

    ws.onmessage = function (event) {
      const data = JSON.parse(event.data);
      handleMessage(data);
    };

    ws.onclose = function () {
      setStatus("Bağlantı kesildi", "");
      streamingEl = null;
      if (reconnectAttempts < 5) {
        reconnectAttempts++;
        var secs = 2 * reconnectAttempts;
        addMessage("status", "Yeniden bağlanılıyor... (" + secs + "s)");
        setTimeout(connect, secs * 1000);
      } else {
        addMessage("status", "Bağlantı kurulamadı. Sayfayı yenileyin.");
      }
    };

    ws.onerror = function () {
      ws.close();
    };
  }

  // ── Message Handlers ──
  function handleMessage(data) {
    switch (data.type) {
      case "assistant":
        streamingEl = null;
        addMessage("assistant", data.content);
        setSending(false);
        break;

      case "token":
        if (!streamingEl) {
          streamingEl = document.createElement("div");
          streamingEl.className = "msg assistant streaming";
          chatMessages.appendChild(streamingEl);
        }
        streamingEl.textContent += data.content;
        chatMessages.scrollTop = chatMessages.scrollHeight;
        break;

      case "error":
        streamingEl = null;
        addMessage("status", "⚠️ " + data.content);
        setSending(false);
        break;

      case "status":
        addMessage("status", data.content);
        break;

      case "building":
        addMessage("building", data.content);
        setStatus("Yazılıyor: " + data.file, "building");
        break;

      case "file_created":
        files[data.file] = data.code;
        updateFileList();
        selectFile(data.file);
        break;

      case "preview_ready":
        showPreview(data.url);
        setStatus("Hazır", "connected");
        switchTab("preview");
        break;
    }
  }

  // ── Chat ──
  function addMessage(type, content) {
    const el = document.createElement("div");
    el.className = "msg " + type;
    el.textContent = content;
    chatMessages.appendChild(el);
    chatMessages.scrollTop = chatMessages.scrollHeight;
  }

  function sendMessage(text) {
    if (!ws || ws.readyState !== WebSocket.OPEN) return;
    if (!text.trim()) return;

    addMessage("user", text);
    ws.send(JSON.stringify({ type: "chat", content: text }));
    setSending(true);
  }

  function setSending(busy) {
    sendBtn.disabled = busy;
    chatInput.disabled = busy;
    if (!busy) chatInput.focus();
  }

  // ── Preview ──
  function showPreview(url) {
    previewPlaceholder.classList.add("hidden");
    previewFrame.classList.remove("hidden");
    previewFrame.src = url;
  }

  // ── Tabs ──
  function switchTab(name) {
    tabs.forEach(function (tab) {
      tab.classList.toggle("active", tab.dataset.tab === name);
    });
    Object.keys(tabContents).forEach(function (key) {
      tabContents[key].classList.toggle("active", key === name);
    });
  }

  // ── File List ──
  function updateFileList() {
    var names = Object.keys(files);
    if (names.length === 0) {
      fileList.innerHTML = '<p class="empty-state">Henüz dosya yok</p>';
      return;
    }

    fileList.innerHTML = "";
    names.forEach(function (name) {
      var el = document.createElement("div");
      el.className = "file-item" + (name === activeFile ? " active" : "");
      el.innerHTML =
        '<span class="file-icon">' + getFileIcon(name) + "</span>" +
        '<span class="file-name">' + escapeHtml(name) + "</span>" +
        '<span class="file-status">✓</span>';
      el.addEventListener("click", function () {
        selectFile(name);
        switchTab("code");
      });
      fileList.appendChild(el);
    });
  }

  function selectFile(name) {
    activeFile = name;
    if (files[name]) {
      codeContent.textContent = files[name];
    }
    updateFileList();
  }

  function getFileIcon(name) {
    if (name.endsWith(".html")) return "🌐";
    if (name.endsWith(".css")) return "🎨";
    if (name.endsWith(".js")) return "⚙️";
    return "📄";
  }

  // ── Utilities ──
  function escapeHtml(text) {
    var d = document.createElement("div");
    d.textContent = text;
    return d.innerHTML;
  }

  function setStatus(text, stateClass) {
    statusBar.textContent = text;
    statusBar.className = "topbar-status" + (stateClass ? " " + stateClass : "");
  }

  // ── Event Listeners ──
  chatForm.addEventListener("submit", function (e) {
    e.preventDefault();
    var text = chatInput.value;
    chatInput.value = "";
    sendMessage(text);
  });

  chatInput.addEventListener("keydown", function (e) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      chatForm.dispatchEvent(new Event("submit"));
    }
  });

  tabs.forEach(function (tab) {
    tab.addEventListener("click", function () {
      switchTab(tab.dataset.tab);
    });
  });

  // ── Init ──
  connect();
})();
