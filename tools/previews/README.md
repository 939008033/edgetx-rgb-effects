# Generate LED previews

[简体中文](README.zh-CN.md)

Requires Windows PowerShell 7.6+ (.NET 10 drawing assemblies), Node.js, Fengari Node CLI 0.1.0 and FFmpeg. The tool executes all unchanged radio entry scripts with mocked LEDs, captures 240 frames, then renders 32 standalone GIFs and one overview per language. No radio is accessed.

~~~powershell
pwsh ./tools/previews/render.ps1 -Language all -Fengari fengari -Ffmpeg ffmpeg -Node node
~~~

Use executable paths if these commands are not on PATH. Add -SamplesOnly to render representative PNGs without encoding GIFs. Outputs go to HelloRadio-V15/previews/{en,zh-CN}; scratch data goes to ignored work/. Captions are in catalog.json; shared labels are in Renderer.cs. preview-config.lua is a simulated host configuration, not a file to install on a radio.
