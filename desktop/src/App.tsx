import { useState, useEffect } from "react";
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
      { id: "item-2", direction: "in", kind: "image", file_name: "IMG_20261123.jpg", size: 2450000, created_at: Date.now() / 1000 - 1800 },
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
  return {} as T;
}

export function App() {
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
      const h = await tauriInvoke<ItemRow[]>("get_history", { limit: 50 });
      setHistory(h);
      const cfg = await tauriInvoke<AppConfig>("get_settings");
      setSettings(cfg);
    } catch (e) {
      console.error("Error loading data:", e);
    }
  };

  useEffect(() => {
    loadData();
    const interval = setInterval(loadData, 5000);
    return () => clearInterval(interval);
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
      await tauriInvoke("send_text_to_phone", { text: quickSendText });
      showToast("Text sent to phone");
      setQuickSendText("");
      loadData();
    } catch (e) {
      showToast(`Send failed: ${e}`);
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

  const handleOpenFolder = async (path?: string) => {
    try {
      await tauriInvoke("open_folder", { path: path || settings?.save_folder });
      showToast("Opened in Explorer");
    } catch (e) {
      showToast(`Open folder failed: ${e}`);
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

  return (
    <div className="app-container">
      {/* Toast */}
      {message && <div className="toast">{message}</div>}

      {/* Header */}
      <header className="header">
        <div className="brand">
          <div className="brand-logo">CS</div>
          <div>
            <h1 className="brand-title">ClipSync</h1>
            <p className="brand-subtitle">Seamless Local Clipboard Sync</p>
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

              <div className="card">
                <h3>Push Text to Phone</h3>
                <p className="subtext">Send quick snippets or links to your connected phone.</p>
                <textarea
                  className="input-textarea"
                  rows={3}
                  placeholder="Paste or type text to send..."
                  value={quickSendText}
                  onChange={(e) => setQuickSendText(e.target.value)}
                />
                <button className="primary-btn" onClick={handleSendText}>
                  Send to Phone
                </button>
              </div>
            </div>

            <div className="card mt-4">
              <div className="card-header-flex">
                <h3>Recent Transfers</h3>
                <button className="link-btn" onClick={() => setActiveTab("history")}>
                  View all &rarr;
                </button>
              </div>
              {history.length === 0 ? (
                <div className="empty-state-rich">
                  <div className="empty-icon">📲</div>
                  <h4>No transfers yet</h4>
                  <p>Share photos, links, or text from your paired Android phone or use &quot;Push Text to Phone&quot; above to see items here in real time.</p>
                  <button className="primary-btn pair-btn mt-2" onClick={openQrModal}>
                    + Pair New Phone
                  </button>
                </div>
              ) : (
                <ul className="item-list">
                  {history.slice(0, 4).map((item) => (
                    <li key={item.id} className="item-row">
                      <span className={`kind-tag kind-${item.kind}`}>{item.kind}</span>
                      <span className="item-content">{item.text || item.file_name || "Attachment"}</span>
                      <button className="btn-sm" onClick={() => handleCopyHistory(item.id)}>Copy</button>
                    </li>
                  ))}
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
                <h3>Transfer History</h3>
                {history.length > 0 && (
                  <button className="btn-danger-sm" onClick={handleClearHistory}>
                    Clear History
                  </button>
                )}
              </div>
              {history.length === 0 ? (
                <div className="empty-state-rich">
                  <div className="empty-icon">📋</div>
                  <h4>Clipboard history is empty</h4>
                  <p>Inbound transfers from your phone and outbound pushes from your PC will be safely preserved here in your local SQLite database.</p>
                  <button className="btn-sm mt-2" onClick={() => setActiveTab("home")}>
                    Go to Home &rarr;
                  </button>
                </div>
              ) : (
                <ul className="item-list">
                  {history.map((item) => (
                    <li key={item.id} className="item-row">
                      <div className="item-meta">
                        <span className={`kind-tag kind-${item.kind}`}>{item.kind}</span>
                        <span className="item-dir">{item.direction === "in" ? "← Inbound" : "→ Outbound"}</span>
                        <span className="item-time">
                          {new Date(item.created_at * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
                        </span>
                      </div>
                      <div className="item-body">
                        {item.text && <p className="item-text">{item.text}</p>}
                        {item.file_name && (
                          <p className="item-file">
                            📁 <strong>{item.file_name}</strong> {item.size ? `(${(item.size / 1024).toFixed(1)} KB)` : ""}
                          </p>
                        )}
                      </div>
                      <div className="item-actions">
                        <button className="btn-sm" onClick={() => handleCopyHistory(item.id)}>Copy</button>
                        {item.file_path && (
                          <button className="btn-sm" onClick={() => handleOpenFolder(item.file_path)}>Folder</button>
                        )}
                        <button className="btn-sm text-danger" onClick={() => handleDeleteHistory(item.id)}>Delete</button>
                      </div>
                    </li>
                  ))}
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

              <div className="toggle-group">
                <label>
                  <input
                    type="checkbox"
                    checked={settings.copy_text_links}
                    onChange={(e) => setSettings({ ...settings, copy_text_links: e.target.checked })}
                  />
                  <span>Copy received text and links to clipboard</span>
                </label>
              </div>

              <div className="toggle-group">
                <label>
                  <input
                    type="checkbox"
                    checked={settings.copy_images}
                    onChange={(e) => setSettings({ ...settings, copy_images: e.target.checked })}
                  />
                  <span>Copy received images to clipboard</span>
                </label>
              </div>

              <div className="toggle-group">
                <label>
                  <input
                    type="checkbox"
                    checked={settings.copy_videos_as_files}
                    onChange={(e) => setSettings({ ...settings, copy_videos_as_files: e.target.checked })}
                  />
                  <span>Copy received videos as files</span>
                </label>
              </div>

              <div className="toggle-group">
                <label>
                  <input
                    type="checkbox"
                    checked={settings.notifications_on_receive}
                    onChange={(e) => setSettings({ ...settings, notifications_on_receive: e.target.checked })}
                  />
                  <span>Show toast notifications on receive</span>
                </label>
              </div>

              <div className="toggle-group">
                <label>
                  <input
                    type="checkbox"
                    checked={settings.auto_send_clipboard}
                    onChange={(e) => setSettings({ ...settings, auto_send_clipboard: e.target.checked })}
                  />
                  <span>Auto-send PC clipboard text to phone (hotkey recommended instead)</span>
                </label>
              </div>

              <div className="setting-group">
                <label>Send Hotkey</label>
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
                    checked={settings.start_with_windows}
                    onChange={(e) => setSettings({ ...settings, start_with_windows: e.target.checked })}
                  />
                  <span>Start with Windows (launch to tray)</span>
                </label>
              </div>

              <div className="setting-group">
                <label>History Retention (Days)</label>
                <input
                  type="number"
                  className="input-text"
                  value={settings.retention_days}
                  onChange={(e) => setSettings({ ...settings, retention_days: Number(e.target.value) })}
                />
              </div>

              <div className="setting-group">
                <label>History Max Items</label>
                <input
                  type="number"
                  className="input-text"
                  value={settings.retention_max_items}
                  onChange={(e) => setSettings({ ...settings, retention_max_items: Number(e.target.value) })}
                />
              </div>

              <button className="primary-btn mt-4" onClick={handleSaveSettings}>
                Save Settings
              </button>
            </div>
          </div>
        )}

        {/* HELP TAB */}
        {activeTab === "help" && (
          <div className="tab-pane">
            <div className="card">
              <h3>Help & Troubleshooting</h3>
              <div className="help-section">
                <h4>1. Windows Firewall</h4>
                <p>
                  Ensure ClipSync is permitted through Windows Firewall. If pairing or transfers fail, verify that inbound connections are allowed for ClipSync on Private networks.
                </p>
                <div className="code-hint mt-2">
                  <span>To add the firewall rule manually via Administrator Command Prompt:</span>
                  <pre className="code-block">
                    netsh advfirewall firewall add rule name=&quot;ClipSync&quot; dir=in action=allow protocol=TCP localport=47821
                  </pre>
                </div>
              </div>
              <div className="help-section">
                <h4>2. Wi-Fi AP Isolation</h4>
                <p>
                  Some routers enable &quot;AP Isolation&quot; or Guest network restrictions, preventing devices on the same Wi-Fi network from talking to each other. Connect both devices to the standard main Wi-Fi network.
                </p>
              </div>
              <div className="help-section">
                <h4>3. Discovery & Manual IP</h4>
                <p>
                  If mDNS automatic discovery fails, enter your PC&apos;s local IP address and port manually in the Android mobile app.
                </p>
              </div>
              <div className="help-section">
                <h4>4. Security & TLS</h4>
                <p>
                  All traffic is end-to-end encrypted with a local self-signed TLS certificate and SHA-256 certificate pinning established during QR pairing. No cloud or external connection is ever required.
                </p>
              </div>
            </div>
          </div>
        )}
      </main>

      {/* QR Pairing Modal */}
      {qrModalOpen && (
        <div className="modal-backdrop" onClick={() => setQrModalOpen(false)}>
          <div className="modal-card" onClick={(e) => e.stopPropagation()}>
            <h3>Pair Phone with ClipSync</h3>
            <p className="subtext">Scan this QR code in the ClipSync Android app to pair securely.</p>
            <div className="qr-box" dangerouslySetInnerHTML={{ __html: qrData?.svg || "" }} />
            <div className="countdown">
              Token expires in: <strong>{Math.floor(countdown / 60)}:{(countdown % 60).toString().padStart(2, "0")}</strong>
            </div>
            <button className="primary-btn mt-4" onClick={() => setQrModalOpen(false)}>
              Close
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

export default App;
