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
4. Confirm its clockwise direction, enter the preview and press 保存设置 (save).

Settings are saved to /SCRIPTS/RGBLED/v15lib/layout.cfg, without changing model/mixer/output settings. Re-enable the special function to reload. Each ring has 16 positions at about 22.5° per step. Inner-bottom starts are approximately left 5:15 and right 6:45; calibration determines actual placement.

Preview controls use 重新校准 (recalibrate) and 保存设置 (save settings). 返回预览 returns from settings, style, diagnostics or About to the preview page. Diagnostic buttons use full Chinese captions centered horizontally and vertically within each button.

关于 (About) lists the author Xu, the GitHub profile [github.com/939008033](https://github.com/939008033), and the email address 939008033@qq.com.

## Which settings apply

- Shared: LED mapping, physical sides, numbering direction, brightness and key enable.
- A automatic presets do not read throttle. Each preset defines its colors and direction.
- B presets use source, reversal and smoothing. B01-user additionally uses your selected palette, path and start angle; B02–B14 fix these options. B15 adds a moving afterburner hotspot.
- C presets map physical sticks according to Mode 1–4 and use brightness, smoothing and key settings. They ignore throttle CHn/reversal and B01 palette/path choices.

油门摇杆 means physical throttle stick; CHn means the selected output. Channel monitor -100% / 0% / +100% maps to progress 0% / 50% / 100%. Default smoothing is about 80 ms; rendering is limited to 20 Hz. Scripts display LEDs only.

## Six key LEDs

Throttle fills **keys 3/4 → 2/5 → 1/6 → rings**, counting physical keys left to right. Keys consume 3/19 of total progress, so 50% total does not mean exactly half of each ring is lit.

For assigned function switches, enable 允许 LUA 脚本控制 (allow Lua control) in both OFF and ON columns under 自定义按键 (custom/function switches). Unassigned/disabled keys can remain disabled. In 配色 (style), select 六键 → 优先点亮 (keys first). 测试 → 测试按键灯 (test key LEDs) shows API acceptance. 6/6 confirms accepted requests, not that both permission gates are enabled.

Disabling keys or exiting the tool releases only its owned key-color overrides. Key functions are preserved.

## Dual-stick controls and combos

C01 follows physical heading/deflection. C02 uses the left stick for color/brightness and the right for speed/direction/width. C03 controls each ring independently. For C04:

1. Center both horizontal axes for about half a second; throttle may remain at minimum.
2. Hold each pose for about half a second, connecting both within 2.5 seconds: **out→in** triggers a pink-white nova; **in→out** an ice-blue wave; **both right→both left** a rainbow swirl.
3. Bursts last about 2.4 seconds. Recenter horizontally after playback to rearm. Power the aircraft off during gesture testing.

## Unexpected colors

Disable all RGB special functions and use static diagnostics in 测试 (Test): 半圈青色 / 全部青色 / 全部红色 / 全部蓝色 / 关闭灯环 (half cyan, full cyan, red, blue, off). If static output still shows unwanted colors or shifted LED positions, investigate firmware, hardware and competing LED writers.

EdgeTX [fix #7620](https://github.com/EdgeTX/edgetx/pull/7620) addresses DMA/data-line behavior and was backported to 2.12.3. Vendor self-builds may differ. Lua cannot guarantee a fix for firmware transport faults. Use firmware specifically supporting the radio model.

95 mocked checks cover three display sizes, centered captions, missing string metatables, calibration, key permissions, throttle/stick animations, the About page, and writing only changed LED colors. Mock tests are not hardware certification.
