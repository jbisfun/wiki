# ios-webusb

適用於 iPhone 和 iPad 的 WebUSB 驅動程式。網頁透過 `navigator.usb` 取得裝置，並在 wasm 中自行執行驅動程式：以 [rusbmux](https://github.com/abdullah-albanna/rusbmux)（內建副本，已移植到 WebUSB）處理 usbmux 協定，並以 [idevice](https://github.com/jkcoxson/idevice) 處理 lockdown、配對與服務。不需要常駐程式，不需要擴充功能，沒有任何原生元件。可在以 Chromium 為基礎的瀏覽器中運作。

同一個驅動程式也有搭配 gpui 系統匣的原生建置版本，供本機工具使用。

## Web

```sh
just web     # -> web/pkg (wasm-bindgen --target web)
just serve   # demo page on http://localhost:8000
```

```js
import init, { IosDevice } from "./pkg/ios_webusb_web.js";
await init();

const device = await IosDevice.request();          // browser chooser; call from a click
// or: const [device] = await IosDevice.authorized(); // devices granted before

// The page is the host: keep one SystemBUID and the pair record per device.
const record = await device.pair(savedRecord, systemBuid); // "Trust This Computer?" on first use
await device.getValue("ProductVersion");

const afc = await device.startService("com.apple.afc");    // TLS set up when needed
await afc.write(bytes); const reply = await afc.read(65536);
const lockdownd = await device.connect(62078);             // raw TCP; sendPlist/readPlist frame plists
```

Linux 需要 udev 規則，瀏覽器才能開啟裝置，而且不能有其他程式占用該裝置：

```sh
sudo cp udev/70-ios-webusb.rules /etc/udev/rules.d/ && sudo udevadm control --reload
sudo systemctl mask --now usbmuxd
```

## 原生系統匣

`just tray`（`--show` 會開啟視窗）。它會在 `$XDG_RUNTIME_DIR/ios-webusb/usbmuxd` 提供 usbmuxd socket（用 `USBMUXD_SOCKET_ADDRESS` 讓工具指向它），列出裝置、為裝置配對，並可**釋放**裝置，讓網頁取得它。同一時間只有一個驅動程式能擁有裝置。配對記錄儲存在 `~/.local/share/ios-webusb/lockdown`。

## 內建 rusbmux 的變更

- 以 nusb 的 WebUSB 後端建置為 `wasm32-unknown-unknown`。在該目標上，常駐程式、Wi-Fi 和檔案系統部分都不會編譯。工作會在頁面的事件迴圈上執行（`rt.rs`）。WebUSB 控制代碼被標記為 `Send`，因為沒有 atomics 的 wasm 是單執行緒的。
- `preflight_with_buid` 讓主機可以提供自己的 SystemBUID。
- `idevice` 固定為精確的 `=0.1.68`（`=`），因為內建的程式碼是針對該版本撰寫的。
- lockdown 目錄可透過 `rusbmux::handler::set_lockdown_path` 設定，因此原生常駐程式可以用非特權身分執行。
