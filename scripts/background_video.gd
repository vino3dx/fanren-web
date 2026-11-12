extends Node3D
## 背景视频：把视频贴在相机前方一块全屏四边形上当背景（相当于「远平面」背景）。
##
## 性能注意：视频是 CPU 软解的，分辨率直接决定每帧开销
## （4K 每次解码 50~140 ms，1080p 约 4~8 ms，720p 只要 1~2 ms）。素材是 1080p，
## 这里落地的 SubViewport 与素材同尺寸，避免二次缩放把 1080p 的清晰度白扔掉。
class_name BackgroundVideo

@export var camera: Camera3D = null
@export var video_path: String = "res://assets/video/bg.ogv"
@export var distance: float = 5.0
@export var resolution: Vector2i = Vector2i(1920, 1080)

var _quad: MeshInstance3D = null
var _mesh: QuadMesh = null
var _viewport: SubViewport = null
var _player: VideoStreamPlayer = null

func _ready() -> void:
	if not ResourceLoader.exists(video_path):
		push_warning("找不到背景视频: " + video_path)
		return
	var stream: VideoStream = load(video_path)
	if stream == null:
		return

	_viewport = SubViewport.new()
	_viewport.size = resolution
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.disable_3d = true
	add_child(_viewport)

	_player = VideoStreamPlayer.new()
	_player.stream = stream
	_player.expand = true
	_player.loop = true
	_player.size = Vector2(resolution)
	_viewport.add_child(_player)
	_player.play()

	_mesh = QuadMesh.new()
	_mesh.size = Vector2(1, 1)
	_quad = MeshInstance3D.new()
	_quad.name = "VideoQuad"
	_quad.mesh = _mesh
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _viewport.get_texture()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_quad.material_override = mat
	add_child(_quad)

var _last_size: Vector2 = Vector2.ZERO
var _last_cam_xf: Transform3D = Transform3D()

func _process(_delta: float) -> void:
	if _quad == null:
		return
	var cam: Camera3D = camera if camera else get_viewport().get_camera_3d()
	if cam == null:
		return
	# 用真实视口像素尺寸算宽高比：设计分辨率固定 3840x2160，
	# 窗口比例不是 16:9 时按设计尺寸算会把背景算小
	var vp: Viewport = get_viewport()
	var px := Vector2(vp.size)
	if px.x <= 0.0 or px.y <= 0.0:
		px = vp.get_visible_rect().size
	# 只在视口 / 相机变化时重算，避免每帧改写变换
	if px == _last_size and cam.global_transform == _last_cam_xf:
		return
	_last_size = px
	_last_cam_xf = cam.global_transform

	var aspect: float = px.x / maxf(px.y, 1.0)
	var h: float = 0.0
	if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		h = cam.size
	else:
		h = 2.0 * distance * tan(deg_to_rad(cam.fov * 0.5))
	var w: float = h * aspect

	# 注意：Basis.scaled() 是按行缩放，相机带旋转时会缩错轴
	# （曾经把高度缩到了相机的前后轴，背景就变成一条横带）。这里直接按列构造。
	var b: Basis = cam.global_transform.basis
	var origin: Vector3 = cam.global_transform.origin + b.z * (-distance)
	_quad.global_transform = Transform3D(Basis(b.x * w, b.y * h, b.z), origin)
