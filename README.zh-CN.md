# EdgeTX RGB Effects

[English](README.md)

面向多款 EdgeTX 遥控器的 RGB 灯效、摇杆联动与灯位校准工具。

## 遥控器适配包

| 型号 | 内容 | 入口 |
|---|---|---|
| HelloRadio V15 | 32 套灯效、六键联动、校准工具 | [HelloRadio-V15](HelloRadio-V15/README.zh-CN.md) |

按型号独立放置安装包；以后新增型号时添加同级目录。当前仅适配上表型号。每个包里的 SCRIPTS 可直接分享、合并到 SD 卡根目录，具体操作见型号说明。

## 项目结构

~~~text
edgetx-rgb-effects/
├─ HelloRadio-V15/
│  ├─ SCRIPTS/
│  ├─ docs/{en,zh-CN}/
│  └─ previews/{en,zh-CN}/
├─ tests/
└─ tools/previews/
~~~

[中文动图总览](HelloRadio-V15/previews/zh-CN/overview.gif) · [English overview](HelloRadio-V15/previews/en/overview.gif)

## 开发与验证

~~~text
npm exec --yes --package=fengari-node-cli@0.1.0 -- fengari tests/helloradio-v15.lua .
~~~

92 项本地模拟检查，含三种屏幕布局、校准、按键权限和组合动作。模拟结果不等于实机认证。动图由实际 Lua 输出生成；中英文各有一张总览和 32 张独立预览。生成方法见 [tools/previews](tools/previews/README.zh-CN.md)。

## 许可

尚未指定开源许可证，具体授权条款待维护者选择。
