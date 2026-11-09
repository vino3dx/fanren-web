extends Control
class_name TocPage
## 目录页覆盖层：贴在某一张书页上，把「条目区」按行数均分成可点击的行。
##
## 为什么这样做：
##   目录文字是印在页面图片里的，覆盖层唯一要解决的是「每一行的点击区落在哪」。
##   印刷目录的行距是均匀的，所以不需要逐个写矩形：只要给出条目区的上下边界和行数，
##   用 VBoxContainer + EXPAND_FILL 均分，行心自然落在印刷行上。
##
## 用法：把本节点放到一个「页框」Control（尺寸 = 该页在屏幕上的矩形）下面并铺满，
##   填好 page_number / block_top / block_bottom / targets 即可。
##   - 页面图上已印好文字 → show_titles = false，只做透明点击区（本工程默认）
##   - 没有印刷目录的素材 → show_titles = true，由程序画文字，配 title_theme 换主题
##
## 换内容：改 targets（跳转页）和 titles（显示文字），行数自动 = targets.size()
## 换主题：换 title_theme，或改 title_font_size / highlight_color
## 换版式：改 block_top / block_bottom / inset_left / inset_right（0~1 相对比例）

## 点了某一行，携带目标书页号
signal page_chosen(target_page: int)

@export_group("归属")
## 这一组条目印在第几页（书页号），决定什么时候显示
@export var page_number: int = 1

@export_group("条目区")
## 条目区在页框里的上下边界（0 = 页面顶边，1 = 页面底边）
@export_range(0.0, 1.0, 0.0001) var block_top: float = 0.36
@export_range(0.0, 1.0, 0.0001) var block_bottom: float = 0.80
## 左右内缩，让点击区不要顶到页边
@export_range(0.0, 0.5, 0.001) var inset_left: float = 0.03
@export_range(0.0, 0.5, 0.001) var inset_right: float = 0.03

@export_group("内容")
## 每一行跳转到第几页
@export var targets: PackedInt32Array = PackedInt32Array()
## 每一行的文字（show_titles = true 时才用）
@export var titles: PackedStringArray = PackedStringArray()

@export_group("样式")
## 页面图上已经印了文字就关掉，只保留透明点击区
@export var show_titles: bool = false
@export var title_theme: Theme = null
@export var title_font_size: int = 34
@export var title_color: Color = Color(0.30, 0.26, 0.20, 1.0)
## 悬停/按下时的高亮底色（alpha 设 0 即完全不要反馈）
@export var highlight_color: Color = Color(0.78, 0.62, 0.32, 0.10)

var _box: VBoxContainer = null
var _rows: Array[Button] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 铺满页框
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build()
	visible = false

## 按当前 targets 重建行（改完数据想热更新时也可以再调一次）
func build() -> void:
	if _box != null and is_instance_valid(_box):
		_box.queue_free()
	_rows.clear()
	if targets.is_empty():
		return

	_box = VBoxContainer.new()
	_box.name = "Entries"
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 行间不留缝：行高由条目区均分决定（separation 在 4.x 里是主题常量）
	_box.add_theme_constant_override("separation", 0)
	_box.anchor_left = inset_left
	_box.anchor_top = block_top
	_box.anchor_right = 1.0 - inset_right
	_box.anchor_bottom = block_bottom
	_box.offset_left = 0.0
	_box.offset_top = 0.0
	_box.offset_right = 0.0
	_box.offset_bottom = 0.0
	add_child(_box)

	var empty := StyleBoxEmpty.new()
	var hover := _make_tint(highlight_color, 10)
	var pressed := _make_tint(Color(highlight_color, minf(highlight_color.a * 2.0, 1.0)), 10)

	for i in targets.size():
		var b := Button.new()
		b.name = "Entry%d" % (i + 1)
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		# 均分条目区：行高由容器决定，行心自然对齐印刷行
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if show_titles:
			b.text = titles[i] if i < titles.size() else ""
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.clip_text = true
			b.add_theme_font_size_override("font_size", title_font_size)
			b.add_theme_color_override("font_color", title_color)
			b.add_theme_color_override("font_hover_color", title_color)
			b.add_theme_color_override("font_pressed_color", title_color)
			if title_theme != null:
				b.theme = title_theme
		b.add_theme_stylebox_override("normal", empty)
		b.add_theme_stylebox_override("focus", empty)
		b.add_theme_stylebox_override("disabled", empty)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", pressed)
		var target := int(targets[i])
		b.pressed.connect(func() -> void: page_chosen.emit(target))
		_box.add_child(b)
		_rows.append(b)

## 由主逻辑按当前书页调用；这一组是否该出现在屏幕上
func set_left_page(left_page: int) -> void:
	visible = left_page == EndlessBook.left_page_number(page_number)

func _make_tint(c: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	return s
