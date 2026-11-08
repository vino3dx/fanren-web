extends Node3D
## EndlessBook 的 Godot 移植版（对应 Unity echo17.EndlessBook.EndlessBook.cs）
## 负责书本状态切换、翻页、以及按“页面材质”更新书页贴图。
class_name EndlessBook

signal state_changed(from_state: int, to_state: int, page_number: int)
signal page_turn_start(page: Node, front: int, back: int, first_visible: int, last_visible: int, direction: int)
signal page_turn_end(page: Node, front: int, back: int, first_visible: int, last_visible: int, direction: int)

enum State { CLOSED_FRONT, OPEN_FRONT, OPEN_MIDDLE, OPEN_BACK, CLOSED_BACK }
enum TurnDirection { FORWARD, BACKWARD }
enum TurnTimeType { TOTAL_TURN_TIME, TIME_PER_PAGE }

## BookAnimated.fbx 中的 take 被拆成 10 段，每段 59 帧 @24fps
const BOOK_CLIP_LENGTH := 59.0 / 24.0
## Page.fbx 中 TurnForward / TurnBackward 各 23 帧 @24fps
const PAGE_CLIP_LENGTH := 23.0 / 24.0

const BOOK_SEGMENTS := {
	"ClosedFrontToOpenMiddle": 0.0,
	"OpenMiddleToClosedBack": 62.0 / 24.0,
	"ClosedFrontToOpenFront": 124.0 / 24.0,
	"OpenFrontToOpenMiddle": 186.0 / 24.0,
	"OpenMiddleToOpenBack": 248.0 / 24.0,
	"OpenBackToClosedBack": 310.0 / 24.0,
	"ClosedFrontToClosedBack": 372.0 / 24.0,
	"OpenFrontToClosedBack": 434.0 / 24.0,
	"OpenFrontToOpenBack": 496.0 / 24.0,
	"ClosedFrontToOpenBack": 558.0 / 24.0,
}
const PAGE_SEGMENTS := {
	"TurnForward": 0.0,
	"TurnBackward": 26.0 / 24.0,
}

@export var max_pages_turning_count: int = 4
## 对应 Unity EndlessBook 的 materials 数组（BookCover / BookPageBack / BookPageFront / BookPageLeft / BookPageRight）
@export var material_cover: Material = null
@export var material_page_back: Material = null
@export var material_page_front: Material = null
@export var material_page_left: Material = null
@export var material_page_right: Material = null

var current_state: int = State.OPEN_MIDDLE
var current_page_number: int = 0
var is_turning_pages: bool = false
var is_changing_state: bool = false
var page_filler_material: Material = null

var page_data: Array = []
var pages: Array = []
var standins: Array = []
## 页面材质按需提供者（页表里为 null 的页由它现取，签名 func(page_number:int) -> Material）
var page_material_provider: Callable = Callable()

var _surface_map: Dictionary = {}
var _seg: Dictionary = {}
var _turn: Dictionary = {}

@onready var book_animated: Node3D = $BookAnimated
@onready var book_mesh: MeshInstance3D = $BookAnimated/Book_Armature/Skeleton3D/Book
@onready var book_anim: AnimationPlayer = $BookAnimated/AnimationPlayer
@onready var standins_root: Node3D = $Standins
@onready var pages_root: Node3D = $Pages

func _ready() -> void:
	for c in standins_root.get_children():
		standins.append(c)
	standins.sort_custom(func(a, b): return _standin_order(a.name) < _standin_order(b.name))
	for c in pages_root.get_children():
		pages.append(c)
		c.turn_completed.connect(_on_page_turn_completed)
		c.visible = false
	_collect_surfaces()
	_apply_default_materials()
	book_animated.visible = false
	for i in standins.size():
		standins[i].visible = (i == current_state)
	# 空闲时不参与每帧处理，只有状态切换 / 翻页时才打开
	set_process(false)

func _standin_order(n: String) -> int:
	if n.begins_with("BookStandinClosedFront"): return State.CLOSED_FRONT
	if n.begins_with("BookStandinOpenFront"): return State.OPEN_FRONT
	if n.begins_with("BookStandinOpenMiddle"): return State.OPEN_MIDDLE
	if n.begins_with("BookStandinOpenBack"): return State.OPEN_BACK
	if n.begins_with("BookStandinClosedBack"): return State.CLOSED_BACK
	return 99

# ---------------------------------------------------------------- 材质映射

func _find_meshes(root: Node, out: Array) -> void:
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		_find_meshes(c, out)

func _collect_surfaces() -> void:
	_surface_map.clear()
	var meshes: Array = []
	if book_mesh: meshes.append(book_mesh)
	for s in standins:
		_find_meshes(s, meshes)
	for mi in meshes:
		if mi == null or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m: Material = mi.get_active_material(i)
			var n: String = m.resource_name if m else ""
			if not _surface_map.has(n):
				_surface_map[n] = []
			_surface_map[n].append([mi, i])

func set_material_name(mat_name: String, material: Material) -> void:
	for entry in _surface_map.get(mat_name, []):
		entry[0].set_surface_override_material(entry[1], material)

func _apply_default_materials() -> void:
	set_material_name("BookCover", material_cover)
	set_material_name("BookPageBack", material_page_back)
	set_material_name("BookPageFront", material_page_front)
	set_material_name("BookPageLeft", material_page_left)
	set_material_name("BookPageRight", material_page_right)

# ---------------------------------------------------------------- 页码工具

static func right_page_number(p: int) -> int:
	return p + 1 if p % 2 != 0 else p

static func left_page_number(p: int) -> int:
	return p if p % 2 != 0 else p - 1

var current_left_page_number: int:
	get: return left_page_number(current_page_number)
var current_right_page_number: int:
	get: return right_page_number(current_page_number)
var is_first_page_group: bool:
	get: return current_left_page_number == 1
var is_last_page_group: bool:
	get: return current_right_page_number == right_page_number(page_data.size())
var last_page_number: int:
	get: return page_data.size()

func get_page_material(page_number: int) -> Material:
	if page_number >= 1 and page_number <= page_data.size():
		var m: Material = page_data[page_number - 1]
		if m != null:
			return m
		# 页表里没有预置材质（正文页），交给按需缓存
		if page_material_provider.is_valid():
			var loaded: Material = page_material_provider.call(page_number)
			if loaded != null:
				return loaded
		return page_filler_material
	return page_filler_material

func set_page_number(page_number: int) -> void:
	current_page_number = page_number
	set_material_name("BookPageLeft", get_page_material(left_page_number(page_number)))
	set_material_name("BookPageRight", get_page_material(right_page_number(page_number)))

# ---------------------------------------------------------------- 段播放

func _start_segment(anim_name: String, start: float, length: float, duration: float, reverse: bool, callback: Callable) -> void:
	# pause() 会清空 current_animation，这里用 assigned_animation 判断，避免重复 play
	if book_anim.assigned_animation != anim_name:
		book_anim.play(anim_name)
	book_anim.pause()
	book_anim.seek(start + (length if reverse else 0.0), true)
	set_process(true)
	_seg = {
		"active": true,
		"start": start,
		"length": length,
		"duration": maxf(duration, 0.001),
		"elapsed": 0.0,
		"reverse": reverse,
		"callback": callback,
	}

func _process(delta: float) -> void:
	# 状态切换动画
	if _seg.get("active", false):
		_seg["elapsed"] = _seg["elapsed"] + delta
		var t: float = clampf(_seg["elapsed"] / _seg["duration"], 0.0, 1.0)
		var k: float = 1.0 - t if _seg["reverse"] else t
		book_anim.seek(_seg["start"] + _seg["length"] * k, true)
		if t >= 1.0:
			_seg["active"] = false
			var cb: Callable = _seg["callback"]
			_seg["callback"] = Callable()
			if cb.is_valid():
				cb.call()
	# 翻页调度
	elif is_turning_pages and int(_turn.get("pages_left_to_turn", 0)) > 0:
		_turn["delay_remaining"] = float(_turn["delay_remaining"]) - delta
		if float(_turn["delay_remaining"]) <= 0.0:
			_turn["last_active_page_index"] = int(_turn["last_active_page_index"]) + 1
			if int(_turn["last_active_page_index"]) > max_pages_turning_count:
				_turn["last_active_page_index"] = 0
			_turn_page(pages[int(_turn["last_active_page_index"])])

	# 完全空闲时停掉每帧回调
	if not _seg.get("active", false) and not is_turning_pages:
		set_process(false)

# ---------------------------------------------------------------- 状态切换

func _clip_name_for(from_state: int, to_state: int) -> String:
	match from_state:
		State.CLOSED_FRONT:
			match to_state:
				State.OPEN_FRONT: return "ClosedFrontToOpenFront"
				State.OPEN_MIDDLE: return "ClosedFrontToOpenMiddle"
				State.OPEN_BACK: return "ClosedFrontToOpenBack"
				State.CLOSED_BACK: return "ClosedFrontToClosedBack"
		State.OPEN_FRONT:
			match to_state:
				State.CLOSED_FRONT: return "ClosedFrontToOpenFront"
				State.OPEN_MIDDLE: return "OpenFrontToOpenMiddle"
				State.OPEN_BACK: return "OpenFrontToOpenBack"
				State.CLOSED_BACK: return "OpenFrontToClosedBack"
		State.OPEN_MIDDLE:
			match to_state:
				State.CLOSED_FRONT: return "ClosedFrontToOpenMiddle"
				State.OPEN_FRONT: return "OpenFrontToOpenMiddle"
				State.OPEN_BACK: return "OpenMiddleToOpenBack"
				State.CLOSED_BACK: return "OpenMiddleToClosedBack"
		State.OPEN_BACK:
			match to_state:
				State.CLOSED_FRONT: return "ClosedFrontToOpenBack"
				State.OPEN_FRONT: return "OpenFrontToOpenBack"
				State.OPEN_MIDDLE: return "OpenMiddleToOpenBack"
				State.CLOSED_BACK: return "OpenBackToClosedBack"
		State.CLOSED_BACK:
			match to_state:
				State.CLOSED_FRONT: return "ClosedFrontToClosedBack"
				State.OPEN_FRONT: return "OpenFrontToClosedBack"
				State.OPEN_MIDDLE: return "OpenMiddleToClosedBack"
				State.OPEN_BACK: return "OpenBackToClosedBack"
	return "ClosedFrontToOpenMiddle"

func set_state(state: int, animation_time: float = 1.0, on_completed: Callable = Callable()) -> void:
	if state == current_state or is_changing_state or is_turning_pages:
		return
	if animation_time <= 0.0:
		if standins[current_state]: standins[current_state].visible = false
		_book_animation_completed(state, on_completed)
		return
	is_changing_state = true
	var clip: String = _clip_name_for(current_state, state)
	var reverse: bool = state < current_state
	book_animated.visible = true
	book_mesh.visible = false
	standins[current_state].visible = false
	_start_segment(clip, BOOK_SEGMENTS[clip], BOOK_CLIP_LENGTH, animation_time, reverse,
		func(): _book_animation_completed(state, on_completed))
	await get_tree().process_frame
	book_mesh.visible = true

func _book_animation_completed(new_state: int, on_completed: Callable) -> void:
	var old_state: int = current_state
	current_state = new_state
	book_animated.visible = false
	if standins[current_state]: standins[current_state].visible = true
	is_changing_state = false
	state_changed.emit(old_state, current_state, current_page_number)
	if on_completed.is_valid():
		on_completed.call(old_state, current_state, current_page_number)

# ---------------------------------------------------------------- 翻页

func turn_to_page(page_number: int, turn_type: int, time: float, open_time: float = 1.0, on_completed: Callable = Callable()) -> void:
	if is_turning_pages or is_changing_state:
		return
	if current_state == State.OPEN_MIDDLE and _is_in_current_page_group(page_number):
		if page_number == current_page_number:
			return
		set_page_number(page_number)
		return
	if page_number < 1 or page_number > page_data.size():
		print("翻书: 非法页码 ", page_number, " (范围 1..", page_data.size(), ")")
		return
	_turn = {
		"page_number": page_number,
		"turn_type": turn_type,
		"time": time,
		"on_completed": on_completed,
	}
	if current_state != State.OPEN_MIDDLE:
		var cb: Callable = on_completed if _is_in_current_page_group(page_number) else func(_a, _b, _c): _turn_to_page_internal()
		set_state(State.OPEN_MIDDLE, open_time, cb)
		return
	if _is_in_current_page_group(page_number):
		set_page_number(page_number)
		return
	_turn_to_page_internal()

func _is_in_current_page_group(page_number: int) -> bool:
	return right_page_number(page_number) == right_page_number(current_page_number)

func _turn_to_page_internal() -> void:
	for i in pages.size():
		pages[i].index = i
	var current_right: int = right_page_number(current_page_number)
	var page_diff: int = right_page_number(_turn["page_number"]) - current_right
	var page_count: int = absi(page_diff)
	var direction: int = TurnDirection.FORWARD if page_diff > 0 else TurnDirection.BACKWARD
	_turn["turn_direction"] = direction
	# page_count 恒为偶数，这里显式取整以避免整数除法告警
	_turn["pages_left_to_turn"] = int(page_count / 2.0)
	_turn["pages_left_to_complete"] = _turn["pages_left_to_turn"]

	var total_turn_time: float = 1.0
	var time_per_page: float = 1.0
	var n: float = float(_turn["pages_left_to_turn"])
	if int(_turn["turn_type"]) == TurnTimeType.TIME_PER_PAGE:
		time_per_page = float(_turn["time"])
		total_turn_time = time_per_page * (((n - 1.0) / float(max_pages_turning_count)) + 1.0)
	else:
		total_turn_time = float(_turn["time"])
		time_per_page = float(_turn["time"]) / (((n - 1.0) / float(max_pages_turning_count)) + 1.0)

	_turn["delay_between"] = (total_turn_time - time_per_page) / maxf(n - 1.0, 1.0)
	_turn["page_turn_time"] = time_per_page
	_turn["last_active_page_index"] = -1
	_turn["far_page_number"] = left_page_number(current_page_number) if direction == TurnDirection.FORWARD else current_right
	_turn["last_page_number"] = current_right
	_turn["delay_remaining"] = 0.0
	is_turning_pages = true
	set_process(true)

func _turn_page(page: Node) -> void:
	_turn["pages_left_to_turn"] = int(_turn["pages_left_to_turn"]) - 1
	_turn["delay_remaining"] = float(_turn["delay_between"])
	var direction: int = int(_turn["turn_direction"])
	_turn["last_page_number"] = int(_turn["last_page_number"]) + (1 if direction == TurnDirection.FORWARD else -1) * 2

	var page_front: int = -1
	var page_back: int = -1
	var first_visible: int = -1
	var last_visible: int = -1
	if direction == TurnDirection.FORWARD:
		page_front = int(_turn["last_page_number"]) - 2
		page_back = int(_turn["last_page_number"]) - 1
		first_visible = int(_turn["far_page_number"])
		last_visible = int(_turn["last_page_number"])
	else:
		page_front = int(_turn["last_page_number"])
		page_back = int(_turn["last_page_number"]) + 1
		first_visible = int(_turn["last_page_number"]) - 1
		last_visible = int(_turn["far_page_number"])

	page_turn_start.emit(page, page_front, page_back, first_visible, last_visible, direction)
	page.turn(direction, float(_turn["page_turn_time"]), get_page_material(page_front), get_page_material(page_back))

	if direction == TurnDirection.FORWARD:
		set_material_name("BookPageRight", get_page_material(last_visible))
	else:
		set_material_name("BookPageLeft", get_page_material(first_visible))

func _on_page_turn_completed(page: Node) -> void:
	var direction: int = int(_turn["turn_direction"])
	_turn["far_page_number"] = int(_turn["far_page_number"]) + (1 if direction == TurnDirection.FORWARD else -1) * 2
	_turn["pages_left_to_complete"] = int(_turn["pages_left_to_complete"]) - 1
	page_turn_end.emit(page, 0, 0, int(_turn["far_page_number"]), int(_turn["last_page_number"]), direction)

	if int(_turn["pages_left_to_complete"]) == 0:
		is_turning_pages = false
		set_page_number(int(_turn["page_number"]))
		var cb: Callable = _turn.get("on_completed", Callable())
		if cb.is_valid():
			cb.call(State.OPEN_MIDDLE, State.OPEN_MIDDLE, current_page_number)
	else:
		if direction == TurnDirection.FORWARD:
			set_material_name("BookPageLeft", page.back_material)
		else:
			set_material_name("BookPageRight", page.front_material)

func turn_forward(time: float = 0.5, on_completed: Callable = Callable()) -> void:
	if current_state != State.OPEN_MIDDLE or is_last_page_group:
		return
	turn_to_page(current_left_page_number + 2, TurnTimeType.TIME_PER_PAGE, time, 1.0, on_completed)

func turn_backward(time: float = 0.5, on_completed: Callable = Callable()) -> void:
	if current_state != State.OPEN_MIDDLE or is_first_page_group:
		return
	turn_to_page(current_left_page_number - 2, TurnTimeType.TIME_PER_PAGE, time, 1.0, on_completed)

func stop_turning_pages() -> void:
	if not is_turning_pages:
		return
	is_turning_pages = false
	for p in pages:
		p.visible = false
	set_page_number(int(_turn.get("page_number", current_page_number)))

# ---------------------------------------------------------------- 页数据

func add_page_data(material: Material = null) -> void:
	page_data.append(material)

func get_page_data(page_number: int) -> Material:
	if page_number >= 1 and page_number <= page_data.size():
		return page_data[page_number - 1]
	return null

func set_page_data(page_number: int, material: Material) -> void:
	if page_number >= 1 and page_number <= page_data.size():
		page_data[page_number - 1] = material
