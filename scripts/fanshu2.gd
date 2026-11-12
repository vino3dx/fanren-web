extends Node
## 主场景 main.tscn 的翻书逻辑
##
## 页码布局：
##   书页 1 .. toc_page_count      = 印刷目录（来自 toc_dir 里的 1..N 图，可为 0）
##   书页 1+offset ..               = 正文，书页 p 显示图片 p - image_offset
## 内容自带扉页/目录时（现在这套《凡人修仙传·仙侠手账》就是），把 toc_page_count 与
## image_offset 都设成 0，书页 p 直接对应第 p 张图。
##
## 目录点击区不再写死坐标：场景里每个 TocPage 节点自己描述「印在第几页、条目区在哪、
## 有几个条目、点了跳哪页」，这里只负责在翻页时把当前页号发给它们。
class_name Fanshu2

## 邻居页预载半径（提前把隔壁几页读进缓存，翻页时就不用等加载）
const PRELOAD_BACK := 3
const PRELOAD_FORWARD := 8
## 缓存容量（张），每张 BC7 1920x2160 ≈ 4 MB
const CACHE_CAPACITY := 16
## 启动时同步预热的页数
const WARMUP_PAGES := 6

## 正文图片目录（支持 png/jpg/jpeg/webp/bmp/tga/svg，纯数字文件名）
@export var page_dir: String = "res://assets/pages"
## 印刷目录页目录（toc_page_count = 0 时不需要；本工程内容自带目录页，留空即可）
@export var toc_dir: String = ""
## 书前插入的印刷目录页数（0 = 不用外部目录，正文图片自带目录页）
@export var toc_page_count: int = 0
## 图片序号 → 书页的偏移：书页 = 图片序号 + image_offset
@export var image_offset: int = 0
## 前置页数（扉页 + 目录页）：这些页上显示「下一页」箭头，且不响应 3D 点击翻页
@export var front_pages: int = 5

@export var book_path: NodePath = NodePath("../Book")
@export var camera_path: NodePath = NodePath("../Main Camera")
@export var feng_mian_manager_path: NodePath = NodePath("../FengMianManager")
@export var next_button_path: NodePath = NodePath("../UI_Book/Root/Panel/下一页")
@export var back_feng_mian_path: NodePath = NodePath("../UI_Top/Root/返回封面")
@export var back_first_path: NodePath = NodePath("../UI_Top/Root/返回目录")
## 目录覆盖层的根节点：它下面（含多层）所有 TocPage 都会被自动接管，增删节点不用改代码
@export var toc_root_path: NodePath = NodePath("../UI_Book/Root/Panel")
@export var page_material_template: Material = null
@export var page_filler_material: Material = null

var book: EndlessBook = null
var camera: Camera3D = null
var feng_mian_manager: FengMianManager = null
var next_button: BaseButton = null
var back_feng_mian: BaseButton = null
var back_first: BaseButton = null

var _toc_pages: Array[TocPage] = []
var _cache: PageCache = null
var _ui_page: int = -1

func _ready() -> void:
	book = get_node_or_null(book_path) as EndlessBook
	camera = get_node_or_null(camera_path) as Camera3D
	feng_mian_manager = get_node_or_null(feng_mian_manager_path) as FengMianManager
	next_button = get_node_or_null(next_button_path) as BaseButton
	back_feng_mian = get_node_or_null(back_feng_mian_path) as BaseButton
	back_first = get_node_or_null(back_first_path) as BaseButton

	if book == null:
		push_error("Fanshu2: 找不到 Book 节点 (%s)" % book_path)
		return
	if page_filler_material:
		book.page_filler_material = page_filler_material

	_cache = PageCache.new(page_dir, page_material_template, image_offset, CACHE_CAPACITY)
	var max_img := _cache.probe_max_page()
	book.page_material_provider = _cache.get_material
	_setup_pages(max_img)

	# 第一屏预热：此时还停在封面上，几毫秒的开销看不出来
	for i in range(1, WARMUP_PAGES + 1):
		_cache.load_now(i)

	if next_button:
		next_button.pressed.connect(turn_to_next_page)
	if back_feng_mian:
		back_feng_mian.pressed.connect(_on_back_feng_mian)
	if back_first:
		back_first.pressed.connect(_on_back_first)

	# 目录覆盖层：自动发现并接管
	_toc_pages = _collect_toc_pages(get_node_or_null(toc_root_path))
	for t in _toc_pages:
		t.page_chosen.connect(_on_toc_page_chosen)

## 递归收集所有 TocPage（含嵌套在页框里的）
func _collect_toc_pages(root: Node) -> Array[TocPage]:
	var found: Array[TocPage] = []
	if root == null:
		return found
	for c in root.get_children():
		if c is TocPage:
			found.append(c as TocPage)
		found.append_array(_collect_toc_pages(c))
	return found

func _on_toc_page_chosen(target_page: int) -> void:
	if book == null:
		return
	book.turn_to_page(target_page, EndlessBook.TurnTimeType.TOTAL_TURN_TIME, 1.0)

func _setup_pages(max_img: int) -> void:
	for i in range(1, toc_page_count + 1):
		book.add_page_data()
		var tex := _load_toc_texture(i)
		if tex:
			book.set_page_data(i, _make_material(tex))
		else:
			push_warning("缺少目录页图片: %s/%d.*" % [toc_dir, i])
	# 最后一页 = 最大图片序号 + 偏移；前面的 toc_page_count 页是外部目录
	var page_count: int = maxi(max_img + image_offset, toc_page_count)
	while book.last_page_number < page_count:
		book.add_page_data()
	var content_pages: int = maxi(page_count - toc_page_count, 0)
	print("Fanshu2: 目录 %d 页 + 正文 %d 页（图片 %d..%d）" % [
		toc_page_count, content_pages, image_offset + 1, max_img])
	book.set_page_number(1)

func _load_toc_texture(index: int) -> Texture2D:
	if toc_dir.is_empty():
		return null
	# 目录页同样支持 png/jpg/jpeg/webp/bmp/tga/svg
	var path := PageCache.find_image(toc_dir, index)
	if path == "":
		return null
	return load(path) as Texture2D

func _make_material(tex: Texture2D) -> Material:
	var mat: Material = page_material_template.duplicate() if page_material_template else StandardMaterial3D.new()
	if mat is BaseMaterial3D:
		var b := mat as BaseMaterial3D
		b.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		b.cull_mode = BaseMaterial3D.CULL_DISABLED
		b.albedo_texture = tex
	return mat

func _on_back_feng_mian() -> void:
	book.set_page_number(1)
	if feng_mian_manager:
		feng_mian_manager.set_first()

func _on_back_first() -> void:
	book.turn_to_page(1, EndlessBook.TurnTimeType.TOTAL_TURN_TIME, 2.0)

func _process(_delta: float) -> void:
	if book == null:
		return
	# 预载邻居页（每帧最多一页）
	if _cache:
		_cache.tick()

	var page: int = book.current_page_number
	if page != _ui_page:
		_ui_page = page
		_update_ui(page)
		_preload_around(page)

	# 前置页（扉页/目录）上不响应 3D 点击翻页，改用「下一页」按钮
	if book.current_left_page_number > front_pages and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if get_viewport().gui_get_hovered_control() == null:
			_handle_page_click()

func _preload_around(page: int) -> void:
	if _cache == null:
		return
	_cache.set_keep([page - 1, page, page + 1, page + 2])
	var pages: Array = []
	for p in range(page - PRELOAD_BACK, page + PRELOAD_FORWARD + 1):
		pages.append(p)
	_cache.request_preload(pages, page)

func _update_ui(page: int) -> void:
	if next_button:
		next_button.visible = page <= front_pages
	if back_first:
		back_first.visible = page > 1
	if back_feng_mian:
		back_feng_mian.visible = true
	# 每组目录只在它所属的那一屏出现（两页一组，与书的页码分组一致）
	var cur_left: int = EndlessBook.left_page_number(page)
	for t in _toc_pages:
		t.set_left_page(cur_left)

func _handle_page_click() -> void:
	var cam: Camera3D = camera if camera else get_viewport().get_camera_3d()
	if cam == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var to := from + cam.project_ray_normal(mouse) * 100.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var node: Node = hit.get("collider")
	if node == null:
		return
	if node.name == "Page Left":
		turn_to_previous_page()
	elif node.name == "Page Right":
		turn_to_next_page()

func turn_to_next_page() -> void:
	book.turn_forward(0.5)

func turn_to_previous_page() -> void:
	book.turn_backward(0.5)

func go_to_cover() -> void:
	book.set_page_number(1)

func go_to_last_page() -> void:
	book.set_page_number(book.last_page_number)
