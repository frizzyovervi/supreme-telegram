extends Node3D
# Lookdev stage: godot --path . res://tests/visual/lookdev.tscn -- --out=/tmp/look --set=fighters
var _out := "/tmp/look"
var _set := "bodies"

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
		if arg.begins_with("--set="): _set = arg.trim_prefix("--set=")
	DirAccess.make_dir_recursive_absolute(_out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.22, 0.27)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.95)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var back := DirectionalLight3D.new()
	back.rotation_degrees = Vector3(-20, -150, 0)
	back.light_energy = 0.7
	back.light_color = Color(0.7, 0.8, 1.0)
	add_child(back)
	Build.box(self, Vector3(30, 0.2, 30), Vector3(0, -0.1, 0), Build.mat(Color(0.3, 0.31, 0.34), 0.9))
	call(_set)

func _cam(pos: Vector3, target: Vector3, fov := 35.0) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = fov
	add_child(cam)
	cam.look_at_from_position(pos, target)
	cam.current = true
	return cam

func _shot(name: String) -> void:
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("saved ", name)

func _model(pos: Vector3, yaw: float, look: Dictionary, build := Vector3(0.5, 0.5, 0.5), colors := {}) -> CharacterModel:
	var m := CharacterModel.new()
	m.render_layers = 1
	m.look = look
	for k in colors:
		m.set(k, colors[k])
	m.set_physique(build.x, build.y, build.z)
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation_degrees.y = yaw
	add_child(holder)
	holder.add_child(m)
	return m

func bodies() -> void:
	var a := _model(Vector3(-1.2, 0, 0), 180, {}, Vector3(0.0, 0.0, 0.0))
	var b := _model(Vector3(0, 0, 0), 180, {}, Vector3(0.5, 0.5, 0.5))
	var c := _model(Vector3(1.2, 0, 0), 180, {"top": CharacterRig.Top.BARE}, Vector3(1, 1, 1), {"shirt_color": Color(0.96, 0.76, 0.62)})
	_cam(Vector3(0, 1.1, 4.6), Vector3(0, 0.95, 0))
	for m: CharacterModel in [a, b, c]:
		m.animate(0.016, 0.0, 0.0, 0.0, false)
	await _shot("bodies_front")
	for m: CharacterModel in [a, b, c]:
		(m.get_parent() as Node3D).rotation_degrees.y = 0
	await _shot("bodies_back")
	get_tree().quit()

func _fighter(pos: Vector3, yaw: float, setup: Callable, look := {}) -> CharacterModel:
	var m := _model(pos, yaw, look, Vector3(0.6, 0.6, 0.6), {"shirt_color": Color(0.96, 0.76, 0.62), "shoe_color": Color(0.96, 0.76, 0.62)})
	var anim := FightAnimator.new()
	m.fight_pose = anim.pose
	m.fight_blend = 1.0
	m.set_hand_gear(CharacterRig.Hands.GLOVES, Color(0.8, 0.12, 0.12))
	setup.call(anim)
	for i in 40:
		anim.update(0.016)
		m.animate(0.016, 0.0, 0.0, 0.0, false)
	return m

func poses() -> void:
	_fighter(Vector3(-3.0, 0, 0), 150, func(a: FightAnimator) -> void: pass)
	_fighter(Vector3(-1.5, 0, 0), 150, func(a: FightAnimator) -> void: a.set_strike(Strike.JAB, 0, 0.0, 1.0))
	_fighter(Vector3(0.0, 0, 0), 150, func(a: FightAnimator) -> void: a.set_strike(Strike.HOOK, 1, 1.0, 0.0))
	_fighter(Vector3(1.5, 0, 0), 150, func(a: FightAnimator) -> void: a.block = 1.0)
	_fighter(Vector3(3.0, 0, 0), 150, func(a: FightAnimator) -> void: a.set_strike(Strike.CROSS, 1, 0.0, 1.0))
	_cam(Vector3(0, 1.3, 7.2), Vector3(0, 1.0, 0), 38.0)
	await _shot("poses_fight")
	for c in get_children():
		if c is Node3D and c.get_child_count() > 0 and c.get_child(0) is CharacterModel:
			c.queue_free()
	_fighter(Vector3(-3.0, 0, 0), 150, func(a: FightAnimator) -> void: a.rocked = 1.0)
	_fighter(Vector3(-1.5, 0, 0), 150, func(a: FightAnimator) -> void: a.set_strike(Strike.KICK, 1, 0.0, 1.0))
	_fighter(Vector3(0.0, 0, 0), 150, func(a: FightAnimator) -> void: a.block_low = 1.0)
	_fighter(Vector3(1.5, 0, 0), 150, func(a: FightAnimator) -> void: a.victory = 1.0)
	_fighter(Vector3(3.3, 0, 0), 100, func(a: FightAnimator) -> void: a.knockdown = 1.0)
	await _shot("poses_fight2")
	get_tree().quit()

func workouts() -> void:
	var specs := [[CharacterModel.Pose.SQUAT, Vector2(0.0, 0.0)], [CharacterModel.Pose.DEADLIFT, Vector2(0.0, 0.0)], [CharacterModel.Pose.CURL, Vector2(1.0, 0.2)], [CharacterModel.Pose.STRETCH, Vector2(1.0, 1.0)], [CharacterModel.Pose.PUSHUP, Vector2(0.2, 0.0)], [CharacterModel.Pose.BENCH, Vector2(0.9, 0.0)]]
	for i in specs.size():
		var m := _model(Vector3(-3.6 + i * 1.5, 0, 0), 140, {}, Vector3(0.5, 0.5, 0.5))
		m.pose = specs[i][0]
		m.pose_progress = specs[i][1]
		if m.pose == CharacterModel.Pose.BENCH:
			m.pose_offset = Vector3(0, 0.5, 0)
		if m.pose == CharacterModel.Pose.PUSHUP:
			m.pose_offset = Vector3(0, 0.05, 0)
		for k in 60:
			m.animate(0.016, 0.0, 0.0, 0.0, false)
	_cam(Vector3(0, 1.5, 8.5), Vector3(0, 0.9, 0), 38.0)
	await _shot("poses_workout")
	get_tree().quit()
