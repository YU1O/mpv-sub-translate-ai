# mpv-sub-translate-ai

mpv 播放时的外挂字幕实时翻译脚本。基于 [dyphire/mpv-sub-fastwhisper](https://github.com/dyphire/mpv-sub-fastwhisper) 改造，原版 MIT；已剥离 faster-whisper 语音识别部分，只保留「外挂 srt → OpenAI 兼容 API → 双语 ASS 字幕」。

## 安装

- `sub-translate-AI.lua` 放到 mpv 配置目录下的 `scripts/`
- `sub_translate_AI.conf` 放到同级的 `script-opts/`，文件名必须与脚本名对应（`sub_translate_AI`）

## 用法

加载外部 srt 字幕后按 `ALT+f`，会生成 `xxx.translate.srt` 与双语 `xxx.Chinese.ass`。也可以在 mpv 里执行 `script-message-to sub_translate_AI translate`。

## 配置

`sub_translate_AI.conf` 里每项都有注释。默认指向本机 LM Studio（`http://localhost:1234/v1/chat/completions`），`api_key=lmstudio` 只是占位符。换成在线服务时修改 `api_url` 与 `api_key`；**不要把真实 API key 提交到公开仓库**。

## 许可

MIT，原作者 dyphire，详见 [LICENSE](LICENSE)。
