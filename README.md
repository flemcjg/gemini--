# GPT-喵（GPT-Miao）· Antigravity 紫发猫娘额度挂件插件

让一只紫发异瞳的小猫娘，陪你在 **Antigravity** 里写代码、看额度、听音乐律动！

<img src="assets/catgirl-bust.png" alt="GPT-喵 紫发猫娘挂件" width="220" />

## 核心特性（双形态）

### 1. Antigravity 原生插件（MCP App）
- 零外部依赖（基于 Python 3 标准库 stdio MCP Server），安装后 Antigravity 自动发现。
- 支持在右侧边栏 `+` 菜单及左侧栏打开 **GPT-喵** 交互面板，也可直接对话唤出。
- 一键启停 Windows 桌面悬浮挂件、实时同步缩放/模式/语录/预算设置。

### 2. Windows 透明桌面悬浮挂件（WPF）
- **原图同款视觉**：紫发猫娘 + 紫色椭圆思考气泡 + 双尾圆点，默认展示 **「我是啥喵？」**，支持实时排版自适应字号（长短语录均饱满清晰）。
- **额度查看与自动刷新**：
  - 支持接入 Antigravity CLI（`agy`）官方 `statusLine` 钩子实时读取官方 `quota`；
  - 未运行 `agy` 时自动回退至本机 `USER_INPUT` 轮次统计 + 锚点校准，后台自动刷新无需手动点击。
- **丝滑交互体验**：
  - 点猫娘：按压回弹 + 合成轻提示音 + 查看 5 小时 / 每周额度；
  - 点气泡：额度 → 随机猫娘语录（含 3% 变色彩蛋）→ 收起；
  - 高分屏 DPI 精确跟手拖动 + **按可见轮廓贴齐屏幕四边碰撞限制** + 松手自动左右翻转（文字保持正向）；
  - **自定义大小（60%–250%）**：右键滑块弹窗实时预览、`Ctrl + 滚轮` 快捷缩放、侧边栏滑块同步。
- **音乐律动（自动检测电脑音频）**：基于 Windows Core Audio (`IAudioMeterInformation`)，电脑播放音乐/视频时猫娘随节奏丝滑 Q 弹律动，静音自动静止。
- **可选自动语录 & 回答结束提醒**：支持关闭 / 5 分钟 / 10 分钟 / 30 分钟自动弹出猫娘语录，以及 Antigravity 真正完成最终回复时的轻提示音提醒。

## 快速安装（Windows）

需要 **Python 3.10+** 与 **Antigravity**。

1. 下载本仓库并解压；
2. 双击根目录的 **`安装GPT喵.cmd`**，会自动将插件安装至 `%USERPROFILE%\.gemini\config\plugins\gpt-miao\` 并启动桌面透明挂件；
3. 在 Antigravity 右侧边栏 `+` 菜单中即可打开 **「GPT-喵」** 面板。

### 可选：接入 `agy` CLI 官方实时额度
在 `%USERPROFILE%\.gemini\antigravity-cli\settings.json` 中添加：

```json
{
  "statusLine": {
    "type": "command",
    "command": "python \"%USERPROFILE%\\.gemini\\config\\plugins\\gpt-miao\\server\\agy_statusline_bridge.py\"",
    "enabled": true,
    "stack_with_default": true
  }
}
```

## 致谢与许可

- 交互与气泡视觉参考开源项目 [T7moris/GPT-Niang](https://github.com/T7moris/GPT-Niang)，感谢其优秀设计。
- 代码采用 [MIT License](LICENSE) 开源；角色图片素材归原权利人所有，请勿用于未经授权的商业用途。
