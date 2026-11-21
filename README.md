# 宇宙银河机甲 · UrhoX 版 v1.4.7

UrhoX / TapTap 制造 版本（v1.4.7），对应网页版《宇宙银河机甲_测试版_23.html》。内容原样取自 `GalaxyMecha_UrhoX_Release_v1_4_7.zip`，只把内层 `UrhoX_Release/` 摊平到仓库根目录，未修改任何代码或资源。

## 版本与结构

- 版本号以 `VERSION` 为准：**1.4.7**
- 文件 198 个，合计约 3.1 MB（本包不含 `store/` 里的宣传片与截图）

```
.project/                 UrhoX 工程配置
VERSION                   1.4.7
assets/Sounds/            音效与 BGM（.ogg）
docs/                     16 篇文档（含 更新说明 v1.3.6 → v1.4.7 各版）
scripts/
  main.lua                引擎入口
  cosmic/                 界面与流程脚本
  game/                   体素构建（VoxelBuilder.lua）
  jsrt/                   运行时（本版只改 Renderer.lua）
  voxeldata/              体素数据与模型
tools/xpile_lite/         网页版 -> Lua 转换器
网页版19源码_供转换器/      19 版网页版 JS 源码
```

## v1.4.7 改动（摘自 `docs/更新说明_v1.4.7.md`）

只改 `scripts/jsrt/Renderer.lua` 与版本号，战斗逻辑、界面与 v1.4.6 完全相同。

**问题（v1.4.6 引入）**：v1.4.6 给激光、弹道、射线也加了光晕，而光晕是把同一个模型整体放大 2.2 倍再斜转 45 度。这些模型细长，放大后比本体长一倍多、斜转后与本体交叉，于是：

- 玩家射线枪的子弹变成青色“十”字 / 飞机形；
- 狙击光束（一串细长段）变成一条很宽的粉色斜纹带；
- 经验宝石带上光晕，变成一圈圈六边形。

**修复**：

- 光晕只保留给方块状小特效：白芯（`fx_white`）、火花（`fx_spark`）；激光、弹道、射线、经验宝石不再加光晕
- 光晕放大 2.2 → **1.8** 倍，亮度 0.2 → **0.18**，每帧上限 110 → **90**
- v1.4.6 的“叠加混合”本体保留：激光、弹道、射线仍是发光叠加效果，只是去掉了会变形的外圈

测试：渲染后端无头跑第 3 章，光晕只出现在白芯 / 火花上，叠加本体正常，无报错。

## 怎么运行

1. 以仓库根目录作为 UrhoX 项目，入口 `scripts/main.lua`；
2. 音频、模型路径相对根目录，请保留原目录结构；
3. 上架流程见 `docs/TapTap制造接入指南.md` 与 `docs/提审清单.md`。

## 使用前请注意

- 整体仍未在真实 UrhoX / TapTap 制造真机验证，首次运行请按 `docs/UrhoX移植说明.md` 末尾的未验证清单核对。
- 特效观感调参仍可参考 v1.4.6 的做法：`Renderer.lua` 里 `addProto` 的 `halo`、`HALO_K`，想回旧效果清空 `ADD_IDS`。
- `docs/用户协议模板.md`、`docs/隐私政策模板.md` 为模板，上线前需按运营主体与法务意见修改。
- 本包不含网页版 HTML（对应测试版 23）。

## 相关仓库

- 上一版（v1.4.6 特效柔和化）：`https://github.com/mmb9w48ff7/GalaxyMecha-UrhoX-Release-v1.4.6`
- 更早：v1.4.4、v1.4.3、v1.4.2、v1.4.1、v1.3.5（UrhoX Release 系列）
- 源码工程（作者专用）：`https://github.com/mmb9w48ff7/GalaxyMecha-Source-v1.3.5`
- 网页版合集：`https://github.com/mmb9w48ff7/GalaxyMecha-Web-2`
