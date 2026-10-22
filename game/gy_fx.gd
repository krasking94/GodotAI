extends RefCounted

## Эффекты частиц для «Кладбища»: светлячки, падающие листья и искры от попаданий.
## Всё на CPUParticles3D (работает и в Forward+, и в режиме совместимости, и без окна),
## картинки частиц рисуются кодом: мягкая точка и овальный листок из GradientTexture2D.

static var _dot_texture: GradientTexture2D
static var _leaf_texture: GradientTexture2D
## На телефонах частиц вдвое меньше, чтобы не подвисало.
static func budget() -> float:
	return 0.5 if OS.has_feature("mobile") else 1.0


static var _spark_materials := {}  # цвет → материал искр, чтобы не плодить материалы на каждый всплеск
static var _spark_mesh: QuadMesh


## Мягкая круглая точка: белая в центре, прозрачная к краю.
static func dot_texture() -> GradientTexture2D:
	if _dot_texture == null:
		_dot_texture = _radial_texture([0.0, 0.35, 1.0], [Color.WHITE, Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
	return _dot_texture


## Листок: сплошной овал с чуть размытым краем (сам овал получается из вытянутого квадратика).
static func leaf_texture() -> GradientTexture2D:
	if _leaf_texture == null:
		_leaf_texture = _radial_texture([0.0, 0.78, 0.92], [Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	return _leaf_texture


static func _radial_texture(offsets: Array, colors: Array) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(offsets)
	gradient.colors = PackedColorArray(colors)
	var texture := GradientTexture2D.new()
	texture.width = 32
	texture.height = 32
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.gradient = gradient
	return texture


## Светящийся материал для точек: без освещения, складывается со светом сцены (ADD), яркость через альфу.
static func _glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_color = color
	material.albedo_texture = dot_texture()
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


## Светлячки: десятки точек в коробке вокруг героя, медленно плывут и мигают (альфа по кривой жизни).
static func fireflies() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Fireflies"
	p.amount = int(45 * budget())
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.randomness = 0.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(17, 1.0, 13)
	p.direction = Vector3(1, 0, 0)
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.25
	p.initial_velocity_max = 0.7
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	var blink := Gradient.new()
	blink.offsets = PackedFloat32Array([0.0, 0.15, 0.3, 0.5, 0.65, 0.85, 1.0])
	blink.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.15), Color(1, 1, 1, 1),
		Color(1, 1, 1, 0.1), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
	p.color_ramp = blink
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.18, 0.18)
	p.mesh = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.material_override = _glow_material(Color("#d4ff6a"), 4.0)
	return p


## Листья: падают с высоты над героем, кружатся, сносятся ветром; цвет у каждого свой (осенняя палитра).
static func leaves() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Leaves"
	p.amount = int(24 * budget())
	p.lifetime = 8.0
	p.preprocess = 8.0
	p.randomness = 0.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(16, 0.5, 12)
	p.direction = Vector3(0.5, -1.0, 0.3)
	p.spread = 25.0
	p.gravity = Vector3(0, -0.1, 0)
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 0.8
	p.angular_velocity_min = -150.0
	p.angular_velocity_max = 150.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	var palette := Gradient.new()
	palette.offsets = PackedFloat32Array([0.0, 0.3, 0.6, 1.0])
	palette.colors = PackedColorArray([Color("#c4692a"), Color("#d9a441"), Color("#8a5a2b"), Color("#b23b1e")])
	p.color_initial_ramp = palette
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.8, 1.0])
	fade.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	p.color_ramp = fade
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.26, 0.15)
	p.mesh = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # тени от листьев с высоты выглядят как пятна
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = leaf_texture()
	material.roughness = 0.9
	p.material_override = material
	return p


## Искры: один всплеск точек, разлетаются во все стороны, падают, гаснут; сами удаляются.
## По умолчанию — горячие искры попадания; при гибели врага зовётся с его цветом и большим числом точек.
static func sparks(color: Color = Color("#ffd27a"), amount: int = 8, size: float = 1.0) -> CPUParticles3D:
	if _spark_mesh == null:
		_spark_mesh = QuadMesh.new()
		_spark_mesh.size = Vector2(0.14, 0.14)
	var key := color.to_html(false)
	if not _spark_materials.has(key):
		_spark_materials[key] = _glow_material(color, 4.0)
	var p := CPUParticles3D.new()
	p.name = "Sparks"
	p.amount = maxi(int(amount * budget()), 4)
	p.lifetime = 0.45 + 0.15 * (size - 1.0)
	p.one_shot = true
	p.explosiveness = 1.0
	p.randomness = 0.4
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.12 * size
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.gravity = Vector3(0, -9.0, 0)
	p.initial_velocity_min = 2.5 * size
	p.initial_velocity_max = 6.0 * size
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.6 * size
	p.scale_amount_max = 1.1 * size
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	fade.colors = PackedColorArray([Color.WHITE, color, Color(color.r, color.g, color.b, 0.0)])
	p.color_ramp = fade
	p.mesh = _spark_mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.material_override = _spark_materials[key]
	p.finished.connect(p.queue_free)
	p.emitting = true
	return p
