extends Node
## 案例目录按钮组（对应 Unity AnLiManager.cs）
class_name AnLiManager

@export var book_path: NodePath = NodePath("../../../Book")
@export var buttons: Array[NodePath] = []
@export var pages: PackedInt32Array = PackedInt32Array()

var _inited: bool = false

func init() -> void:
	if _inited:
		return
	_inited = true
	var book := get_node_or_null(book_path) as EndlessBook
	for i in buttons.size():
		var id: int = i
		var btn := get_node_or_null(buttons[i]) as BaseButton
		if btn == null:
			continue
		btn.pressed.connect(func():
			if book == null or id >= pages.size():
				return
			book.turn_to_page(pages[id], EndlessBook.TurnTimeType.TOTAL_TURN_TIME, 1.0)
			print("翻到", pages[id], "页"))
