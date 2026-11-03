# 生成灯效预览

[English](README.md)

需要 Windows PowerShell 7.6+（.NET 10 绘图库）、Node.js、Fengari Node CLI 0.1.0 和 FFmpeg。工具在电脑模拟硬件，执行现有灯效入口，采集 240 帧；每种语言输出 32 张独立 GIF 和一张总览，不访问遥控器。

~~~powershell
pwsh ./tools/previews/render.ps1 -Language all -Fengari fengari -Ffmpeg ffmpeg -Node node
~~~

命令不在 PATH 时传入完整可执行文件路径。加 -SamplesOnly 可只生成检查用 PNG。输出目录为 HelloRadio-V15/previews/{en,zh-CN}，中间文件位于已忽略的 work/。文字在 catalog.json，公共界面文字在 Renderer.cs。preview-config.lua 仅用于电脑模拟，不能当作遥控器校准文件安装。
