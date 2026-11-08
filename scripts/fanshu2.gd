extends Node
## 「执法复议案例」主逻辑（对应 Unity Fanshu2.cs）
##
## 页码布局与 Unity 里 AnLiManager 的序列化数据一致（Fanshu2.cs 原本就是这个方案）：
##   1..4 页  = 印刷目录（Materials/行政复议案例/目录5..8.png）
##   5..N 页  = 正文，正文图片 i 对应页 i + 3（图片 1 是书名页，不进书）
class_name Fanshu2

const TOC_PAGE_COUNT := 4
## 邻居页预载半径（提前把隔壁几页读进缓存，翻页时就不用等加载）
const PRELOAD_BACK := 3
const PRELOAD_FORWARD := 8
## 缓存容量（张），每张 BC7 1920x2160 ≈ 4 MB
const CACHE_CAPACITY := 16
## 启动时同步预热的页数
const WARMUP_PAGES := 6

## 正文图片目录（对应 Unity 的 Application.streamingAssetsPath + "/images"）
@export var page_dir: String = "res://assets/pages"
## 目录页图片目录（4 张，对应 Fanshu2.directoryMaterials）
@export var toc_dir: String = "res://assets/toc/fuyi"

@export var book_path: NodePath = NodePath("../Book")
@export var camera_path: NodePath = NodePath("../Main Camera")
@export var feng_mian_manager_path: NodePath = NodePath("../FengMianManager")
@export var next_button_path: NodePath = NodePath("../UI_Book/Root/Panel/下一页")
@export var back_feng_mian_path: NodePath = NodePath("../UI_Top/Root/返回封面")
@export var back_first_path: NodePath = NodePath("../UI_Top/Root/返回目录")
@export var an_li_manager_paths: Array[NodePath] = []
@export var page_material_template: Material = null
@export var page_filler_material: Material = null

var book: EndlessBook = null
var camera: Camera3D = null
var feng_mian_manager: FengMianManager = null
var next_button: BaseButton = null
var back_feng_mian: BaseButton = null
var back_first: BaseButton = null

var _anli_nodes: Array[Node] = []
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

	_cache = PageCache.new(page_dir, page_material_template, 3, CACHE_CAPACITY)
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

	for p in an_li_manager_paths:
		var a: Node = get_node_or_null(p)
		if a:
			_anli_nodes.append(a)
			if a.has_method("init"):
				a.init()

func _setup_pages(max_img: int) -> void:
	for i in range(1, TOC_PAGE_COUNT + 1):
		book.add_page_data()
		var tex := _load_toc_texture(i)
		if tex:
			book.set_page_data(i, _make_material(tex))
		else:
			push_warning("缺少目录页图片: %s/%d.png" % [toc_dir, i])
	var page_count: int = TOC_PAGE_COUNT + maxi(max_img - 1, 0)
	while book.last_page_number < page_count:
		book.add_page_data()
	print("执法复议案例: 目录 %d 页 + 正文 %d 页（正文图片 2..%d）" % [TOC_PAGE_COUNT, max_img - 1, max_img])
	book.set_page_number(1)

func _load_toc_texture(index: int) -> Texture2D:
	var path := "%s/%d.png" % [toc_dir, index]
	if not ResourceLoader.exists(path):
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

	if page >= 5 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
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
		next_button.visible = page <= 4
	if back_first:
		back_first.visible = page > 2
	if back_feng_mian:
		back_feng_mian.visible = page <= 2
	# 5 个分组的显隐：<=2 页显示前两组，>2 页显示后三组
	if page <= 2:
		_set_anli_visible([true, true, false, false, false])
	else:
		_set_anli_visible([false, false, true, true, true])

func _set_anli_visible(states: Array) -> void:
	for i in _anli_nodes.size():
		if i < states.size():
			_anli_nodes[i].visible = states[i]

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
