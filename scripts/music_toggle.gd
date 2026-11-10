extends CanvasLayer
class_name MusicToggle
## 左下角的音乐开关：图标一直缓慢旋转，点击静音 / 解除静音。
##
## 组件自带 AudioStreamPlayer，拖进场景就同时拥有「背景音乐 + 开关按钮」，
## 不需要在场景里另放播放器。静音走独立的 BGM 总线，不碰主音量，
## 以后再加音效也不会被一起静掉。
##
## 位置/大小在 music_button.tscn 里改（Root 下 Spin / Hit 的 offset_*），
## 图标与旋转速度在检视面板里改。

## 图标是否继续旋转（想让静音时停下就关掉）
@export var spin_always: bool = true
## 旋转速度（度/秒）
@export var spin_speed: float = 22.0
## 正常 / 静音时的图标透明度
@export_range(0.0, 1.0, 0.01) var active_alpha: float = 0.92
@export_range(0.0, 1.0, 0.01) var muted_alpha: float = 0.45
## 音量
@export var volume_db: float = -6.0
## 静音用的总线名（不存在会自动创建）
@export var bus_name: String = "BGM"
## 启动时就是静音状态
@export var start_muted: bool = false

@export_group("图标")
@export var icon_on: Texture2D = null
@export var icon_off: Texture2D = null

@onready var _spin: Control = $Root/Spin
@onready var _icon: TextureRect = $Root/Spin/Icon
@onready var _hit: Button = $Root/Hit
@onready var _player: AudioStreamPlayer = $Player

var _muted: bool = false
var _bus_index: int = -1

func _ready() -> void:
	_bus_index = _ensure_bus()
	_setup_audio()
	_hit.pressed.connect(toggle_mute)
	_muted = start_muted
	_apply_state()

func _process(delta: float) -> void:
	# 按下时轻微缩小，作为触摸/点击反馈（flat Button 本身不画按下态）
	var target := 0.94 if _hit.button_pressed else 1.0
	_spin.scale = _spin.scale.lerp(Vector2(target, target), minf(1.0, delta * 18.0))
	if not spin_always and _muted:
		return
	_spin.rotation = fmod(_spin.rotation + deg_to_rad(spin_speed) * delta, TAU)

## 关窗 / 退出前先放开音频，避免引擎关闭时报 "resources still in use"
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		_stop_audio()

func _stop_audio() -> void:
	if is_instance_valid(_player):
		_player.stop()
		_player.stream = null

func is_muted() -> bool:
	return _muted

func toggle_mute() -> void:
	set_muted(not _muted)

func set_muted(value: bool) -> void:
	_muted = value
	_apply_state()

func _setup_audio() -> void:
	_player.bus = bus_name
	_player.volume_db = volume_db
	var s := _player.stream
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	elif s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	if s != null and not _player.playing:
		_player.play()

func _apply_state() -> void:
	if _bus_index >= 0:
		AudioServer.set_bus_mute(_bus_index, _muted)
	if _icon != null:
		var tex := icon_off if _muted else icon_on
		if tex != null:
			_icon.texture = tex
		_icon.modulate.a = muted_alpha if _muted else active_alpha
	if _hit != null:
		_hit.tooltip_text = "解除静音" if _muted else "静音"

## 没有就建一条独立总线，返回索引
func _ensure_bus() -> int:
	if bus_name.is_empty():
		return -1
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		return idx
	AudioServer.add_bus()
	idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, &"Master")
	return idx
