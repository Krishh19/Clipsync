import { useState, useEffect } from "react";
import logoSvg from "./assets/logo.svg";
import "./App.css";

// Interface definitions matching Rust models
interface ServerStatus {
  ip: string;
  port: number;
  connected_devices_count: number;
  is_running: boolean;
  is_paused?: boolean;
}

interface DeviceRow {
  id: string;
  name: string;
  platform: string;
  created_at: number;
  last_seen: number;
  revoked: boolean;
}

interface ItemRow {
  id: string;
  direction: "in" | "out";
  kind: "text" | "link" | "image" | "video" | "file";
  device_id?: string;
  text?: string;
  file_path?: string;
  file_name?: string;
  mime?: string;
  size?: number;
  created_at: number;
}

interface AppConfig {
  port: number;
  save_folder: string;
  max_file_size_mb: number;
  copy_text_links: boolean;
  copy_images: boolean;
  copy_videos_as_files: boolean;
  notifications_on_receive: boolean;
  auto_send_clipboard: boolean;
  send_hotkey: string;
  start_with_windows: boolean;
  retention_days: number;
  retention_max_items: number;
  device_name: string;
  server_device_id: string;
}

interface QrData {
  url: string;
  svg: string;
  expires_in_seconds: number;
}

interface PreviewImage {
  id: string;
  url: string;
  fileName: string;
  filePath: string;
  size?: number;
  date?: number;
}

// Safely invoke Tauri commands with browser fallback
async function tauriInvoke<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  if (typeof window !== "undefined" && (window as unknown as { __TAURI_INTERNALS__?: unknown }).__TAURI_INTERNALS__) {
    const { invoke } = await import("@tauri-apps/api/core");
    return invoke<T>(cmd, args);
  }
  // Browser dev mock fallback
  console.log(`[Tauri Mock Invoke] ${cmd}`, args);
  if (cmd === "get_status") {
    return { ip: "192.168.1.100", port: 47821, connected_devices_count: 1, is_running: true, is_paused: false } as T;
  }
  if (cmd === "list_devices") {
    return [
      { id: "dev-1", name: "Pixel 8 Pro", platform: "android", created_at: Date.now() / 1000 - 86400, last_seen: Date.now() / 1000 - 300, revoked: false },
    ] as T;
  }
  if (cmd === "get_history") {
    return [
      { id: "item-1", direction: "in", kind: "text", text: "https://github.com/ClipSync/clipsync", created_at: Date.now() / 1000 - 60 },
      { id: "item-2", direction: "in", kind: "image", file_name: "IMG_20261123.jpg", file_path: "C:\\Downloads\\IMG_20261123.jpg", size: 2450000, created_at: Date.now() / 1000 - 1800 },
      { id: "item-3", direction: "out", kind: "file", file_name: "Document_2026.pdf", file_path: "C:\\Documents\\Document_2026.pdf", size: 512000, created_at: Date.now() / 1000 - 3600 },
    ] as T;
  }
  if (cmd === "get_settings") {
    return {
      port: 47821,
      save_folder: "C:\\Users\\User\\Downloads\\ClipSync",
      max_file_size_mb: 50,
      copy_text_links: true,
      copy_images: true,
      copy_videos_as_files: false,
      notifications_on_receive: true,
      auto_send_clipboard: false,
      send_hotkey: "Ctrl+Shift+S",
      start_with_windows: false,
      retention_days: 30,
      retention_max_items: 500,
      device_name: "Windows PC",
      server_device_id: "pc-uuid-1234",
    } as T;
  }
  if (cmd === "get_pair_qr") {
    return {
      url: "clipsync://pair?host=192.168.1.100&port=47821&token=demo",
      svg: `<svg viewBox="0 0 100 100" width="180" height="180"><rect width="100" height="100" fill="#2563eb"/><text x="50" y="55" fill="white" font-size="12" text-anchor="middle">QR Preview</text></svg>`,
      expires_in_seconds: 300,
    } as T;
  }
  if (cmd === "read_image_base64") {
    return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='100' height='100'><rect width='100' height='100' fill='%233b82f6'/><text x='50%' y='50%' fill='white' font-size='12' text-anchor='middle'>Photo</text></svg>" as T;
  }
  return {} as T;
}

function formatRelativeTime(timestampSec: number): string {
  const diffSec = Math.floor(Date.now() / 1000 - timestampSec);
  if (diffSec < 60) return "Just now";
  if (diffSec < 3600) return `${Math.floor(diffSec / 60)}m ago`;
  if (diffSec < 86400) return `${Math.floor(diffSec / 3600)}h ago`;
  return new Date(timestampSec * 1000).toLocaleDateString([], { month: "short", day: "numeric" });
}

export default function App() {
  const [activeTab, setActiveTab] = useState<"home" | "history" | "devices" | "settings" | "help">("home");
  const [status, setStatus] = useState<ServerStatus | null>(null);
  const [devices, setDevices] = useState<DeviceRow[]>([]);
  const [history, setHistory] = useState<ItemRow[]>([]);
  const [settings, setSettings] = useState<AppConfig | null>(null);
  const [qrModalOpen, setQrModalOpen] = useState(false);
  const [qrData, setQrData] = useState<QrData | null>(null);
  const [countdown, setCountdown] = useState(300);
  const [quickSendText, setQuickSendText] = useState("");
  const [message, setMessage] = useState<string | null>(null);

  // Media Viewer & Thumbnail states
  const [thumbnails, setThumbnails] = useState<Record<string, string>>({});
  const [previewImage, setPreviewImage] = useState<PreviewImage | null>(null);
  const [zoomLevel, setZoomLevel] = useState(1);

  // Search & Filter states
  const [searchQuery, setSearchQuery] = useState("");
  const [filterType, setFilterType] = useState<"all" | "image" | "file" | "text" | "link">("all");

  // Drag and Drop & File Upload states
  const [isDragging, setIsDragging] = useState(false);
  const [pendingFile, setPendingFile] = useState<{ path: string; name: string; size: number } | null>(null);

  useEffect(() => {
    let unlisten: (() => void) | undefined;
    const isTauri =
      typeof window !== "undefined" &&
      Boolean((window as unknown as { __TAURI_INTERNALS__?: unknown }).__TAURI_INTERNALS__);

    if (isTauri) {
      import("@tauri-apps/api/webview")
        .then(({ getCurrentWebview }) =>
          getCurrentWebview().onDragDropEvent(async (event) => {
            if (event.payload.type === "enter" || event.payload.type === "over") {
              setIsDragging(true);
            } else if (event.payload.type === "leave") {
              setIsDragging(false);
            } else if (event.payload.type === "drop") {
              setIsDragging(false);
              const paths = event.payload.paths;
              if (paths && paths.length > 0) {
                try {
                  const info = await tauriInvoke<{ path: string; name: string; size: number }>(
                    "get_file_info",
                    { path: paths[0] }
                  );
                  setPendingFile(info);
                } catch (e) {
                  showToast(`Could not read dropped file: ${e}`);
                }
              }
            }
          })
        )
        .then((fn) => {
          unlisten = fn;
        })
        .catch(() => {});
    }

    return () => {
      if (unlisten) unlisten();
    };
  }, []);

  const showToast = (msg: string) => {
    setMessage(msg);
    setTimeout(() => setMessage(null), 3000);
  };

  const loadData = async () => {
    try {
      const s = await tauriInvoke<ServerStatus>("get_status");
      setStatus(s);
      const d = await tauriInvoke<DeviceRow[]>("list_devices");
      setDevices(d);
      const h = await tauriInvoke<ItemRow[]>("get_history", { limit: 100 });
      setHistory(h);
      const cfg = await tauriInvoke<AppConfig>("get_settings");
      setSettings(cfg);

      // Lazily pre-load thumbnails for visible images
      h.forEach(async (item) => {
        if (item.kind === "image" && item.file_path && !thumbnails[item.id]) {
          try {
            const b64 = await tauriInvoke<string>("read_image_base64", { path: item.file_path });
            setThumbnails((prev) => ({ ...prev, [item.id]: b64 }));
          } catch (_) {
            // Ignore if image file is not on local disk
          }
        }
      });
    } catch (e) {
      console.error("Error loading data:", e);
    }
  };

  useEffect(() => {
    loadData();
    const interval = setInterval(loadData, 5000);
    return () => clearInterval(interval);
  }, []);

  // Keyboard shortcut to close lightbox
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        setPreviewImage(null);
        setQrModalOpen(false);
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, []);

  const openQrModal = async () => {
    try {
      const data = await tauriInvoke<QrData>("get_pair_qr");
      setQrData(data);
      setCountdown(data.expires_in_seconds);
      setQrModalOpen(true);
    } catch (e) {
      showToast("Failed to generate pairing QR");
    }
  };

  useEffect(() => {
    if (!qrModalOpen) return;
    const timer = setInterval(() => {
      setCountdown((prev) => {
        if (prev <= 1) {
          clearInterval(timer);
          return 0;
        }
        return prev - 1;
      });
    }, 1000);
    return () => clearInterval(timer);
  }, [qrModalOpen]);

  const handleSendText = async () => {
    if (!quickSendText.trim()) return;
    try {
      const delivered = await tauriInvoke<number>("send_text_to_phone", { text: quickSendText });
      if (delivered > 0) {
        showToast(`Sent to ${delivered} phone${delivered > 1 ? "s" : ""}`);
      } else {
        showToast("Saved to history (0 phones connected — pair/open app on phone)");
      }
      setQuickSendText("");
      loadData();
    } catch (e) {
      showToast(`Send failed: ${e}`);
    }
  };

  const handleSendPendingFile = async () => {
    if (!pendingFile) return;
    try {
      const delivered = await tauriInvoke<number>("send_file_to_phone", { input: { file_path: pendingFile.path } });
      if (delivered > 0) {
        showToast(`Sent ${pendingFile.name} to ${delivered} phone${delivered > 1 ? "s" : ""}`);
      } else {
        showToast(`Queued ${pendingFile.name} (0 phones connected — pair/open app on phone)`);
      }
      setPendingFile(null);
      loadData();
    } catch (e) {
      showToast(`Send failed: ${e}`);
    }
  };

  const handlePickFile = async () => {
    try {
      const picked = await tauriInvoke<{ path: string; name: string; size: number } | null>("pick_file");
      if (picked) {
        setPendingFile(picked);
      }
    } catch (e) {
      showToast(`File picker failed: ${e}`);
    }
  };

  const handleRevoke = async (id: string) => {
    if (!confirm("Revoke this paired phone?")) return;
    try {
      await tauriInvoke("revoke_device", { deviceId: id });
      showToast("Device revoked");
      loadData();
    } catch (e) {
      showToast(`Revoke failed: ${e}`);
    }
  };

  const handleTogglePause = async () => {
    try {
      const paused = await tauriInvoke<boolean>("toggle_pause_receiving");
      showToast(paused ? "Clipboard receiving paused" : "Clipboard receiving resumed");
      loadData();
    } catch (e) {
      showToast(`Toggle pause failed: ${e}`);
    }
  };

  const handleOpenFile = async (path: string) => {
    try {
      await tauriInvoke("open_file", { path });
      showToast("Opened file in default app");
    } catch (e) {
      showToast(`Open file failed: ${e}`);
    }
  };

  const handleRevealInFolder = async (path: string) => {
    try {
      await tauriInvoke("reveal_in_folder", { path });
      showToast("Revealed in Explorer");
    } catch (e) {
      showToast(`Reveal failed: ${e}`);
    }
  };

  const handleViewImage = async (item: ItemRow) => {
    if (!item.file_path) return;
    try {
      let b64 = thumbnails[item.id];
      if (!b64) {
        b64 = await tauriInvoke<string>("read_image_base64", { path: item.file_path });
        setThumbnails((prev) => ({ ...prev, [item.id]: b64 }));
      }
      setPreviewImage({
        id: item.id,
        url: b64,
        fileName: item.file_name || "Photo",
        filePath: item.file_path,
        size: item.size,
        date: item.created_at,
      });
      setZoomLevel(1);
    } catch (e) {
      showToast(`Could not load image: ${e}`);
    }
  };

  const handleCopyHistory = async (id: string) => {
    try {
      await tauriInvoke("copy_history_item", { id });
      showToast("Copied to clipboard");
    } catch (e) {
      showToast(`Copy failed: ${e}`);
    }
  };

  const handleDeleteHistory = async (id: string) => {
    try {
      await tauriInvoke("delete_history_item", { id });
      showToast("Item deleted");
      loadData();
    } catch (e) {
      showToast(`Delete failed: ${e}`);
    }
  };

  const handleClearHistory = async () => {
    if (!confirm("Clear all transfer history?")) return;
    try {
      await tauriInvoke("clear_history");
      showToast("History cleared");
      loadData();
    } catch (e) {
      showToast(`Clear failed: ${e}`);
    }
  };

  const handleSaveSettings = async () => {
    if (!settings) return;
    try {
      await tauriInvoke("set_settings", { settings });
      showToast("Settings saved");
    } catch (e) {
      showToast(`Save settings failed: ${e}`);
    }
  };

  // Filter history
  const filteredHistory = history.filter((item) => {
    if (filterType !== "all" && item.kind !== filterType) return false;
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      const matchText = item.text?.toLowerCase().includes(q);
      const matchFile = item.file_name?.toLowerCase().includes(q);
      const matchPath = item.file_path?.toLowerCase().includes(q);
      return Boolean(matchText || matchFile || matchPath);
    }
    return true;
  });

  const imageCount = history.filter((i) => i.kind === "image").length;
  const fileCount = history.filter((i) => i.kind === "file" || i.kind === "video").length;
  const textCount = history.filter((i) => i.kind === "text").length;
  const linkCount = history.filter((i) => i.kind === "link").length;

  return (
    <div className="app-container">
      {/* Toast */}
      {message && <div className="toast">{message}</div>}

      {/* Header */}
      <header className="header">
        <div className="brand">
          <img src={logoSvg} alt="ClipSync" className="brand-logo-img" />
          <div>
            <h1 className="brand-title">ClipSync</h1>
            <p className="brand-subtitle">Seamless Local Clipboard & File Sync</p>
          </div>
        </div>
        <div className="status-badge">
          <span className={`status-dot ${status?.is_running ? "active" : ""}`} />
          {status?.is_running ? `Online :${status?.port}` : "Offline"}
        </div>
      </header>

      {/* Navigation Tabs */}
      <nav className="tab-nav">
        {(["home", "history", "devices", "settings", "help"] as const).map((tab) => (
          <button
            key={tab}
            className={`tab-btn ${activeTab === tab ? "active" : ""}`}
            onClick={() => setActiveTab(tab)}
          >
            {tab.charAt(0).toUpperCase() + tab.slice(1)}
          </button>
        ))}
      </nav>

      {/* Main Content Area */}
      <main className="tab-content">
        {/* HOME TAB */}
        {activeTab === "home" && (
          <div className="tab-pane home-pane">
            <div className="card-grid">
              {/* Server Status Card */}
              <div className="card">
                <h3>Server Status</h3>
                <div className="metric">
                  <span className="metric-label">Local Endpoint</span>
                  <span className="metric-val">{status ? `${status.ip}:${status.port}` : "Loading..."}</span>
                </div>
                <div className="metric">
                  <span className="metric-label">Connected Phones</span>
                  <span className="metric-val">{status?.connected_devices_count ?? 0}</span>
                </div>
                <div className="metric">
                  <span className="metric-label">Receiving Status</span>
                  <span className="metric-val">{status?.is_paused ? "Paused" : "Active"}</span>
                </div>
                <div style={{ display: "flex", gap: "8px", marginTop: "12px" }}>
                  <button className="primary-btn pair-btn" style={{ flex: 1 }} onClick={openQrModal}>
                    + Pair New Phone
                  </button>
                  <button className="btn-sm" onClick={handleTogglePause}>
                    {status?.is_paused ? "Resume" : "Pause"}
                  </button>
                </div>
              </div>

              {/* Push to Phone Card */}
              <div className="card">
                <h3>Push to Phone</h3>
                <p className="subtext">Send quick snippets, links, or files to your phone.</p>
                <textarea
                  className="input-textarea"
                  rows={2}
                  placeholder="Paste or type text to send..."
                  value={quickSendText}
                  onChange={(e) => setQuickSendText(e.target.value)}
                />
                <div style={{ display: "flex", gap: "8px", marginTop: "8px" }}>
                  <button className="primary-btn" style={{ flex: 1, marginTop: 0 }} onClick={handleSendText}>
                    Send Text
                  </button>
                  <button
                    className="btn-sm"
                    style={{ whiteSpace: "nowrap" }}
                    onClick={handlePickFile}
                  >
                    + Pick File
                  </button>
                </div>

                {/* Drag & Drop Zone */}
                <div
                  className={`dropzone ${isDragging ? "active" : ""}`}
                  onDragOver={(e) => {
                    e.preventDefault();
                    setIsDragging(true);
                  }}
                  onDragLeave={() => setIsDragging(false)}
                  onClick={handlePickFile}
                >
                  <span className="dropzone-icon">📁</span>
                  <span className="dropzone-text">Drop photos or files to send to phone</span>
                  <span className="dropzone-hint">Or click to browse from PC</span>
                </div>

                {/* Pending file confirmation */}
                {pendingFile && (
                  <div style={{ marginTop: "10px", padding: "8px", background: "rgba(59,130,246,0.12)", borderRadius: "6px", border: "1px solid rgba(59,130,246,0.3)" }}>
                    <div style={{ fontSize: "0.85rem", fontWeight: 600 }}>Ready to send: {pendingFile.name}</div>
                    <div style={{ fontSize: "0.75rem", color: "var(--text-secondary)" }}>{(pendingFile.size / 1024).toFixed(1)} KB</div>
                    <div style={{ display: "flex", gap: "6px", marginTop: "6px" }}>
                      <button className="primary-btn" style={{ flex: 1, padding: "0.4rem", marginTop: 0 }} onClick={handleSendPendingFile}>
                        Confirm Send
                      </button>
                      <button className="btn-sm" onClick={() => setPendingFile(null)}>Cancel</button>
                    </div>
                  </div>
                )}
              </div>
            </div>

            {/* RECENT TRANSFERS CARD */}
            <div className="card mt-4">
              <div className="card-header-flex">
                <div>
                  <h3>Recent Transfers</h3>
                  <p className="subtext">Persistent history from local SQLite database</p>
                </div>
                <button className="link-btn" onClick={() => setActiveTab("history")}>
                  View all ({history.length}) &rarr;
                </button>
              </div>

              {history.length === 0 ? (
                <div className="empty-state-rich">
                  <div className="empty-icon">📲</div>
                  <h4>No transfers yet</h4>
                  <p>Share photos, links, or files from your paired Android phone or use &quot;Push to Phone&quot; to transfer items here.</p>
                  <button className="primary-btn pair-btn mt-2" onClick={openQrModal}>
                    + Pair New Phone
                  </button>
                </div>
              ) : (
                <ul className="item-list">
                  {history.slice(0, 5).map((item) => {
                    const isImage = item.kind === "image";
                    const isLink = item.kind === "link";
                    const isFile = item.kind === "file" || item.kind === "video";
                    const thumb = thumbnails[item.id];

                    return (
                      <li key={item.id} className="rich-item-row">
                        {/* Thumbnail / Icon */}
                        {isImage ? (
                          <div
                            className="item-thumb-wrapper"
                            title="Click to view photo"
                            onClick={() => handleViewImage(item)}
                          >
                            {thumb ? (
                              <img src={thumb} alt={item.file_name} className="item-thumb-img" />
                            ) : (
                              <span className="item-thumb-icon">🖼️</span>
                            )}
                          </div>
                        ) : (
                          <div className="item-thumb-wrapper" style={{ cursor: "default" }}>
                            <span className="item-thumb-icon">
                              {isLink ? "🔗" : isFile ? "📄" : "📝"}
                            </span>
                          </div>
                        )}

                        {/* Main info */}
                        <div className="rich-item-main">
                          <div className="rich-item-header">
                            <span className={`kind-tag kind-${item.kind}`}>{item.kind}</span>
                            <span className={`badge-dir ${item.direction === "in" ? "badge-dir-in" : "badge-dir-out"}`}>
                              {item.direction === "in" ? "← Phone" : "→ PC"}
                            </span>
                            <span className="rich-item-sub">
                              {formatRelativeTime(item.created_at)}
                            </span>
                          </div>
                          <div className="rich-item-title">
                            {item.text || item.file_name || "Attachment"}
                          </div>
                          {item.size && (
                            <div className="rich-item-sub">
                              {(item.size / 1024).toFixed(1)} KB
                            </div>
                          )}
                        </div>

                        {/* Actions */}
                        <div className="item-actions">
                          {isImage && (
                            <button className="btn-sm" onClick={() => handleViewImage(item)}>
                              View 🖼️
                            </button>
                          )}
                          {isFile && item.file_path && (
                            <button className="btn-sm" onClick={() => handleOpenFile(item.file_path!)}>
                              Open 📄
                            </button>
                          )}
                          {isLink && item.text && (
                            <button
                              className="btn-sm"
                              onClick={() => {
                                handleOpenFile(item.text!);
                              }}
                            >
                              Open 🔗
                            </button>
                          )}
                          <button className="btn-sm" onClick={() => handleCopyHistory(item.id)}>
                            Copy
                          </button>
                          {item.file_path && (
                            <button
                              className="btn-sm"
                              title="Show in Explorer"
                              onClick={() => handleRevealInFolder(item.file_path!)}
                            >
                              📁
                            </button>
                          )}
                        </div>
                      </li>
                    );
                  })}
                </ul>
              )}
            </div>
          </div>
        )}

        {/* HISTORY TAB */}
        {activeTab === "history" && (
          <div className="tab-pane">
            <div className="card">
              <div className="card-header-flex">
                <div>
                  <h3>Transfer History ({history.length})</h3>
                  <p className="subtext">Browse, search, inspect photos, and launch files</p>
                </div>
                {history.length > 0 && (
                  <button className="btn-danger-sm" onClick={handleClearHistory}>
                    Clear History
                  </button>
                )}
              </div>

              {/* Filter and Search Toolbar */}
              <div className="filter-search-bar">
                <div className="search-input-wrapper">
                  <input
                    type="text"
                    className="search-input"
                    placeholder="Search by text, filename, or path..."
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                  />
                  {searchQuery && (
                    <button className="search-clear-btn" onClick={() => setSearchQuery("")}>
                      ✕
                    </button>
                  )}
                </div>

                <div className="filter-pills">
                  <button
                    className={`filter-pill ${filterType === "all" ? "active" : ""}`}
                    onClick={() => setFilterType("all")}
                  >
                    All ({history.length})
                  </button>
                  <button
                    className={`filter-pill ${filterType === "image" ? "active" : ""}`}
                    onClick={() => setFilterType("image")}
                  >
                    Photos 🖼️ ({imageCount})
                  </button>
                  <button
                    className={`filter-pill ${filterType === "file" ? "active" : ""}`}
                    onClick={() => setFilterType("file")}
                  >
                    Files 📁 ({fileCount})
                  </button>
                  <button
                    className={`filter-pill ${filterType === "text" ? "active" : ""}`}
                    onClick={() => setFilterType("text")}
                  >
                    Text 📝 ({textCount})
                  </button>
                  <button
                    className={`filter-pill ${filterType === "link" ? "active" : ""}`}
                    onClick={() => setFilterType("link")}
                  >
                    Links 🔗 ({linkCount})
                  </button>
                </div>
              </div>

              {filteredHistory.length === 0 ? (
                <div className="empty-state-rich">
                  <div className="empty-icon">📋</div>
                  <h4>No matching transfers</h4>
                  <p>Try clearing your search query or switching to another filter tab.</p>
                </div>
              ) : (
                <ul className="item-list">
                  {filteredHistory.map((item) => {
                    const isImage = item.kind === "image";
                    const isLink = item.kind === "link";
                    const isFile = item.kind === "file" || item.kind === "video";
                    const thumb = thumbnails[item.id];

                    return (
                      <li key={item.id} className="rich-item-row">
                        {/* Thumbnail */}
                        {isImage ? (
                          <div
                            className="item-thumb-wrapper"
                            title="Click to view full photo"
                            onClick={() => handleViewImage(item)}
                          >
                            {thumb ? (
                              <img src={thumb} alt={item.file_name} className="item-thumb-img" />
                            ) : (
                              <span className="item-thumb-icon">🖼️</span>
                            )}
                          </div>
                        ) : (
                          <div className="item-thumb-wrapper" style={{ cursor: "default" }}>
                            <span className="item-thumb-icon">
                              {isLink ? "🔗" : isFile ? "📄" : "📝"}
                            </span>
                          </div>
                        )}

                        {/* Content */}
                        <div className="rich-item-main">
                          <div className="rich-item-header">
                            <span className={`kind-tag kind-${item.kind}`}>{item.kind}</span>
                            <span className={`badge-dir ${item.direction === "in" ? "badge-dir-in" : "badge-dir-out"}`}>
                              {item.direction === "in" ? "← From Phone" : "→ To Phone"}
                            </span>
                            <span className="rich-item-sub">
                              {formatRelativeTime(item.created_at)} •{" "}
                              {new Date(item.created_at * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
                            </span>
                          </div>
                          <div className="rich-item-title">
                            {item.text || item.file_name || "Attachment"}
                          </div>
                          {item.size && (
                            <div className="rich-item-sub">
                              Size: {(item.size / 1024).toFixed(1)} KB {item.file_path && `• ${item.file_path}`}
                            </div>
                          )}
                        </div>

                        {/* Action Buttons */}
                        <div className="item-actions">
                          {isImage && (
                            <button className="btn-sm" onClick={() => handleViewImage(item)}>
                              View 🖼️
                            </button>
                          )}
                          {isFile && item.file_path && (
                            <button className="btn-sm" onClick={() => handleOpenFile(item.file_path!)}>
                              Open 📄
                            </button>
                          )}
                          {isLink && item.text && (
                            <button className="btn-sm" onClick={() => handleOpenFile(item.text!)}>
                              Open 🔗
                            </button>
                          )}
                          <button className="btn-sm" onClick={() => handleCopyHistory(item.id)}>
                            Copy
                          </button>
                          {item.file_path && (
                            <button
                              className="btn-sm"
                              title="Reveal in Explorer"
                              onClick={() => handleRevealInFolder(item.file_path!)}
                            >
                              📁
                            </button>
                          )}
                          <button className="btn-sm text-danger" onClick={() => handleDeleteHistory(item.id)}>
                            Delete
                          </button>
                        </div>
                      </li>
                    );
                  })}
                </ul>
              )}
            </div>
          </div>
        )}

        {/* DEVICES TAB */}
        {activeTab === "devices" && (
          <div className="tab-pane">
            <div className="card">
              <div className="card-header-flex">
                <h3>Paired Phones</h3>
                <button className="primary-btn" onClick={openQrModal}>+ Pair New Phone</button>
              </div>
              {devices.length === 0 ? (
                <div className="empty-state-rich">
                  <div className="empty-icon">🔒</div>
                  <h4>No paired Android devices</h4>
                  <p>ClipSync connects directly over your local Wi-Fi with TLS certificate pinning. No account, internet relay, or cloud storage required.</p>
                  <button className="primary-btn mt-2" onClick={openQrModal}>
                    + Pair Your Android Phone Now
                  </button>
                </div>
              ) : (
                <ul className="device-list">
                  {devices.map((dev) => (
                    <li key={dev.id} className="device-row">
                      <div>
                        <strong>{dev.name}</strong> ({dev.platform})
                        <div className="subtext">
                          Last seen: {new Date(dev.last_seen * 1000).toLocaleString()} {dev.revoked && "• (Revoked)"}
                        </div>
                      </div>
                      {!dev.revoked && (
                        <button className="btn-danger-sm" onClick={() => handleRevoke(dev.id)}>
                          Revoke
                        </button>
                      )}
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </div>
        )}

        {/* SETTINGS TAB */}
        {activeTab === "settings" && settings && (
          <div className="tab-pane">
            <div className="card settings-card">
              <h3>Settings</h3>
              <div className="setting-group">
                <label>Device Name</label>
                <input
                  type="text"
                  className="input-text"
                  value={settings.device_name}
                  onChange={(e) => setSettings({ ...settings, device_name: e.target.value })}
                />
              </div>

              <div className="setting-group">
                <label>Port</label>
                <input
                  type="number"
                  className="input-text"
                  value={settings.port}
                  onChange={(e) => setSettings({ ...settings, port: Number(e.target.value) })}
                />
              </div>

              <div className="setting-group">
                <label>Save Folder</label>
                <input
                  type="text"
                  className="input-text"
                  value={settings.save_folder}
                  onChange={(e) => setSettings({ ...settings, save_folder: e.target.value })}
                />
              </div>

              <div className="setting-group">
                <label>Max File Size (MB)</label>
                <input
                  type="number"
                  className="input-text"
                  value={settings.max_file_size_mb}
                  onChange={(e) => setSettings({ ...settings, max_file_size_mb: Number(e.target.value) })}
                />
              </div>

              <div className="setting-group">
                <label>Global Send Hotkey</label>
                <input
                  type="text"
                  className="input-text"
                  value={settings.send_hotkey}
                  onChange={(e) => setSettings({ ...settings, send_hotkey: e.target.value })}
                />
              </div>

              <div className="toggle-group">
                <label>
                  <input
                    type="checkbox"
                    checked={settings.notifications_on_receive}
                    onChange={(e) => setSettings({ ...settings, notifications_on_receive: e.target.checked })}
                  />
                  Show notification on receiving items
                </label>
              </div>

              <div className="toggle-group">
                <label>
                  <input
                    type="checkbox"
                    checked={settings.auto_send_clipboard}
                    onChange={(e) => setSettings({ ...settings, auto_send_clipboard: e.target.checked })}
                  />
                  Auto-send clipboard when copied on PC
                </label>
              </div>

              <div className="toggle-group">
                <label>
                  <input
                    type="checkbox"
                    checked={settings.start_with_windows}
                    onChange={(e) => setSettings({ ...settings, start_with_windows: e.target.checked })}
                  />
                  Start ClipSync with Windows
                </label>
              </div>

              <button className="primary-btn" onClick={handleSaveSettings}>
                Save Settings
              </button>
            </div>
          </div>
        )}

        {/* HELP TAB */}
        {activeTab === "help" && (
          <div className="tab-pane">
            <div className="card">
              <h3>Help & Keyboard Shortcuts</h3>
              <div className="help-section mt-2">
                <h4>🚀 Fast Hotkey Transfer</h4>
                <p>Press <kbd>Ctrl+Shift+S</kbd> anywhere in Windows to instantly push your current clipboard text or copied file to your paired phone.</p>
              </div>
              <div className="help-section">
                <h4>🖼️ Viewing Photos & Files</h4>
                <p>Click any photo thumbnail in Recent Transfers or History to open the high-res Lightbox viewer. Use &quot;Open 📄&quot; to launch PDFs and files directly with your default Windows application.</p>
              </div>
              <div className="help-section">
                <h4>📲 Android Share Sheet</h4>
                <p>In any Android app (Chrome, Photos, WhatsApp), tap Share and choose <strong>&quot;Send to PC&quot;</strong> to push files up to 50 MB directly into your PC&apos;s Downloads\ClipSync folder.</p>
              </div>
              <div className="help-section">
                <h4>🔒 End-to-End Local Security</h4>
                <p>All transfers use TLS 1.3 with an ECDSA P-256 certificate pinned to your phone during QR pairing. No telemetry, cloud relay, or third-party servers.</p>
              </div>
            </div>
          </div>
        )}
      </main>

      {/* QR PAIRING MODAL */}
      {qrModalOpen && qrData && (
        <div className="modal-backdrop" onClick={() => setQrModalOpen(false)}>
          <div className="modal-card" onClick={(e) => e.stopPropagation()}>
            <h3>Pair New Phone</h3>
            <p className="subtext">Scan this QR code with the ClipSync app on your phone</p>
            <div className="qr-box" dangerouslySetInnerHTML={{ __html: qrData.svg }} />
            <div className="countdown">Expires in {countdown}s</div>
            <button className="primary-btn mt-2" onClick={() => setQrModalOpen(false)}>
              Done
            </button>
          </div>
        </div>
      )}

      {/* PHOTO LIGHTBOX MODAL */}
      {previewImage && (
        <div className="lightbox-backdrop" onClick={() => setPreviewImage(null)}>
          {/* Header */}
          <div className="lightbox-header" onClick={(e) => e.stopPropagation()}>
            <div>
              <div className="lightbox-title">{previewImage.fileName}</div>
              <div className="lightbox-meta">
                {previewImage.size ? `${(previewImage.size / 1024).toFixed(1)} KB • ` : ""}
                {previewImage.date ? new Date(previewImage.date * 1000).toLocaleString() : ""}
              </div>
            </div>
            <div style={{ display: "flex", gap: "8px", alignItems: "center" }}>
              <div className="zoom-controls">
                <button
                  className="btn-sm"
                  title="Zoom Out"
                  onClick={() => setZoomLevel((z) => Math.max(0.5, z - 0.25))}
                >
                  -
                </button>
                <span style={{ fontSize: "0.8rem", minWidth: "45px", textAlign: "center" }}>
                  {Math.round(zoomLevel * 100)}%
                </span>
                <button
                  className="btn-sm"
                  title="Zoom In"
                  onClick={() => setZoomLevel((z) => Math.min(3, z + 0.25))}
                >
                  +
                </button>
                <button className="btn-sm" title="Reset Zoom" onClick={() => setZoomLevel(1)}>
                  Reset
                </button>
              </div>
              <button
                className="btn-sm"
                style={{ fontSize: "1.1rem", padding: "0.2rem 0.6rem" }}
                onClick={() => setPreviewImage(null)}
              >
                ✕
              </button>
            </div>
          </div>

          {/* Body */}
          <div className="lightbox-body" onClick={() => setPreviewImage(null)}>
            <img
              src={previewImage.url}
              alt={previewImage.fileName}
              className="lightbox-img"
              style={{ transform: `scale(${zoomLevel})` }}
              onClick={(e) => e.stopPropagation()}
            />
          </div>

          {/* Footer Toolbar */}
          <div className="lightbox-footer" onClick={(e) => e.stopPropagation()}>
            <div style={{ fontSize: "0.8rem", color: "var(--text-secondary)", overflow: "hidden", textOverflow: "ellipsis", maxWidth: "50%" }}>
              {previewImage.filePath}
            </div>
            <div className="lightbox-actions">
              <button
                className="btn-sm"
                onClick={() => handleOpenFile(previewImage.filePath)}
              >
                Open in Photos 🖼️
              </button>
              <button
                className="btn-sm"
                onClick={() => handleRevealInFolder(previewImage.filePath)}
              >
                Show in Folder 📁
              </button>
              <button
                className="btn-sm"
                onClick={() => handleCopyHistory(previewImage.id)}
              >
                Copy Image 📋
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
