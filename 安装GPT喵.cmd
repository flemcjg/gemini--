@echo off
chcp 65001 >nul
setlocal
set "TARGET=%USERPROFILE%\.gemini\config\plugins\gpt-miao"
echo 正在安装 GPT-喵 到 Antigravity 插件目录：%TARGET%
if not exist "%TARGET%" mkdir "%TARGET%"
xcopy "%~dp0plugin.json" "%TARGET%\" /Y /Q >nul
xcopy "%~dp0mcp_config.json" "%TARGET%\" /Y /Q >nul
xcopy "%~dp0README.md" "%TARGET%\" /Y /Q >nul
xcopy "%~dp0启动悬浮挂件.cmd" "%TARGET%\" /Y /Q >nul
xcopy "%~dp0关闭悬浮挂件.cmd" "%TARGET%\" /Y /Q >nul
xcopy "%~dp0assets" "%TARGET%\assets\" /E /I /Y /Q >nul
xcopy "%~dp0server" "%TARGET%\server\" /E /I /Y /Q >nul
xcopy "%~dp0widget" "%TARGET%\widget\" /E /I /Y /Q >nul
xcopy "%~dp0skills" "%TARGET%\skills\" /E /I /Y /Q >nul
echo.
echo 安装完成！Antigravity 会自动发现并加载 GPT-喵 插件。
echo 正在启动 Windows 透明桌面悬浮挂件...
wscript.exe "%TARGET%\widget\launch.vbs"
echo 已启动喵！按任意键关闭此窗口。
pause >nul
