# Native AI compatibility

Verified against vendor documentation on 2026-10-11. Vendor support changes over
time, so release testing must use the current official compatibility lists.

Official references: [Apple Foundation Models](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel),
[ML Kit Prompt API setup](https://developers.google.com/ml-kit/genai/prompt/android/get-started),
and [ML Kit device support](https://developers.google.com/ml-kit/genai#device_support).

| Platform | Sarti requirement | Native AI requirement | Fallback |
| --- | --- | --- | --- |
| iOS | Existing app deployment target; native symbols are availability guarded | iOS 26+, Apple Intelligence-capable hardware, enabled/supported language and region, downloaded model ready | Deterministic parser |
| Android | Android API 26 or later | Device on Google's Prompt API list, AICore present, Gemini Nano model status `AVAILABLE`, locked bootloader | Deterministic parser |

On Android, `DOWNLOADABLE` and `DOWNLOADING` currently use the deterministic
fallback rather than starting a large model download without the parent's
knowledge. On iOS, model-not-ready, Apple Intelligence disabled, and unsupported
hardware also use the deterministic fallback.

Google's Prompt API list currently spans selected Pixel, Honor, iQOO, Lenovo,
Motorola, OnePlus, OPPO, POCO, realme, Samsung, Sharp, Sony, vivo, and Xiaomi
models. The official list is the source of truth; Sarti deliberately avoids a
hard-coded device allowlist and trusts the runtime availability result.

## Release matrix still required

- One eligible physical iPhone with the production OS and Apple Intelligence
  model ready.
- At least one physical Android device for each Gemini Nano generation Sarti
  intends to support.
- Offline inference, unsupported-device fallback, disabled/model-not-ready state,
  non-English input, malformed response, repeated requests/quota, and app
  background/foreground transitions.
- Confirmation and Undo on each platform.

Simulators, emulators, compilation, and mocked method channels do not prove that
the vendor model executes locally on shipping hardware.
