# TFS Paster

Windows 小工具：用全域熱鍵把剪貼簿中的 HTML（含圖片）整理/修補後，貼到 TFS / Azure DevOps 的網頁編輯器中，避免直接 `Ctrl+V` 造成格式或圖片問題。

## 功能概要

- 全域熱鍵觸發（預設：`Alt + Shift + D`）
- 只在「目前前景視窗是瀏覽器」時執行（Chrome / Firefox / Edge）
- 備份剪貼簿 → 讀取 `HTML Format` →（可選）縮減 HTML → 修補圖片引用 → 更新 HTML Header 偏移 → 寫回剪貼簿
- 自動送出按鍵：`Ctrl+A` → Backspace 清空 → `Ctrl+V` 貼上
- 完成後還原原本剪貼簿內容
- Debug 模式可落地 `Source.html` / `Patched.html` 方便排查

## 需求

- Windows
- Python 3.x
- `pywin32`（見 `requirements.txt`）

> `tkinter` 為 Python 內建（一般安裝會有）。

## 安裝

在專案根目錄（有 `main.py` 那層）執行：

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

## 使用

啟動常駐模式（會出現小型狀態視窗）：

```powershell
python .\main.py
```

- 切到你的瀏覽器（TFS / Azure DevOps 編輯器所在分頁）
- 先把來源內容複製到剪貼簿（確保剪貼簿內含 HTML 格式）
- 按下熱鍵觸發（預設 `Alt + Shift + D`）

一次性執行（無 GUI；適合腳本/排程）：

```powershell
python .\main.py Quiet
```

## 設定（Config.ini）

設定檔：`Config.ini`

### General

- `Debug`：`1` 會輸出除錯檔（`Source.html` / `Patched.html`）
- `PreShrinkHtml`：貼上前先做一次 HTML 精簡（移除部分註解等）
- `PostShrinkHtml`：圖片處理完後再做一次 HTML 精簡

### Hotkey

預設：

```ini
[Hotkey]
CTRL=0
ALT=1
SHIFT=1
KEY=d
```

- `KEY` 目前設計為單一字元（程式內使用 `ord(key.upper())`）

### Timing

`Timing` 區塊用來調整：剪貼簿讀寫延遲、輪詢間隔、圖片處理等待時間、按鍵按下時間等。
若遇到「貼上太快/太慢」或「剪貼簿被占用」類問題，通常優先調整這裡。

## 日誌與除錯檔

- 執行日誌：`%TEMP%\TFS Paster\TFS Paster.log`（每次啟動會覆寫）
- Debug 落地檔（`Debug=1`）：`%TEMP%\TFS Paster\TFS Paster Log\Source.html` / `Patched.html`

## 測試

```powershell
pytest
```

## 常見問題

- 熱鍵註冊失敗（已被其他程式佔用）：請修改 `Config.ini` 的 `Hotkey` 設定。
- 顯示 `Active window is not a browser`：確認前景視窗是瀏覽器，且視窗標題能被程式辨識（不同語系/瀏覽器版本可能影響）。
- 顯示 `No HTML format in clipboard`：來源需提供 HTML 格式（純文字可能不會有 `HTML Format`）。
- 顯示 `Clipboard idle timeout`：可嘗試提高 `ClipboardIdleTimeoutMs` 或增加延遲。
