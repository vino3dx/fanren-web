extends RefCounted
## 页面材质缓存（LRU + 提前预载）
##
## 与 Unity 版的差别：Unity 是 ImageLoaderManager 启动时一次性建好整本书的材质；
## 86 张 1920x2160 的页面会吃掉 1.4 GB 显存、启动卡 6 秒，这里改成按需加载。
##
## 性能前提：页面贴图的导入格式必须是 compress/mode=2（VRAM 压缩 / BC7）。
## 原来用「无损」存进 .ctex（内部仍是 PNG），每次“首次使用”要在主线程解码 17~31 ms、
## 渲染线程再卡 40~70 ms，于是每翻一页掉好几帧。换成 BC7 后纹理是 GPU 直读的，
## 一次加载只有读 4 MB + 上传，约 2~4 ms，所以这里可以放心同步加载，也不会出现空白页。
class_name PageCache

## 缓存上限（张）。每张 BC7 1920x2160 ≈ 4 MB，16 张约 64 MB
const DEFAULT_CAPACITY := 16
## 每帧最多预载几页（预载同样走同步读取，摊到多帧免得挤在一起）
const PRELOAD_PER_FRAME := 1

## 支持的图片格式（按优先级排序：同一序号有多种格式时取靠前的）
const SUPPORTED_IMAGE_EXTS := ["png", "jpg", "jpeg", "webp", "bmp", "tga", "svg"]

static func is_supported_image(path: String) -> bool:
	return SUPPORTED_IMAGE_EXTS.has(path.get_extension().to_lower())

## 在目录里按「纯数字文件名」找图，自动尝试所有支持的扩展名。
## 返回资源路径，找不到返回空字符串。
static func find_image(dir: String, index: int) -> String:
	var base := dir.rstrip("/")
	for ext in SUPPORTED_IMAGE_EXTS:
		var path := "%s/%d.%s" % [base, index, ext]
		if ResourceLoader.exists(path):
			return path
	return ""

## 同一序号有多种格式时的优先级（越小越优先）
static func ext_rank(ext: String) -> int:
	var rank := SUPPORTED_IMAGE_EXTS.find(ext.to_lower())
	return rank if rank >= 0 else SUPPORTED_IMAGE_EXTS.size()

var page_dir: String
var template: Material
var capacity: int = DEFAULT_CAPACITY
## 页码 → 图片序号的偏移：图片 i 对应书页 i + image_offset
## （内容自带扉页/目录时为 0，即书页 p 显示图片 p；前置印刷目录时通常为 3）
var image_offset: int = 3

var load_count: int = 0

var _entries: Dictionary = {}     # page_number -> Material
var _order: Array = []            # LRU：尾部最新
var _pending: Array = []          # 待预载的页码
var _images: Dictionary = {}      # 实际存在的图片序号
var _files: Dictionary = {}       # 图片序号 -> 实际文件名（含扩展名）
var _keep: Dictionary = {}        # 禁止淘汰的页码（当前可视范围）
var _max_page: int = 0

func _init(dir: String, mat_template: Material, offset: int = 3, cap: int = DEFAULT_CAPACITY) -> void:
	page_dir = dir.rstrip("/")
	template = mat_template
	image_offset = offset
	capacity = maxi(cap, 8)

func image_of_page(page_number: int) -> int:
	return page_number - image_offset

func page_of_image(image_index: int) -> int:
	return image_index + image_offset

## 扫描目录，得到可用页数（避免逐页 ResourceLoader.exists）
## 支持 png/jpg/jpeg/webp/bmp/tga/svg，同一序号有多个格式时按优先级取一个
func probe_max_page(limit: int = 400) -> int:
	var m := 0
	_images.clear()
	_files.clear()
	var da := DirAccess.open(page_dir)
	if da == null:
		push_error("PageCache: 打不开图片目录 %s" % page_dir)
		return 0
	for f in da.get_files():
		var ext := f.get_extension().to_lower()
		if not SUPPORTED_IMAGE_EXTS.has(ext):
			continue
		var n := f.get_basename().to_int()
		if n <= 0 or n > limit:
			continue
		if _files.has(n) and ext_rank(ext) >= ext_rank(_files[n].get_extension()):
			continue
		_files[n] = f
		_images[n] = true
		m = maxi(m, n)
	_max_page = m
	return _max_page

func max_page() -> int:
	return _max_page

## 可用的最大书页页码（图片序号 + 偏移）
func max_page_number() -> int:
	return _max_page + image_offset

## 正文页从第 image_offset + 1 页开始
func min_page_number() -> int:
	return image_offset + 1

func has(page_number: int) -> bool:
	return _entries.has(page_number)

func pending_count() -> int:
	return _pending.size()

func path_of_page(page_number: int) -> String:
	var img := image_of_page(page_number)
	if not _files.has(img):
		return ""
	return "%s/%s" % [page_dir, _files[img]]

## 取材质：命中直接返回，未命中同步加载（BC7 下约 2~4 ms）
func get_material(page_number: int) -> Material:
	if page_number < min_page_number() or page_number > max_page_number():
		return null
	var m: Material = _entries.get(page_number)
	if m != null:
		_touch(page_number)
		return m
	return load_now(page_number)

## 立即加载并建材质
func load_now(page_number: int) -> Material:
	var m: Material = _entries.get(page_number)
	if m != null:
		_touch(page_number)
		return m
	if page_number < min_page_number() or page_number > max_page_number():
		return null
	if not _images.has(image_of_page(page_number)):
		return null
	var path := path_of_page(page_number)
	if path == "" or not ResourceLoader.exists(path):
		return null
	var tex := ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	if tex == null:
		return null
	return _make_entry(page_number, tex)

## 禁止淘汰的页码（通常是当前左右页），避免刚显示就被挤掉再重新加载
func set_keep(pages: Array) -> void:
	_keep.clear()
	for p in pages:
		_keep[int(p)] = true

## 预载邻居页；center 用于按“离当前页远近”排序，近的先加载
func request_preload(pages: Array, center: int = -1) -> void:
	var list: Array = []
	for p in pages:
		var n := int(p)
		if n < min_page_number() or n > max_page_number():
			continue
		if _entries.has(n) or _pending.has(n):
			continue
		list.append(n)
	if center >= 0:
		list.sort_custom(func(a, b): return absi(a - center) < absi(b - center))
	_pending.append_array(list)

func clear_pending() -> void:
	_pending.clear()

## 每帧推进预载队列（每帧最多 PRELOAD_PER_FRAME 页）
func tick() -> void:
	var made := 0
	while made < PRELOAD_PER_FRAME and not _pending.is_empty():
		var p: int = int(_pending.pop_front())
		if _entries.has(p):
			continue
		load_now(p)
		made += 1

func _make_entry(page_number: int, tex: Texture2D) -> Material:
	load_count += 1
	var mat: Material = template.duplicate() if template else StandardMaterial3D.new()
	if mat is BaseMaterial3D:
		var b := mat as BaseMaterial3D
		b.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		b.cull_mode = BaseMaterial3D.CULL_DISABLED
		b.albedo_texture = tex
		b.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_entries[page_number] = mat
	_touch(page_number)
	_evict()
	return mat

func _touch(page_number: int) -> void:
	var i := _order.find(page_number)
	if i >= 0:
		_order.remove_at(i)
	_order.append(page_number)

func _evict() -> void:
	while _order.size() > capacity:
		var victim := -1
		for i in _order.size():
			if not _keep.has(int(_order[i])):
				victim = i
				break
		if victim < 0:
			return
		var old: int = int(_order[victim])
		_order.remove_at(victim)
		_entries.erase(old)
