# 翻书

一个基于 Godot 4 的 3D 书本阅读器。封面点开后进入书本，书页像真书一样带着书脊弯曲和页角掀起翻开，
支持逐页翻动、长按连翻、目录按钮直达指定章节，页面内容全部来自外置图片，换一套图就是一本新书。

- 引擎：Godot 4.6 及以上（GDScript），渲染后端 Compatibility（OpenGL 3.3）
- 设计分辨率 3840×2160，默认窗口 1920×1080（`keep_width` 适配，16:9 以外补背景色）
- 内容：《凡人修仙传·仙侠手账》，`assets/pages/` 下 45 张 jpg，主场景 `scenes/main.tscn`

## 运行

用 Godot 打开本目录下的 `project.godot` 直接运行，或命令行：

```bash
Godot_v4.6-stable_win64.exe --path <工程目录>
```

启动场景由 `project.godot` 里的 `application/run/main_scene` 决定（当前 `res://scenes/main.tscn`）。

## 操作方式

| 操作 | 效果 |
| --- | --- |
| 封面上点击任意位置 | 进入书本 |
| 点击/按住右半页 | 下一页（按住可连续翻） |
| 点击/按住左半页 | 上一页 |
| 点目录按钮 | 直接翻到对应页（多页连续翻动） |
| 「返回目录」 | 回到第 1 页 |
| 「返回封面」 | 回到封面 |
| 左下角音乐符号 | 静音 / 解除静音（图标一直慢速旋转） |
| 无操作 600 秒 | 自动回到封面 |

点击翻页依赖场景里 `SimpleTouchPad` 下的 `Page Left` / `Page Right` 两个碰撞盒，
指针落在 UI 按钮上时不会触发 3D 翻页。

## 目录结构

```
project.godot            工程配置（主场景、分辨率、渲染后端）
export_presets.cfg       Web 导出预设
scenes/
  main.tscn              主场景：书本 + 相机 + 背景视频 + UI + 目录覆盖层
  book.tscn              书本本体：骨骼动画书 + 5 个静态替身 + 若干翻动页
  page.tscn              单张翻动页
  music_button.tscn      左下角音乐开关（自带播放器，可整段拖到任何场景）
scripts/
  endless_book.gd        书本状态机与翻页调度（页码、状态切换、页材质）
  page.gd                单张翻动页的翻动动画
  page_cache.gd          页面材质缓存（LRU + 邻页预载）
  fanshu2.gd             主逻辑（页数扫描、UI 显隐、点击翻页、目录接管）
  feng_mian_manager.gd   封面 / 正文切换、自动回封面
  toc_page.gd            目录点击区覆盖层（页框 + 垂直框自动排布）
  image_loader_manager.gd 外部图片加载（默认只提供接口，不预载）
  simple_touch_pad.gd    左右页点击区域
  background_video.gd    背景视频（贴在相机前方的全屏四边形上）
  music_toggle.gd        音乐开关（旋转图标 + 静音切换 + 独立 BGM 总线）
assets/
  models/                书本与替身模型（FBX）
  materials/             书页、封面、单页的材质
  ui/                    封面图、翻页按钮、返回按钮、音乐图标
  pages/                 正文页图片（45 张 jpg）
  audio/                 背景音乐（不凡.mp3）
  video/                 背景视频（bg.ogv，1920×1080 / 25fps / 无音轨）
```

`.godot/` 是引擎的导入缓存，可以随时删除，重新打开工程会自动重建。

## 换成自己的内容

### 1. 正文页图片（最常改的一项）

把图片按 **纯数字命名** 放进 `assets/pages/`。支持 `png`、`jpg/jpeg`、`webp`、`bmp`、`tga`、`svg`，
同一序号有多个格式时按上面的顺序取第一个，所以换格式不用改代码，直接放图即可。

页数不用手工填，程序启动时扫描目录取最大序号。页序规则由场景里 `FanShu` 节点的两个属性决定：

```
toc_page_count = 书前插入的印刷目录页数（来自 toc_dir，可为 0）
image_offset   = 书页 = 图片序号 + image_offset
```

本工程用 `toc_page_count = 0`、`image_offset = 0`：图片自带目录页，书页 p 就是第 p 张图，
`front_pages = 4` 表示前 4 页是目录，第 5 页起是正文。

这套内容的换算关系是 **书页 = 页脚印的页码 + 4**：图片 5 是正文第 1 页（页脚印 `01`），
图片 13 是第 9 页（`09`），图片 44 是第 40 页（`40`）。目录里的 `targets` 就按这个算 ——
例如总目录里「卷一 · 页脚 01」对应书页 5。

### 2. 目录点击区（`TocPage`）

目录文字是印在页面图片里的，所以需要一层透明点击区盖在上面。这一层由 `TocPage`
（`scripts/toc_page.gd`）负责，**一个节点管一页**，不再逐个按钮写坐标。

场景里 `UI_Book/Root/Panel/PageAreaLeft` / `PageAreaRight` 是两个「页框」Control，
矩形就是该页在屏幕上的位置（设计坐标 3840×2160）。每个页框下面挂若干 `TocPage`：

| 属性 | 作用 |
| --- | --- |
| `page_number` | 这组条目印在第几页；翻到那一屏才显示 |
| `block_top` / `block_bottom` | 条目区在页面里的上下边界（0~1 相对比例） |
| `targets` | 每行跳转到第几页，**行数 = 数组长度** |
| `titles` | 每行文字，配合 `show_titles` 使用 |
| `show_titles` | 页面图上已印好文字就关掉，只做透明点击区（本工程就是这样） |
| `inset_left` / `inset_right` | 点击区左右内缩，避免顶到页边 |
| `title_theme` / `title_font_size` / `highlight_color` | 换主题、字号、悬停高亮色 |

行是用 `VBoxContainer` + `EXPAND_FILL` 均分条目区排出来的，所以只需要「上下边界 + 行数」两个量，
不需要逐个写矩形。印刷目录的行距是均匀的，行边界会自然落在印刷分隔线上。

当前四页的数值（从实际画面上量的，行心误差 < 1px）：

| 节点 | 所在页 | 行数 | block_top | block_bottom |
| --- | --- | --- | --- | --- |
| `TocTotal` | 1（左页） | 6 | 0.3921 | 0.7784 |
| `TocVol1` | 2（右页） | 8 | 0.3570 | 0.7889 |
| `TocVol23` | 3（左页） | 9 | 0.3443 | 0.8017 |
| `TocVol46` | 4（右页） | 9 | 0.3435 | 0.8032 |

换一套目录页时：

1. 改 `page_number`（印在第几页）和 `targets`（点每行跳哪页）；
2. 行数变了，条目区边界一般还能用，因为行是均分的；
3. 如果新目录页的行距明显不同，量出第一行中心 `f`、行距 `s`、行数 `n`，换算：
   `block_top = f - s/2`，`block_bottom = f + (n-1)*s + s/2`（都是相对页面高度的比例）。

`fanshu2.gd` 启动时会自动扫描 `Panel` 下所有 `TocPage`，**增删目录组不用改代码**。

### 3. 封面与按钮图

替换 `assets/ui/` 下的 PNG。封面是 `Cover` 层里的 `Image`（TextureRect），
按钮是 `UI_Top` / `UI_Book` 里的 TextureButton，直接换贴图资源即可。

### 4. 书本外观

- 书页/封面材质：`assets/materials/*.tres`
- 书本模型：`assets/models/BookAnimated.fbx`（带骨骼动画），
  以及 5 个静态替身 `BookStandin*.fbx`（闭合前、开前、开中、开后、闭合后）。
  静止时显示替身、翻动时切到带动画的书，这是保证静态画面也能扛住高清渲染的做法。

### 5. 背景视频

Godot 只支持 **Ogg Theora**，需要先转码。当前素材是 **1920×1080 / 25fps / Theora 质量模式 `-q:v 5`（约 10.8 Mbps）/ 无音轨 / 23 MB**：

```bash
ffmpeg -y -i "源视频.mp4" \
       -vf "scale=1920:1080:flags=lanczos" \
       -c:v libtheora -q:v 5 -g 64 -pix_fmt yuv420p \
       -an \
       "assets/video/bg.ogv"
```

Theora 效率很低，同一段素材用固定码率 `-b:v 1500k` 会明显发糊（PSNR 仅 27 dB，`-q:v 5` 是 34 dB）；
想更清楚就把 `-q:v` 提到 6（约 15 Mbps / 34 MB）。**不要**加音轨：背景音乐由
`scenes/music_button.tscn` 单独负责，视频音轨只会和它叠在一起。

播放分辨率在 `VideoBackground` 节点的 `resolution` 属性（脚本默认 1920×1080），
换视频时让它和视频实际分辨率一致。背景是拉伸铺满整个窗口的，窗口比例变化会自动重新适配。
不想要背景视频，把 `VideoBackground` 节点禁用即可。

### 6. 背景音乐与静音开关

背景音乐是一个可以整段复用的组件：`scenes/music_button.tscn`（脚本 `scripts/music_toggle.gd`）。
它同时包含播放器和左下角的圆形开关，拖进场景就能用，不需要另外放 `AudioStreamPlayer`。

- 音乐文件：`assets/audio/不凡.mp3`，在 `music_button.tscn` 里作为 `stream` 引用（**不要**把 mp3
  拖进场景本身，那样会把整段音频以 base64 内嵌进场景，`.tscn` 会膨胀到 2 MB 量级，保存/加载都变慢）
- 循环：mp3 的导入参数里 `loop=true`，另外脚本运行时会再确认一次，换素材也不容易漏
- 静音：走单独的 `BGM` 总线（不存在会自动创建），不影响以后加的其它音效
- 外观：图标 `assets/ui/music_on.svg` / `music_off.svg`，尺寸和位置在 `music_button.tscn` 里改
  （`Root/Spin` 和 `Root/Hit` 的 `offset_*`，默认左下角 64，按钮 150×150，按 3840×2160 设计坐标）

| 想改 | 改哪里 |
| --- | --- |
| 换音乐 | `music_button.tscn` 里 `Player` 节点的 `stream` |
| 音量 | `MusicButton` 节点 → `volume_db`（默认 -6 dB） |
| 旋转速度 | `MusicButton` 节点 → `spin_speed`（度/秒，默认 22；设 0 即不转） |
| 静音时是否继续转 | `MusicButton` 节点 → `spin_always` |
| 正常 / 静音时透明度 | `active_alpha` / `muted_alpha` |
| 按钮位置、大小 | `music_button.tscn` 里 `Root/Spin`、`Root/Hit` 的 `offset_*` 与 `pivot_offset` |

`MusicToggle` 也可以从代码控制：`set_muted(true)`、`toggle_mute()`、`is_muted()`。

> 封面用的是「点任意处进书」，但播的是 `_unhandled_input`，所以点音乐开关只会静音，不会顺带进书。

## 关键参数速查

| 想改什么 | 改哪里 |
| --- | --- |
| 启动场景 | `project.godot` → `application/run/main_scene` |
| 分辨率 / 窗口大小 | `project.godot` → `display/window/size/*` |
| 页面图片目录 | 场景里 `FanShu` 节点 → `page_dir` |
| 印刷目录页目录 / 页数 | 场景里 `FanShu` 节点 → `toc_dir`、`toc_page_count` |
| 图片序号偏移 | 场景里 `FanShu` 节点 → `image_offset` |
| 前置页数（不响应点击翻页） | 场景里 `FanShu` 节点 → `front_pages` |
| 目录条目与跳转页 | 场景里各 `TocPage` 节点 → `targets`、`titles` |
| 目录条目区位置 | 场景里各 `TocPage` 节点 → `block_top`、`block_bottom` |
| 目录悬停/按下高亮 | 场景里各 `TocPage` 节点 → `highlight_color`（alpha 设 0 关掉） |
| 翻页时长 | `turn_to_next_page()` 里的 `0.5`（秒/页） |
| 页面缓存张数 / 预载半径 | `fanshu2.gd` → `CACHE_CAPACITY`、`PRELOAD_BACK`、`PRELOAD_FORWARD` |
| 自动回封面时间 | 场景里 `FengMianManager` 节点 → `max_times`（秒） |
| 背景视频 | 场景里 `VideoBackground` 节点 → `video_path`、`resolution` |
| 背景音乐 / 音量 / 转速 | 场景里 `MusicButton` 节点 → `stream`（在 `music_button.tscn`）、`volume_db`、`spin_speed` |

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

1. **背景视频别用高分辨率。** Theora 是 CPU 软解，4K 单帧要 50~140 ms，1080p 约 4~8 ms，
   而且是逐帧解码的，分辨率直接决定整机帧率上限。现在的 `bg.ogv` 是 1080p / 约 10.8 Mbps / 无音轨。
2. **页面贴图用 VRAM 压缩（BC7）。** `*.jpg.import` / `*.png.import` 里保持
   `compress/mode=2` + `compress/high_quality=true`。用「无损」的话，`.ctex` 内部仍是 PNG，
   每张首次使用要在主线程解码 17~31 ms、渲染线程再卡 40~70 ms，每翻一页掉好几帧。
   BC7 与源图差异只有 PSNR 47.8 dB（肉眼看不出），但换来 4 倍显存和 8 倍加载速度。
   改过导入设置后需要重新导入：`godot --headless --path . --import`。
3. **页面按需加载，不要启动时全量读。** 45 张 1920×2160 的图一次性读进来是 GB 级显存、
   启动卡数秒。`PageCache` 只保留最近用过的 16 张并预载前后若干页，显存稳定在 200 MB 左右。

导出时 `texture_format/s3tc_bptc` 必须保持开启，否则 BC7 贴图会失效。

## 打包

`export_presets.cfg` 里目前只有一份 **Web** 预设，导出路径未设置，在 Godot 的「项目 → 导出」
里选定目标平台后即可导出。首次导出需要安装对应版本的导出模板。

## 常见问题

**页面是空白/纯色**
图片命名不是纯数字，或序号断档；也可能是新加图片后没有重新导入。确认文件名为
`1.png`/`1.jpg`/`1.webp`…（支持 png、jpg/jpeg、webp、bmp、tga、svg），并在编辑器里让它完成导入。

**翻页方向或页序对不上**
先确认「书页 → 图片」的换算：看正文第一页页脚印的页码，`image_offset = 第一张正文图的序号 - 1 - 页脚号`。
本工程是 0（图片 5 = 页脚 01）。

**点目录某一行跳到隔壁或者差一页**
`targets` 里的数字是**书页号**（即图片序号），不是页脚上印的页码。两者差多少见上面的换算。

**背景视频不播放**
工程里必须放 `.ogv`（Ogg Theora），mp4/webm 都不支持。转码命令见上文。

**翻页卡顿**
先看背景视频分辨率，再看页面贴图的导入格式（见「性能要点」两条）。
