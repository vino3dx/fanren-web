extends Node
## 封面 / 正文切换：点封面任意处进书，久无操作自动回封面。
## 点击只认「没有被 UI 吃掉」的事件，所以点左下角的音乐开关不会顺带进书。
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

func _unhandled_input(event: InputEvent) -> void:
	# 用 _unhandled_input 而不是 _input：点在按钮上（比如左下角的音乐开关）时，
	# 事件已经被 GUI 吃掉，不会顺带进书。
	var pressed := false
	if event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		pressed = e.pressed and e.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	if pressed:
		show_book_ui()

func show_book_ui() -> void:
	times = 0.0
	if canvas: canvas.visible = false
	if canvas2: canvas2.visible = true

func set_first() -> void:
	times = 0.0
	if canvas: canvas.visible = true
	if canvas2: canvas2.visible = false
