# HelloRadio V15 User Guide

[简体中文](../zh-CN/user-guide.md) · [Effect catalog](effects.md) · [Animated previews](previews.md)

## Compatibility

This package targets HelloRadio V15: two 16-LED decorative rings and six function-switch LEDs. The tool requires EdgeTX LVGL and RGB LED Lua APIs. Other radio models require their own adaptation.

## Installation and selection

1. Merge this model package's **SCRIPTS** into the SD card root. The result contains SCRIPTS/RGBLED and SCRIPTS/TOOLS.
2. Keep the device's existing RGBLED/v15lib/layout.cfg and the entire v15lib directory. *.luac files are device-generated caches; remove a matching stale cache if updated source is not being loaded.
3. Safely eject USB storage and reboot. Run **v15map** from SYS tools. Existing completed v5.1 calibration remains valid.
4. In model special functions select **RGB LED → one A/B/C file → repeat ON → enable**. Enable one RGB effect at a time, checking both model and global special functions.
5. To follow arming, use your existing arm switch condition to trigger the effect.

When migrating older v15xxx names, update model/global RGB references to the new names before removing old entry files and caches. v15map and v15lib retain their names.

## Four-step calibration

Face the radio with its display at the bottom. Current tool labels are Chinese; the labels below match the display.

1. For ring group 1 select its six-o'clock LED. Set 所在侧 to the physical left/right stick, then press 确定灯位 (confirm position).
2. The moving white LED should travel clockwise. Press 反转方向 (reverse numbering) if needed, then 方向正确 (direction correct).
3. Select the six-o'clock LED for ring group 2.
4. Confirm its clockwise direction, return to the home page and press 保存设置 (save), then 返回 (return) to exit.

Settings are saved to /SCRIPTS/RGBLED/v15lib/layout.cfg, without changing model/mixer/output settings. Re-enable the special function to reload. Each ring has 16 positions at about 22.5° per step. Inner-bottom starts are approximately left 5:15 and right 6:45; calibration determines actual placement.

v15map handles calibration and shared settings only. The home page has 设置 (settings), 关于 (About), 重新校准 (recalibrate), 保存设置 (save settings) and 返回 (return). Each page has one 返回 button, which returns one level; on the home page it exits. Captions are centered horizontally and vertically using the firmware's actual font height.

Settings directly contains brightness, key enable and idle timeout. 油门设置 (throttle settings) contains input source, reversal and smoothing. Return home and save after editing. Palette, static diagnostics, key diagnostics and throttle preview controls have been removed. The tool lights only the white positioning LED during calibration; choose the actual A/B/C preset in model special functions after calibrating once.

关于 (About) lists the author Xu, the GitHub profile [github.com/939008033](https://github.com/939008033), and the email address 939008033@qq.com.

## Which settings apply

- Shared: LED mapping, physical sides, numbering direction, brightness, key enable and idle timeout.
- A automatic presets do not respond to throttle. Each preset defines its colors and direction. Enabling idle timeout also reads physical controls for activity detection.
- B presets use source, reversal and smoothing under 设置 → 油门设置. B01-user retains the palette, path and start angle from older saved configurations, defaulting to a mirrored rainbow on new installs; the simplified tool no longer edits those values. B02–B14 use fixed styles. B15 adds a moving afterburner hotspot.
- C presets map physical sticks according to Mode 1–4 and use brightness, smoothing and key settings. They ignore throttle CHn/reversal and B01 palette/path choices.

油门摇杆 means physical throttle stick; CHn means the selected output. Channel monitor -100% / 0% / +100% maps to progress 0% / 50% / 100%. Default smoothing is about 80 ms; rendering is limited to 20 Hz. Scripts display LEDs only.

## Low power (idle lights-off)

Open **v15map → 设置** and set 低功耗 directly to **关闭 / 5分钟 / 10分钟 / 15分钟** (off / 5 / 10 / 15 minutes). Press 返回 to go home, press 保存设置, then re-enable the effect. The default is off, including when loading older calibration files; recalibration is unnecessary.

All 32 A/B/C presets share this setting. After the selected idle interval, script-controlled rings and key LEDs go dark and animation calculations pause. Operating a control wakes the current effect and restarts the timer. Radio power, screen, model and channel settings are unchanged.

Activity includes sticks, pots/sliders, physical switches, trims, and SW1–SW6 states exposed by the firmware. Small analog jitter, animated colors, telemetry and channel-output changes do not keep the lights awake. The white calibration LED also honors the timeout and wakes on interaction inside v15map. Home and settings pages keep the rings dark.

EdgeTX does not deliver system menu keys such as SYS/RTN or touchscreen events to background RGB scripts. Use a stick or switch to wake lights when navigating system menus. Disabled function keys or keys without readable state cannot wake them either. Key LEDs that Lua lacks permission to control remain managed by firmware.

## Six key LEDs

Throttle fills **keys 3/4 → 2/5 → 1/6 → rings**, counting physical keys left to right. Keys consume 3/19 of total progress, so 50% total does not mean exactly half of each ring is lit.

For assigned function switches, enable 允许 LUA 脚本控制 (allow Lua control) in both OFF and ON columns under 自定义按键 (custom/function switches). Unassigned/disabled keys can remain disabled. In 设置 (settings), select 六键 → 开启 (keys enabled), save and re-enable the effect.

Effects release their own key-color overrides when keys are disabled. v15map neither probes nor takes control of key LEDs. Key functions are preserved.

## Dual-stick controls and combos

C01 follows physical heading/deflection. C02 uses the left stick for color/brightness and the right for speed/direction/width. C03 controls each ring independently. For C04:

1. Center both horizontal axes for about half a second; throttle may remain at minimum.
2. Hold each pose for about half a second, connecting both within 2.5 seconds: **out→in** triggers a pink-white nova; **in→out** an ice-blue wave; **both right→both left** a rainbow swirl.
3. Bursts last about 2.4 seconds. Recenter horizontally after playback to rearm. Power the aircraft off during gesture testing.

## Unexpected colors

Check that only one RGB effect is enabled across model and global special functions. For incorrect placement or direction, disable the effect, recalibrate with v15map and save. If even the white positioning LED shows unwanted colors or shifted positions, investigate firmware, hardware and competing LED writers.

EdgeTX [fix #7620](https://github.com/EdgeTX/edgetx/pull/7620) addresses DMA/data-line behavior and was backported to 2.12.3. Vendor self-builds may differ. Lua cannot guarantee a fix for firmware transport faults. Use firmware specifically supporting the radio model.

106 mocked checks cover simplified menus and return navigation, three display sizes, multiple font heights, missing string metatables, calibration, key permissions, idle sleep/wake across all presets, the About page, and writing only changed LED colors. Mock tests are not hardware certification.
