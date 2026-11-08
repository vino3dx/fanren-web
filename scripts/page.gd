extends Node3D
## 单张翻动页面（对应 Unity echo17.EndlessBook.Page.cs）
## Page.fbx 的 take 内包含 TurnForward / TurnBackward 两段动画，按段播放。
class_name BookPage

signal turn_completed(page: Node)

const SEGMENTS := {
	0: 0.0,            # TurnDirection.FORWARD
	1: 26.0 / 24.0,    # TurnDirection.BACKWARD
}
const SEG_LENGTH := 23.0 / 24.0

var index: int = 0
var front_material: Material = null
var back_material: Material = null

var _anim: AnimationPlayer
var _mesh: MeshInstance3D
var _front_surface: int = 0
var _back_surface: int = 1

var _turning: bool = false
var _start: float = 0.0
var _length: float = SEG_LENGTH
var _duration: float = 1.0
var _elapsed: float = 0.0

func _ready() -> void:
	_mesh = find_child("Page", true, false)
	_anim = find_child("AnimationPlayer", true, false)
	_index_surfaces()
	# 不翻动时不需要每帧 seek
	set_process(false)

func _index_surfaces() -> void:
	if _mesh == null or _mesh.mesh == null:
		return
	for i in _mesh.mesh.get_surface_count():
		var m: Material = _mesh.get_active_material(i)
		var n: String = m.resource_name if m else ""
		if n == "PageFront":
			_front_surface = i
		elif n == "PageBack":
			_back_surface = i

func _material_name() -> String:
	var list := _anim.get_animation_list()
	if list.size() > 0:
		return list[0]
	return ""

func set_page_materials(front: Material, back: Material) -> void:
	front_material = front
	back_material = back
	if _mesh:
		_mesh.set_surface_override_material(_front_surface, front)
		_mesh.set_surface_override_material(_back_surface, back)

func turn(direction: int, time: float, front: Material, back: Material) -> void:
	visible = true
	set_page_materials(front, back)
	_turning = true
	_elapsed = 0.0
	_duration = time if time > 0.0 else 0.001
	_start = SEGMENTS.get(direction, 0.0)
	_length = SEG_LENGTH
	var anim_name := _material_name()
	if anim_name != "":
		if _anim.assigned_animation != anim_name:
			_anim.play(anim_name)
		_anim.pause()
		_anim.seek(_start, true)
		set_process(true)

func _process(delta: float) -> void:
	if not _turning:
		return
	_elapsed += delta
	var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
	if _anim != null and _anim.assigned_animation != "":
		_anim.seek(_start + _length * t, true)
	if t >= 1.0:
		_turning = false
		_animation_completed()

func _animation_completed() -> void:
	set_process(false)
	visible = false
	turn_completed.emit(self)
