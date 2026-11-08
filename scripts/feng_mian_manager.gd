extends Node
## 封面/正文切换（对应 Unity FengMianManager.cs）
## 600 秒无操作自动回到封面；点击任意位置进入书本界面。
class_name FengMianManager

@export var canvas_path: NodePath = NodePath("../Cover")
@export var canvas2_path: NodePath = NodePath("../UI_Book")
@export var max_times: float = 600.0

var canvas: CanvasLayer = null
var canvas2: CanvasLayer = null
var times: float = 0.0

func _ready() -> void:
	canvas = get_node_or_null(canvas_path) as CanvasLayer
	canvas2 = get_node_or_null(canvas2_path) as CanvasLayer
	set_first()

func _process(delta: float) -> void:
	times += delta
	if times > max_times:
		set_first()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		if e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			show_book_ui()
	elif event is InputEventScreenTouch:
		if (event as InputEventScreenTouch).pressed:
			show_book_ui()

func show_book_ui() -> void:
	times = 0.0
	if canvas: canvas.visible = false
	if canvas2: canvas2.visible = true

func set_first() -> void:
	times = 0.0
	if canvas: canvas.visible = true
	if canvas2: canvas2.visible = false
