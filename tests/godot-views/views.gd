extends Node3D

var n_views := 8
var view_size := 512
var n_objects := 800
var warmup := 120
var measure := 300

var _frames: Array[float] = []
var _count := 0
var _movers: Array[MeshInstance3D] = []
var _cams: Array[Camera3D] = []

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"views": n_views = int(kv[1])
			"size": view_size = int(kv[1])
			"objects": n_objects = int(kv[1])
			"warmup": warmup = int(kv[1])
			"measure": measure = int(kv[1])

func _ready() -> void:
	_parse_args()

	var cam := Camera3D.new()
	cam.position = Vector3(0, 14, 34)
	cam.rotation = Vector3(deg_to_rad(-20), 0, 0)
	cam.far = 200.0
	add_child(cam)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	sun.shadow_enabled = false
	add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = Sky.new()
	e.sky.sky_material = ProceduralSkyMaterial.new()
	env.environment = e
	add_child(env)

	var meshes: Array[Mesh] = [BoxMesh.new(), SphereMesh.new(), TorusMesh.new(), CylinderMesh.new()]
	var side := int(ceil(sqrt(float(n_objects))))
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	for i in n_objects:
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[i % meshes.size()]
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(rng.randf(), rng.randf(), rng.randf())
		m.metallic = rng.randf()
		m.roughness = 0.1 + 0.8 * rng.randf()
		mi.material_override = m
		var x := float(i % side) - float(side) * 0.5
		var z := float(i / side) - float(side) * 0.5
		mi.position = Vector3(x * 1.6, rng.randf_range(0.0, 3.0), z * 1.6 - 10.0)
		mi.scale = Vector3.ONE * rng.randf_range(0.3, 0.7)
		add_child(mi)
		if i % 8 == 0:
			_movers.append(mi)

	# Chaque SubViewport possede sa propre texture cible : les passes sont
	# independantes les unes des autres, contrairement a un atlas d'ombres.
	var layer := CanvasLayer.new()
	add_child(layer)
	var grid := GridContainer.new()
	grid.columns = 4
	layer.add_child(grid)

	for i in n_views:
		var sv := SubViewport.new()
		sv.size = Vector2i(view_size, view_size)
		sv.own_world_3d = false
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		sv.positional_shadow_atlas_size = 0
		sv.msaa_3d = Viewport.MSAA_DISABLED
		add_child(sv)

		var c := Camera3D.new()
		c.far = 200.0
		sv.add_child(c)
		c.position = Vector3(cos(float(i)) * 26.0, 8.0 + float(i), sin(float(i)) * 26.0)
		c.look_at(Vector3(0, 3, -10), Vector3.UP)
		_cams.append(c)

		var tr := TextureRect.new()
		tr.texture = sv.get_texture()
		tr.custom_minimum_size = Vector2(160, 160)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		grid.add_child(tr)

	print("CONFIG vues=%d taille=%d objets=%d viewport=%s" % [
		n_views, view_size, n_objects, str(get_viewport().size)])

func _process(delta: float) -> void:
	var t := float(Time.get_ticks_msec()) * 0.001
	for i in _movers.size():
		_movers[i].rotation = Vector3(t * 0.6 + float(i), t * 0.9, 0.0)
	for i in _cams.size():
		var a := t * 0.2 + float(i) * 0.8
		_cams[i].position = Vector3(cos(a) * 26.0, 8.0 + float(i) * 0.5, sin(a) * 26.0)
		_cams[i].look_at(Vector3(0, 3, -10), Vector3.UP)

	_count += 1
	if _count <= warmup:
		return
	_frames.append(delta)
	if _frames.size() < measure:
		return

	_frames.sort()
	var med := _frames[_frames.size() / 2]
	var p95 := _frames[int(float(_frames.size()) * 0.95)]
	var best := _frames[0]
	print("DRAWCALLS %d PRIMITIVES %d" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
	print("RESULT frames=%d mediane=%.3f ms (%.1f img/s) p95=%.3f ms meilleure=%.3f ms" % [
		_frames.size(), med * 1000.0, 1.0 / med, p95 * 1000.0, best * 1000.0])
	get_tree().quit()
