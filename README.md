# EdgeTX RGB Effects

[简体中文](README.zh-CN.md)

RGB animations, stick-driven effects and LED calibration tools for EdgeTX radios.

## Radio packages

| Radio | Package | Guide |
|---|---|---|
| HelloRadio V15 | 32 presets, six-key lighting and calibration | [HelloRadio-V15](HelloRadio-V15/README.md) |

Each supported model has a standalone directory; future adaptations add sibling directories. Only the listed model is supported today. Share a model's SCRIPTS folder and merge it into the SD root. Read the model guide before installation.

## Layout

~~~text
edgetx-rgb-effects/
├─ HelloRadio-V15/
│  ├─ SCRIPTS/
│  ├─ docs/{en,zh-CN}/
│  └─ previews/{en,zh-CN}/
├─ tests/
└─ tools/previews/
~~~

[English animated overview](HelloRadio-V15/previews/en/overview.gif) · [中文动图总览](HelloRadio-V15/previews/zh-CN/overview.gif)

## Development and verification

~~~text
npm exec --yes --package=fengari-node-cli@0.1.0 -- fengari tests/helloradio-v15.lua .
~~~

106 mocked checks cover three screen layouts, multiple font heights, calibration, key permissions, stick combos, idle sleep/wake and incremental LED updates. They are not hardware certification. GIFs use real Lua output: one overview and 32 individual previews per language. See [preview generation](tools/previews/README.md).

## Licensing

No open-source license has been selected yet; the maintainer will choose distribution terms.
