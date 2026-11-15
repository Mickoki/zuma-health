extends ColorRect

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader_material := ShaderMaterial.new()
	shader_material.shader = preload("res://addons/zuma_minigames/ui/orbit.gdshader")
	material = shader_material
