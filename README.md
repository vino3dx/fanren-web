# 翻书

一个基于 Godot 4 的 3D 书本阅读器。封面点开后进入书本，书页像真书一样带着书脊弯曲和页角掀起翻开，
支持逐页翻动、长按连翻、目录按钮直达指定章节，页面内容全部来自外置图片，换一套图就是一本新书。

- 引擎：Godot 4.7（GDScript），渲染后端 Compatibility（OpenGL 3.3）
- 设计分辨率 3840×2160，默认窗口 1600×900（`keep_width` 适配，16:9 以外补背景色）
- 内置两套内容：`main_shenpan.tscn`（审判案例，81 页）与 `main_fuyi.tscn`（执法复议案例，89 页）

## 运行

用 Godot 4.7 打开本目录下的 `project.godot` 直接运行，或命令行：

```bash
# 运行主场景（main_shenpan.tscn）
Godot_v4.7.2-stable_win64.exe --path <工程目录>

# 运行另一套场景
Godot_v4.7.2-stable_win64.exe --path <工程目录> scenes/main_fuyi.tscn
```

切换默认启动场景：改 `project.godot` 里的 `application/run/main_scene`。

## 操作方式

| 操作 | 效果 |
| --- | --- |
| 封面上点击任意位置 | 进入书本 |
| 点击/按住右半页 | 下一页（按住可连续翻） |
| 点击/按住左半页 | 上一页 |
| 点目录按钮 | 直接翻到对应页（多页连续翻动） |
| 「返回目录」 | 回到第 1 页 |
| 「返回封面」 | 回到封面 |
| 无操作 600 秒 | 自动回到封面 |

点击翻页依赖场景里 `SimpleTouchPad` 下的 `Page Left` / `Page Right` 两个碰撞盒，
指针落在 UI 按钮上时不会触发 3D 翻页。

## 目录结构

```
project.godot          工程配置（主场景、分辨率、渲染后端）
export_presets.cfg     Windows 导出预设
scenes/
  book.tscn            书本本体：骨骼动画书 + 5 个静态替身 + 5 张翻动页
  page.tscn            单张翻动页
  main_shenpan.tscn    审判案例
  main_fuyi.tscn       执法复议案例
scripts/
  endless_book.gd      书本状态机与翻页调度（页码、状态切换、页材质）
  page.gd              单张翻动页的翻动动画
  page_cache.gd        页面材质缓存（LRU + 邻页预载）
  fanshu.gd            审判案例的主逻辑（页数、UI 显隐、点击翻页）
  fanshu2.gd           执法复议案例的主逻辑
  feng_mian_manager.gd 封面 / 正文切换、自动回封面
  an_li_manager.gd     目录按钮 → 指定页
  image_loader_manager.gd 外部图片加载（默认只提供接口，不预载）
  simple_touch_pad.gd  左右页点击区域
  background_video.gd  背景视频（贴在相机前方的全屏四边形上）
assets/
  models/              书本与替身模型（FBX）
  materials/           书页、封面、单页的材质
  ui/                  封面图、翻页按钮、返回按钮
  pages/               正文页图片（执法复议案例）
  pages_shenpan/       正文页图片（审判案例）
  toc/fuyi/            印刷目录页图片（4 张）
  toc/shenpan/         印刷目录页图片（4 张）
  video/               背景视频（mp4 源文件 + 实际播放的 ogv）
  fonts/               备用中文字体
```

`.godot/` 是引擎的导入缓存，可随时删除，重新打开工程会自动重建（当前约 700 MB）。

## 换成自己的内容

### 1. 正文页图片（最常改的一项）

把图片按 **纯数字命名** 放进目标目录（默认 `assets/pages_shenpan/` 或 `assets/pages/`）：
`1.png`、`2.png`、`3.png`……

页数不用手工填，程序启动时扫描目录取最大序号。页序规则：

```
书页 1 ~ 4     = 印刷目录（来自 assets/toc/<套>/1..4.png）
书页 5 起      = 正文，书页 p 显示图片 p-3
图片 1         = 章节扉页，不入书（所以正文从图片 2 开始）
```

如果新内容的页序规则不同（比如没有印刷目录、或图片 1 就是正文第一页），
改 `PageCache` 的 `image_offset`（构造参数第 3 位，`Fanshu._ready()` 里传的是 3）
以及 `TOC_PAGE_COUNT` 即可。

### 2. 印刷目录页

替换 `assets/toc/shenpan/1..4.png` 与 `assets/toc/fuyi/1..4.png`。这 4 张是静态材质，
启动时就加载并常驻，不参与按需加载。

### 3. 目录按钮

每个分组的按钮是 `UI_Book/Root/Panel/<分组名>` 下的 `Button`，分组节点上挂着 `AnLiManager`：

- `buttons`：按钮的 NodePath 列表
- `pages`：与 `buttons` 一一对应的目标**书页号**

改完按钮数量后，把这两个数组同步改一下即可（长度要一致，多出来的会被忽略）。

### 4. 封面与按钮图

替换 `assets/ui/` 下的 PNG。封面是 `Cover` 层里的 `Image`（TextureRect），
按钮是 `UI_Top` / `UI_Book` 里的 TextureButton，直接换贴图资源即可。

### 5. 书本外观

- 书页/封面材质：`assets/materials/*.tres`
- 书本模型：`assets/models/BookAnimated.fbx`（带骨骼动画），
  以及 5 个静态替身 `BookStandin*.fbx`（闭合前、开前、开中、开后、闭合后）。
  静止时显示替身、翻动时切到带动画的书，这是保证静态画面也能扛住高清渲染的做法。

### 6. 背景视频

Godot 只支持 **Ogg Theora**，需要先转码。建议 **1280×720、25fps**，模糊的粒子背景足够清晰，
再高只会白白增加解码开销：

```bash
ffmpeg -y -i "assets/video/粒子背景.mp4" \
	   -vf "scale=1280:720:flags=lanczos" \
	   -c:v libtheora -q:v 8 -pix_fmt yuv420p -an \
       "assets/video/粒子背景.ogv"
```

播放分辨率在 `VideoBackground` 节点的 `resolution` 属性（默认 1280×720），
换视频时让它和视频实际分辨率一致。背景是拉伸铺满整个窗口的，窗口比例变化会自动重新适配。
不想要背景视频，把 `VideoBackground` 节点禁用即可。

## 关键参数速查

| 想改什么 | 改哪里 |
| --- | --- |
| 启动场景 | `project.godot` → `application/run/main_scene` |
| 分辨率 / 窗口大小 | `project.godot` → `display/window/size/*` |
| 页面图片目录 | 场景里 `FanShu` 节点 → `page_dir` |
| 目录页图片目录 | 场景里 `FanShu` 节点 → `toc_dir` |
| 印刷目录页数 | `fanshu.gd` / `fanshu2.gd` → `TOC_PAGE_COUNT` |
| 图片序号偏移 | `fanshu.gd` / `fanshu2.gd` → `PageCache.new(..., 3, ...)` 的第 3 个参数 |
| 翻页时长 | `turn_to_next_page()` 里的 `0.5`（秒/页） |
| 页面缓存张数 / 预载半径 | `fanshu.gd` → `CACHE_CAPACITY`、`PRELOAD_BACK`、`PRELOAD_FORWARD` |
| 自动回封面时间 | 场景里 `FengMianManager` 节点 → `max_times`（秒） |
| 背景视频 | 场景里 `VideoBackground` 节点 → `video_path`、`resolution` |

## 翻页动画是怎么做的

书和单页各有一条骨骼动画，里面按状态把动作首尾相连排在一起。运行时不用完整的
`AnimationPlayer.play()`，而是「定位到某一段的起点 + 每帧 `seek()` 到段内比例位置」，
这样一次导出就能当多段动画用，也能随时改变播放速度。

书本的 10 段（59 帧 / 段 @24fps）：

| 段落 | 起始帧 | 起始秒 |
| --- | --- | --- |
| ClosedFrontToOpenMiddle | 1 | 0.000 |
| OpenMiddleToClosedBack | 63 | 2.583 |
| ClosedFrontToOpenFront | 125 | 5.167 |
| OpenFrontToOpenMiddle | 187 | 7.750 |
| OpenMiddleToOpenBack | 249 | 10.333 |
| OpenBackToClosedBack | 311 | 12.917 |
| ClosedFrontToClosedBack | 373 | 15.500 |
| OpenFrontToClosedBack | 435 | 18.083 |
| OpenFrontToOpenBack | 497 | 20.667 |
| ClosedFrontToOpenBack | 559 | 23.250 |

单页 `Page.fbx`：`TurnForward` 从 0.000s 起、`TurnBackward` 从 1.083s 起，每段 0.958s。
反向播放（例如「往回翻」）就是把段内时间取反，不用另做倒放资源。

多页连翻时最多只复用 5 张翻动页轮转（`book.tscn` 里的 `Page`~`Page5`，
数量由 `EndlessBook.max_pages_turning_count` 控制），所以翻 30 页也不会卡。

## 性能要点

这套程序在 GTX 级显卡上连续翻页可以稳定在 700 fps 以上（脚本 + 渲染总耗时约 1.5 ms/帧），
关键靠三条约束，改内容时建议保持：

1. **背景视频别用高分辨率。** Theora 是 CPU 软解，4K 单帧要 50~140 ms，1280×720 只要 1~2 ms，
   而且是逐帧解码的，分辨率直接决定整机帧率上限。
2. **页面贴图用 VRAM 压缩（BC7）。** `*.png.import` 里保持
   `compress/mode=2` + `compress/high_quality=true`。用「无损」的话，`.ctex` 内部仍是 PNG，
   每张首次使用要在主线程解码 17~31 ms、渲染线程再卡 40~70 ms，每翻一页掉好几帧。
   BC7 与源图差异只有 PSNR 47.8 dB（肉眼看不出），但换来 4 倍显存和 8 倍加载速度。
   改过导入设置后需要重新导入：`godot --headless --path . --import`（172 张约 4~5 分钟）。
3. **页面按需加载，不要启动时全量读。** 全书 86 张 1920×2160 的图一次性读进来要 1.4 GB 显存、
   启动卡 6 秒。`PageCache` 只保留最近用过的 16 张并预载前后若干页，显存稳定在 200 MB 左右。

导出时 `texture_format/s3tc_bptc` 必须保持开启，否则 BC7 贴图会失效。

## 打包

`export_presets.cfg` 里已有一份 Windows 预设（导出到 `build/翻书.exe`），
在 Godot 的「项目 → 导出」里直接导出即可。首次导出需要安装对应版本的导出模板。

## 常见问题

**页面是空白/纯色**
图片命名不是纯数字，或序号断档；也可能是新加图片后没有重新导入。确认文件名为 `1.png`…`N.png`，
并在编辑器里让它完成导入。

**翻页方向或页序对不上**
检查 `image_offset`（默认 3）与印刷目录页数 `TOC_PAGE_COUNT`（默认 4）是否和实际内容一致。

**背景视频不播放**
工程里必须放 `.ogv`（Ogg Theora），mp4/webm 都不支持。转码命令见上文。

**翻页卡顿**
先看背景视频分辨率，再看页面贴图的导入格式（见「性能要点」两条）。

**中文字体显示异常**
项目使用默认字体；`assets/fonts/msyh.ttc` 是备用字体，需要时在主题里指定。
