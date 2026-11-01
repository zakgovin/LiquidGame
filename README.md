# Hydrologic 0.7.0 / Гидрологика

[Скачать APK / Download APK](https://github.com/zakgovin/LiquidGame/raw/refs/heads/downloads-v0.7.0/hydrologic-0.7.0-android.apk)

[Скачать ZIP / Download ZIP](https://codeload.github.com/zakgovin/LiquidGame/zip/refs/heads/downloads-v0.7.0)

Если APK зависает при скачивании на телефоне, скачайте ZIP, распакуйте его и откройте APK.

Android 7.0+ / API 24, ARM64 / x86_64, OpenGL ES 3.0. Offline, no permissions. Debug-signed prototype; same signing key as 0.6.0, supports an in-place update.

New in 0.7.0:
- Tilt mode plus Rotate mode: drag around the level centre; water is pulled towards the bottom of the screen.
- Preparation rotation, preserved orientation on pause, reset on restart, adaptive framing.
- Stronger visible phone tilt feedback, up to 9 degrees.
- Closed glass wall volumes with visible thickness, edges and reflections.
- Hazard stripes wrap across each step fold; arrows point downhill.
- Faster water response and depth-based transparency without a scene-depth texture.
- Existing Touch preferences migrate to Rotate; Russian and English are supported.

161 automated checks passed: physics, lifecycle, input migration, native touch at scaled resolution, real rendering, and completion using rotation controls. Physical-phone FPS and gesture comfort for this version remain to be measured.

Авторы / Creators: Zakhar Govin and Codex (OpenAI).

Source: https://github.com/zakgovin/LiquidGame/commit/df674f1f5289e0f6741e9327594fd1c3d9103b7d

SHA-256: `433479948e239efa067d76fc9188bb9c81a06e78e9af8a52ea4b97f705c5a82a`
