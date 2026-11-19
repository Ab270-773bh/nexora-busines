extends Node3D

# WILD HUNT ONLINE - Integrated playable prototype
const SAVE_PATH = "user://wild_hunt_save.json"
var player: CharacterBody3D
var camera: Camera3D
var hud: CanvasLayer
var info_label: Label
var coins := 250
var ammo := 12
var deer_count := 0
var mission_progress := 0
var dog_level := 1
var dog_owned := true
var camp_level := 1
var selected_weapon := "Hunting Rifle"
var animals: Array[Node3D] = []
var birds: Array[Node3D] = []
var move_flags := {"forward": false, "back": false, "left": false, "right": false}
var yaw := 0.0
var pitch := -0.22
var world_time := 0.0
var message_timer := 0.0
var current_message := "مرحباً بك في البرية! اصطد واجمع العملات."
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	_load_game()
	_build_world()
	_build_player()
	_build_wildlife()
	_build_hud()
	_update_hud()

func _process(delta: float) -> void:
	world_time += delta
	message_timer = maxf(0.0, message_timer - delta)
	if message_timer <= 0.0:
		current_message = "استكشف الغابة وابحث عن الحيوانات."
	_update_hud()
	for bird in birds:
		if is_instance_valid(bird):
			bird.position.x += sin(world_time * 0.7 + bird.position.z) * delta * 0.9
			bird.position.z += cos(world_time * 0.6 + bird.position.x) * delta * 0.45
			bird.position.y = 7.0 + sin(world_time * 2.0 + bird.position.x) * 0.45

func _physics_process(delta: float) -> void:
	if player == null:
		return
	var input_dir := Vector2.ZERO
	if move_flags["forward"]: input_dir.y -= 1.0
	if move_flags["back"]: input_dir.y += 1.0
	if move_flags["left"]: input_dir.x -= 1.0
	if move_flags["right"]: input_dir.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): input_dir.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): input_dir.x += 1.0
	input_dir = input_dir.normalized()
	var forward := -player.global_transform.basis.z
	var right := player.global_transform.basis.x
	var direction := (right * input_dir.x + forward * -input_dir.y).normalized()
	player.velocity.x = direction.x * 5.2
	player.velocity.z = direction.z * 5.2
	player.velocity.y -= 18.0 * delta
	player.move_and_slide()
	if direction.length() > 0.1:
		player.rotation.y = lerp_angle(player.rotation.y, atan2(-direction.x, -direction.z), delta * 8.0)

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.79, 0.83)
	environment.ambient_light_energy = 0.8
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = environment
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(180, 180)
	ground.mesh = plane
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.19, 0.34, 0.17)
	grass.roughness = 1.0
	ground.material_override = grass
	ground.position.y = -0.12
	add_child(ground)

	var water := MeshInstance3D.new()
	var water_mesh := CylinderMesh.new()
	water_mesh.top_radius = 11.0
	water_mesh.bottom_radius = 11.0
	water_mesh.height = 0.18
	water.mesh = water_mesh
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.08, 0.28, 0.38, 0.88)
	water_mat.metallic = 0.15
	water_mat.roughness = 0.22
	water.material_override = water_mat
	water.position = Vector3(25, 0.0, -20)
	add_child(water)

	for i in range(95):
		var x := rng.randf_range(-78, 78)
		var z := rng.randf_range(-78, 78)
		if Vector2(x - 25, z + 20).length() < 14: continue
		_make_tree(Vector3(x, 0, z), rng.randf_range(0.75, 1.35))

	for i in range(22):
		var rock := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = rng.randf_range(0.35, 1.0)
		mesh.height = mesh.radius * 1.2
		rock.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.28, 0.30, 0.27)
		rock.material_override = mat
		rock.position = Vector3(rng.randf_range(-70,70), 0.15, rng.randf_range(-70,70))
		rock.scale = Vector3(1.4, 0.65, 1.0)
		add_child(rock)

	_make_camp()

func _make_tree(pos: Vector3, size: float) -> void:
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18 * size
	trunk_mesh.bottom_radius = 0.28 * size
	trunk_mesh.height = 2.6 * size
	trunk.mesh = trunk_mesh
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.22, 0.13, 0.07)
	trunk.material_override = bark
	trunk.position = pos + Vector3(0, 1.3 * size, 0)
	add_child(trunk)
	var crown := MeshInstance3D.new()
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 1.25 * size
	crown_mesh.height = 2.2 * size
	crown.mesh = crown_mesh
	var leaves := StandardMaterial3D.new()
	leaves.albedo_color = Color(0.08 + rng.randf() * 0.06, 0.22 + rng.randf() * 0.08, 0.09)
	crown.material_override = leaves
	crown.position = pos + Vector3(0, 3.1 * size, 0)
	add_child(crown)

func _make_camp() -> void:
	var tent := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = Vector3(4, 2.5, 3)
	tent.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.31, 0.14)
	tent.material_override = mat
	tent.position = Vector3(0, 1.2, 8)
	add_child(tent)
	var fire := MeshInstance3D.new()
	var fire_mesh := SphereMesh.new()
	fire_mesh.radius = 0.45
	fire.mesh = fire_mesh
	var fire_mat := StandardMaterial3D.new()
	fire_mat.albedo_color = Color(1.0, 0.32, 0.04)
	fire.material_override = fire_mat
	fire.position = Vector3(0, 0.35, 5.3)
	add_child(fire)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.0, 5.3)
	light.light_color = Color(1.0, 0.42, 0.12)
	light.omni_range = 9
	light.light_energy = 1.4
	add_child(light)

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.position = Vector3(0, 1.0, 0)
	add_child(player)
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.42
	capsule.height = 1.7
	body.mesh = capsule
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.16, 0.24, 0.13)
	body.material_override = body_mat
	body.position.y = 0.85
	player.add_child(body)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.25
	head.mesh = head_mesh
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.66, 0.48, 0.34)
	head.material_override = skin
	head.position = Vector3(0, 1.78, 0)
	player.add_child(head)
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 1.7
	collider.shape = shape
	collider.position.y = 0.85
	player.add_child(collider)

	camera = Camera3D.new()
	camera.position = Vector3(0, 3.1, 6.4)
	camera.rotation_degrees.x = -18
	camera.current = true
	player.add_child(camera)

func _build_wildlife() -> void:
	for i in range(7):
		var deer := _make_deer()
		deer.position = Vector3(rng.randf_range(-35,35), 0, rng.randf_range(-35,35))
		animals.append(deer)
	for i in range(5):
		var bird := MeshInstance3D.new()
		var bird_mesh := SphereMesh.new()
		bird_mesh.radius = 0.16
		bird.mesh = bird_mesh
		var bird_mat := StandardMaterial3D.new()
		bird_mat.albedo_color = Color(0.13, 0.12, 0.1)
		bird.material_override = bird_mat
		bird.position = Vector3(rng.randf_range(-35,35), 7, rng.randf_range(-35,35))
		add_child(bird)
		birds.append(bird)

func _make_deer() -> Node3D:
	var deer := Node3D.new()
	deer.name = "Deer"
	add_child(deer)
	var torso := MeshInstance3D.new()
	var torso_mesh := SphereMesh.new()
	torso_mesh.radius = 0.62
	torso_mesh.height = 0.95
	torso.mesh = torso_mesh
	var brown := StandardMaterial3D.new()
	brown.albedo_color = Color(0.43, 0.25, 0.12)
	torso.material_override = brown
	torso.position.y = 1.05
	torso.scale = Vector3(1.25, 0.8, 0.7)
	deer.add_child(torso)
	var neck := MeshInstance3D.new()
	var neck_mesh := CapsuleMesh.new()
	neck_mesh.radius = 0.18
	neck_mesh.height = 0.9
	neck.mesh = neck_mesh
	neck.material_override = brown
	neck.position = Vector3(0, 1.48, -0.43)
	neck.rotation.x = -0.4
	deer.add_child(neck)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.23
	head.mesh = head_mesh
	head.material_override = brown
	head.position = Vector3(0, 1.78, -0.72)
	deer.add_child(head)
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var leg_mesh := CylinderMesh.new()
		leg_mesh.top_radius = 0.055
		leg_mesh.bottom_radius = 0.07
		leg_mesh.height = 0.8
		leg.mesh = leg_mesh
		leg.material_override = brown
		leg.position = Vector3(side * 0.28, 0.42, -0.18)
		deer.add_child(leg)
		var leg2 := leg.duplicate() as MeshInstance3D
		leg2.position.z = 0.35
		deer.add_child(leg2)
	return deer

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var panel := PanelContainer.new()
	panel.position = Vector2(14, 14)
	panel.custom_minimum_size = Vector2(300, 112)
	hud.add_child(panel)
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(info_label)
	var help := Label.new()
	help.text = "WASD / الأسهم للحركة • اسحب الشاشة لتدوير الكاميرا"
	help.add_theme_font_size_override("font_size", 13)
	vbox.add_child(help)

	var actions := HBoxContainer.new()
	actions.position = Vector2(14, 145)
	hud.add_child(actions)
	_add_action_button(actions, "المتجر", _open_shop)
	_add_action_button(actions, "الكلب", _train_dog)
	_add_action_button(actions, "المخيم", _upgrade_camp)
	_add_action_button(actions, "مهمة", _mission)

	var dpad := GridContainer.new()
	dpad.columns = 3
	dpad.position = Vector2(22, 510)
	dpad.add_theme_constant_override("h_separation", 5)
	dpad.add_theme_constant_override("v_separation", 5)
	hud.add_child(dpad)
	_add_move_button(dpad, "", "")
	_add_move_button(dpad, "▲", "forward")
	_add_move_button(dpad, "", "")
	_add_move_button(dpad, "◀", "left")
	_add_move_button(dpad, "▼", "back")
	_add_move_button(dpad, "▶", "right")

	var shoot := Button.new()
	shoot.text = "إطلاق"
	shoot.position = Vector2(1080, 575)
	shoot.custom_minimum_size = Vector2(150, 72)
	shoot.add_theme_font_size_override("font_size", 22)
	shoot.pressed.connect(_shoot)
	hud.add_child(shoot)

	var whistle := Button.new()
	whistle.text = "صفارة"
	whistle.position = Vector2(1080, 490)
	whistle.custom_minimum_size = Vector2(150, 60)
	whistle.pressed.connect(_call_dog)
	hud.add_child(whistle)

	var look := Label.new()
	look.text = "اسحب هنا لتحريك الكاميرا"
	look.position = Vector2(850, 20)
	look.add_theme_font_size_override("font_size", 14)
	hud.add_child(look)

func _add_action_button(parent: Node, label_text: String, callback: Callable) -> void:
	var b := Button.new()
	b.text = label_text
	b.custom_minimum_size = Vector2(112, 48)
	b.pressed.connect(callback)
	parent.add_child(b)

func _add_move_button(parent: Node, label_text: String, direction: String) -> void:
	var b := Button.new()
	b.text = label_text
	b.custom_minimum_size = Vector2(58, 54)
	if direction == "":
		b.disabled = true
	else:
		b.button_down.connect(func(): move_flags[direction] = true)
		b.button_up.connect(func(): move_flags[direction] = false)
	parent.add_child(b)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		if event.position.x > 500:
			yaw -= event.relative.x * 0.004
			pitch = clampf(pitch - event.relative.y * 0.003, -0.8, 0.15)
			player.rotation.y = yaw
			camera.rotation.x = pitch
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * 0.004
		pitch = clampf(pitch - event.relative.y * 0.003, -0.8, 0.15)
		player.rotation.y = yaw
		camera.rotation.x = pitch

func _shoot() -> void:
	if ammo <= 0:
		_show_message("الذخيرة خلصت! اشترِ ذخيرة من المتجر.")
		return
	ammo -= 1
	var target: Node3D = null
	var nearest := 100000.0
	for animal in animals:
		if not is_instance_valid(animal): continue
		var d := player.global_position.distance_to(animal.global_position)
		if d < nearest:
			nearest = d
			target = animal
	if target != null and nearest < 24.0:
		animals.erase(target)
		target.queue_free()
		coins += 55
		deer_count += 1
		mission_progress += 1
		_show_message("صيد ناجح! +55 عملة صيد")
	else:
		_show_message("لم تصب هدفاً. اقترب أكثر من الحيوان.")
	_save_game()

func _open_shop() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "متجر الصياد"
	dialog.dialog_text = "ذخيرة 5 طلقات: 40 عملة\nترقية البندقية: 180 عملة\nكلب صيد إضافي: 220 عملة"
	dialog.add_cancel_button("إغلاق")
	dialog.confirmed.connect(func():
		if coins >= 40:
			coins -= 40
			ammo += 5
			_show_message("تم شراء 5 طلقات.")
			_save_game()
		else:
			_show_message("عملاتك لا تكفي.")
	)
	hud.add_child(dialog)
	dialog.popup_centered()

func _train_dog() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "تدريب كلب الصيد"
	dialog.dialog_text = "تطوير مهارة الكلب للمستوى التالي مقابل 100 عملة؟"
	dialog.confirmed.connect(func():
		if coins >= 100:
			coins -= 100
			dog_level += 1
			_show_message("صار مستوى كلبك " + str(dog_level) + "!")
			_save_game()
		else:
			_show_message("تحتاج 100 عملة لتدريب الكلب.")
	)
	hud.add_child(dialog)
	dialog.popup_centered()

func _upgrade_camp() -> void:
	if coins >= 150:
		coins -= 150
		camp_level += 1
		_show_message("تم تطوير المخيم إلى المستوى " + str(camp_level))
		_save_game()
	else:
		_show_message("تطوير المخيم يحتاج 150 عملة.")

func _mission() -> void:
	var reward := 100
	if mission_progress >= 2:
		coins += reward
		mission_progress = 0
		_show_message("أنجزت المهمة! مكافأة 100 عملة.")
		_save_game()
	else:
		_show_message("المهمة الحالية: اصطد حيوانين. التقدم: " + str(mission_progress) + "/2")

func _call_dog() -> void:
	_show_message("كلبك بدأ يتبعك! مستوى التدريب: " + str(dog_level))
	# Visual companion marker near the hunter
	var marker := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.28
	marker.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.48, 0.28, 0.12)
	marker.material_override = mat
	marker.position = player.position + Vector3(1.0, 0.3, 1.0)
	add_child(marker)

func _show_message(msg: String) -> void:
	current_message = msg
	message_timer = 4.0
	_update_hud()

func _update_hud() -> void:
	if info_label:
		info_label.text = "WILD HUNT ONLINE\nHUNT COINS: %d   الذخيرة: %d\nالصيد: %d   الكلب: Lv.%d   المخيم: Lv.%d\n%s" % [coins, ammo, deer_count, dog_level, camp_level, current_message]

func _save_game() -> void:
	var data := {"coins": coins, "ammo": ammo, "deer_count": deer_count, "mission_progress": mission_progress, "dog_level": dog_level, "camp_level": camp_level}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))

func _load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null: return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		coins = int(parsed.get("coins", coins))
		ammo = int(parsed.get("ammo", ammo))
		deer_count = int(parsed.get("deer_count", deer_count))
		mission_progress = int(parsed.get("mission_progress", mission_progress))
		dog_level = int(parsed.get("dog_level", dog_level))
		camp_level = int(parsed.get("camp_level", camp_level))
