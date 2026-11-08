extends Node3D
## 左右页触摸/点击区域（对应 Unity SimpleTouchPad.cs）
## 在鼠标松开时判断是否点在左/右页碰撞盒上，并派发事件。
class_name SimpleTouchPad

signal touch_up_detected(page_side: int, normalized_pos: Vector2, dragging: bool)

enum Page { LEFT, RIGHT }

@export var main_camera: Camera3D = null
@export var left_page_collider: CollisionObject3D = null
@export var right_page_collider: CollisionObject3D = null

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var e := event as InputEventMouseButton
	if e.button_index != MOUSE_BUTTON_LEFT or e.pressed:
		return
	var cam: Camera3D = main_camera if main_camera else get_viewport().get_camera_3d()
	if cam == null:
		return
	var from := cam.project_ray_origin(e.position)
	var to := from + cam.project_ray_normal(e.position) * 100.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var node: Node = hit.get("collider")
	if node == null:
		return
	if node == left_page_collider:
		touch_up_detected.emit(Page.LEFT, _normalized(hit.get("position")), false)
	elif node == right_page_collider:
		touch_up_detected.emit(Page.RIGHT, _normalized(hit.get("position")), false)

func _normalized(world_point: Vector3) -> Vector2:
	return Vector2(world_point.x, world_point.z)
