---
name: gpt-miao
description: 打开并管理「GPT-喵」Antigravity 紫发猫娘额度挂件（支持原生侧边栏 MCP App 面板与 Windows 透明悬浮挂件，查看本地对话用量统计、调整自定义额度预算、编辑猫娘语录以及启停悬浮挂件）。
---

# GPT-喵 挂件技能

当用户要求打开 GPT-喵 面板、查看本地用量预算、编辑猫娘语录，或启动/关闭 Windows 透明悬浮挂件时，调用 `gpt-miao_gpt_miao` MCP 服务器提供的工具：

- `open_gpt_miao`：打开 GPT-喵 原生交互面板（支持侧边栏 `aux_pane` 和左侧全局入口，实时展示紫发猫娘、思考气泡、本地对话用量统计、自定义预算与悬浮窗控制）。
- `toggle_desktop_widget`：启动或关闭 Windows 透明悬浮挂件（支持跟随 Antigravity 窗口或桌面自由拖动）。
- `update_gpt_miao_config`：更新 5 小时 / 每周自定义预算上限、添加猫娘语录或调整挂件默认模式。
