# Shadow Coach

**把真实英语视频变成逐句复述训练，并告诉你具体哪个词、哪个音、哪个节奏出了问题。**

[English](README.md) · [架构](docs/architecture.md) · [参与贡献](CONTRIBUTING.md) · [隐私说明](docs/privacy.md)

Shadow Coach 是一个本地优先的 macOS 英语跟读与复述训练工具。用户先隐藏文本听原声，再凭记忆复述、录音和分析。macOS 是主程序，iPhone 是可导入 Mac 资料包的随身练习端。

![Shadow Coach 练习流程](docs/shadow-coach-demo.gif)

## 核心流程

主页面的 **Next Coach** 每次只显示当前最值得做的一步，并自动把一句话推进完整学习闭环：

1. 结合语境理解真实输入。
2. 主动注意一个可复用语块，以及重音、弱读和连接方式。
3. Shadowing 模仿原声节奏和表达。
4. 隐藏答案，无提示大声提取。
5. 用本地 FSRS-6 安排间隔复习。
6. 保留语块，但换人物、时间和场景重新表达。
7. 围绕相关经历或观点自由表达 30–60 秒。
8. 在真实对话、会议或语音消息中使用一次。
9. 分析一次精确复述，根据反馈完成一遍纠错重录。

变形和自由表达录音会保存进历史，但不会被错误地拿去和原句逐字打分。各步骤完成条件见 [学习路径说明](docs/learning-path.md)。

## 主要功能

- 文件夹式本地 Library、搜索、标签、收藏、练习状态和历史记录。
- 导入 `.txt`、`.csv`、`.xlsx`、`.srt`、`.vtt`。
- 导入 `.mp4`、`.mov`、`.m4a`、`.mp3` 和配套字幕。
- 导入前预览 YouTube、TED、VOA 等链接的标题、时长和字幕质量。
- 有真实音频时播放原声，没有时自动使用系统 TTS。
- 录音、回放、多次尝试、删除和本地缓存分析结果。
- WhisperX 识别用户实际说了什么，并提供词级时间轴。
- 原句与用户 transcript 对比，标记漏词、多词和错词。
- Praat/Parselmouth 对比语速、停顿、pitch、intensity 和重读证据。
- 可选 Azure 词级/音素级发音评估。
- 可选本地 Codex CLI 或 Gemini，把分析证据解释成练习建议。
- 本地 FSRS-6 自适应复习；默认英文语境提示，中文只作为卡住时的辅助，并可设置记忆目标和每日上限。
- 把部分 Mac 文件夹导出为 `.shadowcoachbundle`，导入 iPhone 练习。

复习算法和四个评分按钮的含义见 [docs/review.md](docs/review.md)。

## 普通用户安装

首个公开版本发布后，从 [GitHub Releases](../../releases) 下载已经签名和公证的 DMG，把 **Shadow Coach** 拖入 Applications 即可。

基础的听音、录音、回放、Library、TTS 和历史记录不需要 API Key。高级导入或分析缺少可选工具时，软件会提示具体安装方法。

## 开发者启动

```bash
git clone https://github.com/Marvelousp4/ShadowCoach.git
cd ShadowCoach
./scripts/bootstrap.sh
swift run ShadowCoach
```

构建 Mac App、检查环境和运行测试：

```bash
./scripts/build-app.sh
./scripts/doctor.sh
swift test
```

较慢的 `./scripts/clean-room-smoke.sh` 从零安装检查只在正式 `v*` 版本发布时运行。

iPhone 工程：

```bash
open ios/ShadowCoachMobile.xcodeproj
```

详细安装请看 [docs/setup.md](docs/setup.md)。个人 Library、下载媒体、录音、分析结果、模型和 API 配置都不会进入源码仓库。

各项本地工具如何分发请看 [docs/dependencies.md](docs/dependencies.md)。

从各工具的官方包来源安装可选本地能力：

```bash
./scripts/install-local-tools.sh --media
./scripts/install-local-tools.sh --analysis
# 或一次安装两组：
./scripts/install-local-tools.sh --all
```

## 参与贡献

请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)，优先从带有 `good first issue` 的任务开始。提交 bug 时可以附上脱敏日志，但不要上传私人录音、受版权保护的媒体或 API Key。

## 开源协议

本项目使用 [AGPL-3.0](LICENSE)。外部工具与在线服务仍遵守各自的许可和服务条款，详情见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
