extends Node
## 外部图片加载管理器（对应 Unity ImageLoaderManager.cs）
## Unity 从 StreamingAssets/images 读取 PNG，这里读取 assets/pages（可导出后替换）。
##
## 注意：Unity 版是启动时把整本书一次性读进内存。Godot 侧如果照搬，
## 86 张 1920x2160 的页面会占掉约 1.4 GB 显存、启动卡 6 秒，而且真正显示时
## 是由 PageCache 按需加载的，这里预载的材质没有任何地方使用。
## 因此默认关闭全量预载（preload_all_pages = false），保留接口供需要时打开。

class_name ImageLoaderManager

static var instance: ImageLoaderManager = null

const PAGE_DIR := "res://assets/pages"
const MAX_PAGE_PROBE := 400

@export var page_material_template: Material = null
## 启动时把整本书读进内存。大量页面时不要开（见文件头说明）。
@export var preload_all_pages: bool = false

var loaded_materials: Dictionary = {}

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
		return
	if preload_all_pages:
		load_images_from_streaming_assets()

func load_images_from_streaming_assets() -> void:
	loaded_materials.clear()
	for i in range(1, MAX_PAGE_PROBE + 1):
		# 支持 png/jpg/jpeg/webp/bmp/tga/svg（PageCache 里统一维护格式列表）
		var path := PageCache.find_image(PAGE_DIR, i)
		if path == "":
			continue
		var tex := load(path) as Texture2D
		if tex == null:
			continue
		var mat: Material = null
		if page_material_template:
			mat = page_material_template.duplicate()
		else:
			var std := StandardMaterial3D.new()
			std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat = std
		if mat is BaseMaterial3D:
			(mat as BaseMaterial3D).albedo_texture = tex
		loaded_materials[i] = mat
	print("外部图片加载完成，共加载 ", loaded_materials.size(), " 张图片")

func get_page_material(page_index: int) -> Material:
	return loaded_materials.get(page_index, null)

func is_material_loaded(page_index: int) -> bool:
	return loaded_materials.has(page_index)

func get_loaded_page_count() -> int:
	return loaded_materials.size()

func get_all_loaded_materials() -> Dictionary:
	return loaded_materials.duplicate()
