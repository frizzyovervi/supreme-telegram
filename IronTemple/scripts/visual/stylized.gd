class_name Stylized
extends RefCounted
## The shared look of the game: procedural noise maps for skin, fabric, leather, metal and
## masonry, the StandardMaterial3D factories built on them and the conversion of imported
## materials to the stylized PBR shader. Everything is cached, so repeated surfaces batch.

enum Surface { PLAIN, SKIN, FABRIC, LEATHER, METAL, RUBBER, MASONRY }

const SHADER_PATH := "res://shaders/stylized_pbr.gdshader"
## Rim light every stylized surface gets: a soft, slightly warm edge where light grazes.
const RIM := 0.3
const RIM_TINT := 0.4

# Noise recipe per surface: type, frequency, octaves, bump strength, texture size, tiling per
# metre, normal depth, and the roughness band the noise is remapped into.
const _RECIPES := {
	Surface.PLAIN: {"type": FastNoiseLite.TYPE_SIMPLEX_SMOOTH, "freq": 0.045, "octaves": 3, "bump": 3.0, "size": Vector2i(256, 256), "tiling": 0.9, "depth": 0.3, "band": Vector2(0.86, 1.0)},
	Surface.SKIN: {"type": FastNoiseLite.TYPE_CELLULAR, "freq": 0.11, "octaves": 2, "bump": 2.2, "size": Vector2i(256, 256), "tiling": 9.0, "depth": 0.35, "band": Vector2(0.78, 1.0)},
	Surface.FABRIC: {"type": FastNoiseLite.TYPE_VALUE, "freq": 0.42, "octaves": 2, "bump": 5.0, "size": Vector2i(256, 256), "tiling": 7.0, "depth": 0.55, "band": Vector2(0.88, 1.0)},
	Surface.LEATHER: {"type": FastNoiseLite.TYPE_CELLULAR, "freq": 0.06, "octaves": 3, "bump": 6.0, "size": Vector2i(256, 256), "tiling": 6.0, "depth": 0.7, "band": Vector2(0.62, 1.0)},
	# A wide, short texture stretches the noise into brushed streaks.
	Surface.METAL: {"type": FastNoiseLite.TYPE_VALUE, "freq": 0.2, "octaves": 2, "bump": 3.0, "size": Vector2i(512, 48), "tiling": 2.0, "depth": 0.3, "band": Vector2(0.6, 1.0)},
	Surface.RUBBER: {"type": FastNoiseLite.TYPE_VALUE, "freq": 0.3, "octaves": 3, "bump": 4.0, "size": Vector2i(256, 256), "tiling": 4.0, "depth": 0.6, "band": Vector2(0.85, 1.0)},
	Surface.MASONRY: {"type": FastNoiseLite.TYPE_SIMPLEX_SMOOTH, "freq": 0.03, "octaves": 5, "bump": 5.0, "size": Vector2i(512, 512), "tiling": 0.45, "depth": 0.55, "band": Vector2(0.8, 1.0)},
}

static var _normals: Dictionary = {}
static var _roughness: Dictionary = {}
static var _heights: Dictionary = {}
static var _materials: Dictionary = {}
static var _converted: Dictionary = {}
static var _shaders: Dictionary = {}


## Tangent-space normal map of a surface kind, generated once on a worker thread.
static func normal_map(surface: Surface) -> NoiseTexture2D:
	if not _normals.has(surface):
		var texture := _noise_texture(surface)
		texture.as_normal_map = true
		texture.bump_strength = _RECIPES[surface]["bump"]
		_normals[surface] = texture
	return _normals[surface]


## Roughness map of a surface kind: the same noise squeezed into a narrow bright band, so it
## varies the gloss without changing its level much.
static func roughness_map(surface: Surface) -> NoiseTexture2D:
	if not _roughness.has(surface):
		var texture := _noise_texture(surface)
		var band: Vector2 = _RECIPES[surface]["band"]
		var ramp := Gradient.new()
		ramp.set_color(0, Color(band.x, band.x, band.x))
		ramp.set_color(1, Color(band.y, band.y, band.y))
		texture.color_ramp = ramp
		_roughness[surface] = texture
	return _roughness[surface]


## Greyscale height of a surface kind, for shaders that derive their own bump.
static func height_map(surface: Surface) -> NoiseTexture2D:
	if not _heights.has(surface):
		_heights[surface] = _noise_texture(surface)
	return _heights[surface]


## StandardMaterial3D with the noise normal and roughness maps of `surface` (triplanar, so it
## needs no UVs) and the shared rim light. Translucent colours stay plain.
static func standard(color: Color, roughness: float, metallic: float, surface: Surface) -> StandardMaterial3D:
	var key := "%s/%.2f/%.2f/%d" % [color.to_html(), roughness, metallic, surface]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	else:
		var recipe: Dictionary = _RECIPES[surface]
		material.uv1_triplanar = true
		material.uv1_scale = Vector3.ONE * (recipe["tiling"] as float)
		material.normal_enabled = true
		material.normal_texture = normal_map(surface)
		material.normal_scale = recipe["depth"]
		material.roughness_texture = roughness_map(surface)
		material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		material.rim_enabled = true
		material.rim = RIM * (0.5 if metallic > 0.5 else 1.0)
		material.rim_tint = RIM_TINT
		if metallic > 0.5:
			material.metallic_specular = 0.6
	_materials[key] = material
	return material


## Picks the surface kind a flat colour most likely stands for from its gloss and metalness.
static func guess(roughness: float, metallic: float) -> Surface:
	if metallic >= 0.5:
		return Surface.METAL
	if roughness >= 0.88:
		return Surface.MASONRY
	if roughness >= 0.72:
		return Surface.FABRIC
	if roughness <= 0.45:
		return Surface.RUBBER
	return Surface.PLAIN


static func skin(color: Color) -> StandardMaterial3D:
	var material := standard(color, 0.62, 0.0, Surface.SKIN)
	material.subsurf_scatter_enabled = false
	return material


static func fabric(color: Color) -> StandardMaterial3D:
	return standard(color, 0.86, 0.0, Surface.FABRIC)


static func leather(color: Color, roughness: float = 0.48) -> StandardMaterial3D:
	return standard(color, roughness, 0.0, Surface.LEATHER)


static func metal(color: Color, roughness: float = 0.32) -> StandardMaterial3D:
	return standard(color, roughness, 1.0, Surface.METAL)


static func rubber(color: Color) -> StandardMaterial3D:
	return standard(color, 0.8, 0.0, Surface.RUBBER)


## The stylized PBR shader, optionally without back-face culling.
static func shader(double_sided: bool = false) -> Shader:
	if not _shaders.has(double_sided):
		var base: Shader = load(SHADER_PATH)
		if double_sided:
			var copy := Shader.new()
			copy.code = base.code.replace("cull_back", "cull_disabled")
			_shaders[double_sided] = copy
		else:
			_shaders[double_sided] = base
	return _shaders[double_sided]


## Turns an imported material into the stylized PBR pass, keeping its colour, textures and
## emission. Alpha-blended materials (glass) and anything that is not a BaseMaterial3D are
## returned unchanged. `tint` multiplies the albedo.
static func convert(source: Material, tint: Color = Color.WHITE, surface: Surface = Surface.PLAIN) -> Material:
	var base := source as BaseMaterial3D
	if base == null or base.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
		return source
	var key := "%d/%s/%d" % [source.get_instance_id(), tint.to_html(), surface]
	if _converted.has(key):
		return _converted[key]
	var material := ShaderMaterial.new()
	material.shader = shader(base.cull_mode == BaseMaterial3D.CULL_DISABLED)
	material.resource_name = source.resource_name
	material.set_shader_parameter("albedo", base.albedo_color)
	material.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b))
	if base.albedo_texture != null:
		material.set_shader_parameter("albedo_tex", base.albedo_texture)
	material.set_shader_parameter("roughness", base.roughness)
	material.set_shader_parameter("metallic", base.metallic)
	material.set_shader_parameter("specular", base.metallic_specular)
	if base.roughness_texture != null and base.roughness_texture == base.metallic_texture:
		material.set_shader_parameter("orm_tex", base.roughness_texture)
		material.set_shader_parameter("use_orm", true)
	if base.normal_enabled and base.normal_texture != null:
		material.set_shader_parameter("normal_tex", base.normal_texture)
		material.set_shader_parameter("normal_scale", base.normal_scale)
		material.set_shader_parameter("use_normal", true)
	if base.emission_enabled:
		material.set_shader_parameter("emission", base.emission)
		material.set_shader_parameter("emission_energy", base.emission_energy_multiplier)
		if base.emission_texture != null:
			material.set_shader_parameter("emission_tex", base.emission_texture)
		else:
			material.set_shader_parameter("emission_tex", _white())
	material.set_shader_parameter("use_vertex_color", base.vertex_color_use_as_albedo)
	if base.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR or base.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH:
		material.set_shader_parameter("alpha_scissor", base.alpha_scissor_threshold if base.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else 0.5)
	var recipe: Dictionary = _RECIPES[surface]
	material.set_shader_parameter("detail_height", height_map(surface))
	material.set_shader_parameter("detail_tiling", recipe["tiling"])
	material.set_shader_parameter("detail_bump", recipe["depth"])
	material.set_shader_parameter("rim_strength", RIM * (0.5 if base.metallic > 0.5 else 1.0))
	material.set_shader_parameter("rim_tint", RIM_TINT)
	_converted[key] = material
	return material


static func _noise_texture(surface: Surface) -> NoiseTexture2D:
	var recipe: Dictionary = _RECIPES[surface]
	var noise := FastNoiseLite.new()
	noise.noise_type = recipe["type"]
	noise.frequency = recipe["freq"]
	noise.fractal_octaves = recipe["octaves"]
	noise.seed = 1337 + int(surface) * 17
	var texture := NoiseTexture2D.new()
	var size: Vector2i = recipe["size"]
	texture.width = size.x
	texture.height = size.y
	texture.seamless = true
	texture.generate_mipmaps = true
	texture.noise = noise
	return texture


static func _white() -> Texture2D:
	if not _heights.has("white"):
		var image := Image.create(4, 4, false, Image.FORMAT_RGB8)
		image.fill(Color.WHITE)
		_heights["white"] = ImageTexture.create_from_image(image)
	return _heights["white"]
