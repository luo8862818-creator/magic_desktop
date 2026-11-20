extends Node3D

const DEFAULT_PORT := 49261
const WINDOW_WIDTH := 640
const WINDOW_HEIGHT := 520

var udp := PacketPeerUDP.new()
var cake_root: Node3D
var birthday_label: Label3D
var flame_nodes: Array[MeshInstance3D] = []
var flame_lights: Array[OmniLight3D] = []
var rotation_speed_degrees := 24.0
var flame_clock := 0.0
var passthrough_enabled := false

var dragging := false
var drag_moved := false
var drag_mouse_origin := Vector2i.ZERO
var drag_window_origin := Vector2i.ZERO

var rng := RandomNumberGenerator.new()
var burst_particles: GPUParticles3D


func _ready() -> void:
    rng.randomize()

    # Enable per-pixel alpha so the desktop shows through the empty scene area.
    get_viewport().transparent_bg = true
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, false)

    _build_scene()
    _setup_mouse_region()
    _setup_ipc()
    _center_window()

    print("Magic Desktop 3D overlay is ready.")


func _process(delta: float) -> void:
    if is_instance_valid(cake_root):
        cake_root.rotate_y(deg_to_rad(rotation_speed_degrees) * delta)

    flame_clock += delta
    for index in range(flame_nodes.size()):
        var pulse := 1.0 + sin(flame_clock * 8.0 + float(index) * 1.7) * 0.10
        var flame := flame_nodes[index]
        flame.scale = Vector3(0.72 * pulse, 1.12 / pulse, 0.72 * pulse)
        flame.position.y = 1.045 + sin(flame_clock * 5.0 + float(index)) * 0.018
        flame_lights[index].light_energy = 1.25 + sin(flame_clock * 9.0 + float(index)) * 0.25

    _poll_ipc()


func _build_scene() -> void:
    var cake_material := _make_material(Color("#3c1d22"), 0.08, 0.28)
    var chocolate_material := _make_material(Color("#21151a"), 0.12, 0.22)
    var icing_material := _make_material(Color("#f3d7d9"), 0.02, 0.32)
    var plate_material := _make_material(Color("#d8e5f4"), 0.18, 0.24)
    var candle_material := _make_material(Color("#4aa9d8"), 0.05, 0.3)
    var gold_material := _make_material(Color("#ffc65c"), 0.15, 0.25, Color("#ffb43b"), 0.65)

    var candy_colors: Array[Color] = [
        Color("#ff6584"),
        Color("#64d4e8"),
        Color("#ffd166"),
        Color("#9c8cff"),
        Color("#83d69b"),
    ]

    cake_root = Node3D.new()
    cake_root.name = "CakeRoot"
    add_child(cake_root)

    _add_cylinder(cake_root, "CakeBody", 1.12, 1.18, 0.82, 0.0, cake_material)
    _add_cylinder(cake_root, "ChocolateTop", 1.18, 1.18, 0.10, 0.43, chocolate_material)
    _add_cylinder(cake_root, "CreamTop", 1.16, 1.16, 0.045, 0.505, icing_material)
    _add_cylinder(cake_root, "CakePlate", 1.48, 1.52, 0.13, -0.49, plate_material)
    _add_cylinder(cake_root, "PlateFoot", 0.62, 0.72, 0.10, -0.60, plate_material)

    # Rounded icing drips around the outer edge.
    for index in range(14):
        var angle := TAU * float(index) / 14.0
        var drip := _add_sphere(
            cake_root,
            "IcingDrip_%02d" % index,
            0.105,
            icing_material,
            Vector3(cos(angle) * 1.105, 0.365 + rng.randf_range(-0.025, 0.025), sin(angle) * 1.105)
        )
        drip.scale = Vector3(1.0, rng.randf_range(1.0, 1.55), 1.0)

    # Colorful sugar sprinkles scattered over the top surface.
    for index in range(52):
        var angle := rng.randf_range(0.0, TAU)
        var radius := sqrt(rng.randf()) * 0.98
        var sprinkle := MeshInstance3D.new()
        sprinkle.name = "Sprinkle_%02d" % index
        var box := BoxMesh.new()
        box.size = Vector3(rng.randf_range(0.055, 0.12), 0.018, 0.025)
        sprinkle.mesh = box
        sprinkle.material_override = _make_material(
            candy_colors[index % candy_colors.size()],
            0.0,
            0.3,
            candy_colors[index % candy_colors.size()] * 0.18,
            0.18
        )
        sprinkle.position = Vector3(cos(angle) * radius, 0.535, sin(angle) * radius)
        sprinkle.rotation = Vector3(
            rng.randf_range(-0.12, 0.12),
            rng.randf_range(0.0, TAU),
            rng.randf_range(-0.12, 0.12)
        )
        cake_root.add_child(sprinkle)

    # Three candles with individually animated flames and point lights.
    var candle_positions: Array[Vector3] = [
        Vector3(-0.43, 0.0, 0.08),
        Vector3(0.0, 0.0, -0.12),
        Vector3(0.43, 0.0, 0.08),
    ]
    for index in range(candle_positions.size()):
        var candle_group := Node3D.new()
        candle_group.position = candle_positions[index]
        cake_root.add_child(candle_group)

        var candle := MeshInstance3D.new()
        var candle_mesh := CylinderMesh.new()
        candle_mesh.top_radius = 0.052
        candle_mesh.bottom_radius = 0.052
        candle_mesh.height = 0.48
        candle.mesh = candle_mesh
        candle.material_override = candle_material
        candle.position.y = 0.755
        candle_group.add_child(candle)

        var stripe := MeshInstance3D.new()
        var stripe_mesh := CylinderMesh.new()
        stripe_mesh.top_radius = 0.054
        stripe_mesh.bottom_radius = 0.054
        stripe_mesh.height = 0.035
        stripe.mesh = stripe_mesh
        stripe.material_override = icing_material
        stripe.position.y = 0.79
        candle_group.add_child(stripe)

        var flame := MeshInstance3D.new()
        var flame_mesh := SphereMesh.new()
        flame_mesh.radius = 0.105
        flame_mesh.height = 0.27
        flame.mesh = flame_mesh
        flame.material_override = _make_material(
            Color("#ff9b36"), 0.0, 0.18, Color("#ff6a20"), 2.2
        )
        flame.position.y = 1.045
        flame.scale = Vector3(0.72, 1.12, 0.72)
        candle_group.add_child(flame)
        flame_nodes.append(flame)

        var flame_light := OmniLight3D.new()
        flame_light.light_color = Color("#ffad58")
        flame_light.light_energy = 1.25
        flame_light.omni_range = 2.5
        flame_light.position.y = 1.08
        candle_group.add_child(flame_light)
        flame_lights.append(flame_light)

    _add_lighting()
    _add_camera()
    _add_ambient_particles(gold_material)
    _add_burst_particles(gold_material)
    _add_birthday_text()


func _make_material(
    color: Color,
    metallic: float = 0.0,
    roughness: float = 0.35,
    emission_color: Color = Color.BLACK,
    emission_energy: float = 0.0
) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.metallic = metallic
    material.roughness = roughness
    if emission_energy > 0.0:
        material.emission_enabled = true
        material.emission = emission_color
        material.emission_energy_multiplier = emission_energy
    return material


func _add_cylinder(
    parent: Node3D,
    node_name: String,
    top_radius: float,
    bottom_radius: float,
    height: float,
    y_position: float,
    material: Material
) -> MeshInstance3D:
    var mesh := CylinderMesh.new()
    mesh.top_radius = top_radius
    mesh.bottom_radius = bottom_radius
    mesh.height = height

    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.material_override = material
    instance.position.y = y_position
    parent.add_child(instance)
    return instance


func _add_sphere(
    parent: Node3D,
    node_name: String,
    radius: float,
    material: Material,
    position: Vector3
) -> MeshInstance3D:
    var mesh := SphereMesh.new()
    mesh.radius = radius
    mesh.height = radius * 2.0

    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.material_override = material
    instance.position = position
    parent.add_child(instance)
    return instance


func _add_lighting() -> void:
    var key_light := DirectionalLight3D.new()
    key_light.name = "KeyLight"
    key_light.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
    key_light.light_energy = 1.65
    key_light.shadow_enabled = true
    add_child(key_light)

    var fill_light := OmniLight3D.new()
    fill_light.name = "SoftFill"
    fill_light.position = Vector3(-2.8, 1.8, 2.8)
    fill_light.light_color = Color("#9bcfff")
    fill_light.light_energy = 0.55
    fill_light.omni_range = 6.0
    add_child(fill_light)

    var rim_light := OmniLight3D.new()
    rim_light.name = "WarmRim"
    rim_light.position = Vector3(2.2, 1.6, -2.0)
    rim_light.light_color = Color("#ffbd83")
    rim_light.light_energy = 1.0
    rim_light.omni_range = 5.0
    add_child(rim_light)


func _add_camera() -> void:
    var camera := Camera3D.new()
    camera.name = "OverlayCamera"
    camera.position = Vector3(0.0, 2.15, 7.0)
    camera.fov = 38.0
    camera.current = true
    add_child(camera)
    camera.look_at(Vector3(0.0, 0.05, 0.0), Vector3.UP)


func _add_ambient_particles(material: Material) -> void:
    var particle_mesh := SphereMesh.new()
    particle_mesh.radius = 0.035
    particle_mesh.height = 0.07
    particle_mesh.material = material

    var process_material := ParticleProcessMaterial.new()
    process_material.direction = Vector3(0.0, 1.0, 0.0)
    process_material.spread = 180.0
    process_material.initial_velocity_min = 0.08
    process_material.initial_velocity_max = 0.30
    process_material.gravity = Vector3(0.0, 0.025, 0.0)
    process_material.scale_min = 0.35
    process_material.scale_max = 1.1

    var particles := GPUParticles3D.new()
    particles.name = "AmbientStars"
    particles.amount = 42
    particles.lifetime = 4.5
    particles.preprocess = 2.0
    particles.position = Vector3(0.0, 0.0, 0.0)
    particles.process_material = process_material
    particles.draw_pass_1 = particle_mesh
    particles.emitting = true
    add_child(particles)


func _add_burst_particles(material: Material) -> void:
    var particle_mesh := SphereMesh.new()
    particle_mesh.radius = 0.045
    particle_mesh.height = 0.09
    particle_mesh.material = material

    var process_material := ParticleProcessMaterial.new()
    process_material.direction = Vector3(0.0, 1.0, 0.0)
    process_material.spread = 180.0
    process_material.initial_velocity_min = 1.2
    process_material.initial_velocity_max = 2.8
    process_material.gravity = Vector3(0.0, -1.4, 0.0)
    process_material.scale_min = 0.55
    process_material.scale_max = 1.5

    burst_particles = GPUParticles3D.new()
    burst_particles.name = "SurpriseBurst"
    burst_particles.amount = 85
    burst_particles.lifetime = 1.6
    burst_particles.one_shot = true
    burst_particles.explosiveness = 1.0
    burst_particles.position = Vector3(0.0, 0.35, 0.0)
    burst_particles.process_material = process_material
    burst_particles.draw_pass_1 = particle_mesh
    burst_particles.emitting = false
    add_child(burst_particles)


func _add_birthday_text() -> void:
    birthday_label = Label3D.new()
    birthday_label.name = "BirthdayText"
    birthday_label.text = "Happy Birthday"
    birthday_label.font_size = 48
    birthday_label.pixel_size = 0.0045
    birthday_label.modulate = Color("#ffe0a2")
    birthday_label.outline_size = 8
    birthday_label.outline_modulate = Color("#45222b")
    birthday_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    birthday_label.position = Vector3(0.0, -1.18, 0.35)
    add_child(birthday_label)


func _setup_mouse_region() -> void:
    var polygon := PackedVector2Array()
    var center := Vector2(WINDOW_WIDTH * 0.5, WINDOW_HEIGHT * 0.53)
    for index in range(24):
        var angle := TAU * float(index) / 24.0
        polygon.append(
            center + Vector2(cos(angle) * 235.0, sin(angle) * 190.0)
        )
    DisplayServer.window_set_mouse_passthrough(polygon)


func _set_passthrough(enabled: bool) -> void:
    passthrough_enabled = enabled
    DisplayServer.window_set_flag(
        DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH,
        enabled
    )
    if not enabled:
        _setup_mouse_region()
    else:
        DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
    print("Mouse passthrough: ", enabled)


func _center_window() -> void:
    var screen_size := DisplayServer.screen_get_size()
    var position := Vector2i(
        int((screen_size.x - WINDOW_WIDTH) / 2),
        int((screen_size.y - WINDOW_HEIGHT) / 2)
    )
    DisplayServer.window_set_position(position)


func _setup_ipc() -> void:
    var port := DEFAULT_PORT
    var env_port := OS.get_environment("MAGIC_DESKTOP_PORT")
    if not env_port.is_empty() and env_port.is_valid_int():
        port = int(env_port)

    var error := udp.bind(port, "127.0.0.1")
    if error != OK:
        push_error("Could not bind local control port %d: %s" % [port, error_string(error)])
    else:
        print("Local control channel listening on 127.0.0.1:%d" % port)


func _poll_ipc() -> void:
    while udp.get_available_packet_count() > 0:
        var packet := udp.get_packet()
        var parsed = JSON.parse_string(packet.get_string_from_utf8())
        if parsed is Dictionary:
            _handle_command(parsed)


func _handle_command(command: Dictionary) -> void:
    var action := str(command.get("action", ""))
    match action:
        "set_rotation_speed":
            rotation_speed_degrees = clampf(
                float(command.get("value", 24.0)),
                0.0,
                120.0
            )
        "set_text":
            if is_instance_valid(birthday_label):
                var new_text := str(command.get("value", "Happy Birthday")).strip_edges()
                birthday_label.text = new_text.left(32) if not new_text.is_empty() else "Happy Birthday"
        "burst":
            _trigger_surprise()
        "set_passthrough":
            _set_passthrough(bool(command.get("enabled", false)))
        "show":
            get_window().visible = true
        "hide":
            get_window().visible = false
        "quit":
            get_tree().quit()
        _:
            print("Unknown command: ", action)


func _trigger_surprise() -> void:
    if is_instance_valid(burst_particles):
        burst_particles.restart()
    if is_instance_valid(cake_root):
        var tween := create_tween()
        tween.set_trans(Tween.TRANS_BACK)
        tween.set_ease(Tween.EASE_OUT)
        tween.tween_property(cake_root, "scale", Vector3(1.09, 1.09, 1.09), 0.18)
        tween.tween_property(cake_root, "scale", Vector3.ONE, 0.32)


func _input(event: InputEvent) -> void:
    if passthrough_enabled:
        return

    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            dragging = true
            drag_moved = false
            drag_mouse_origin = DisplayServer.mouse_get_position()
            drag_window_origin = DisplayServer.window_get_position()
        else:
            if dragging and not drag_moved:
                _trigger_surprise()
            dragging = false

    elif event is InputEventMouseMotion and dragging:
        var current_mouse := DisplayServer.mouse_get_position()
        if current_mouse.distance_to(drag_mouse_origin) > 4:
            drag_moved = true
        if drag_moved:
            DisplayServer.window_set_position(
                drag_window_origin + current_mouse - drag_mouse_origin
            )
