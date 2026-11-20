extends Node3D

const DEFAULT_PORT := 49261
const WINDOW_WIDTH := 820
const WINDOW_HEIGHT := 720

var udp := PacketPeerUDP.new()
var cake_root: Node3D
var birthday_label: Label3D
var subtitle_label: Label3D
var flame_nodes: Array[MeshInstance3D] = []
var flame_lights: Array[OmniLight3D] = []
var star_nodes: Array[MeshInstance3D] = []
var star_phases: Array[float] = []
var star_base_positions: Array[Vector3] = []
var rotation_speed_degrees := 12.0
var flame_clock := 0.0
var passthrough_enabled := false
var dragging := false
var drag_moved := false
var drag_mouse_origin := Vector2i.ZERO
var drag_window_origin := Vector2i.ZERO
var rng := RandomNumberGenerator.new()
var burst_particles: GPUParticles3D
var halo_ring: MeshInstance3D


func _ready() -> void:
    rng.randomize()

    get_viewport().transparent_bg = true
    get_viewport().msaa_3d = Viewport.MSAA_4X
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, false)

    _setup_environment()
    _build_scene()
    _setup_mouse_region()
    _setup_ipc()
    _center_window()

    print("Magic Desktop premium 3D overlay is ready.")


func _process(delta: float) -> void:
    flame_clock += delta

    if is_instance_valid(cake_root):
        cake_root.rotate_y(deg_to_rad(rotation_speed_degrees) * delta)
        cake_root.position.y = sin(flame_clock * 1.15) * 0.035

    for index in range(flame_nodes.size()):
        var pulse := 1.0 + sin(flame_clock * 10.0 + float(index) * 1.9) * 0.13
        var flame := flame_nodes[index]
        flame.scale = Vector3(0.68 * pulse, 1.15 / pulse, 0.68 * pulse)
        flame.position.y = 1.47 + sin(flame_clock * 7.0 + float(index)) * 0.025
        flame.rotation.z = sin(flame_clock * 5.0 + float(index) * 2.0) * 0.10
        flame_lights[index].light_energy = 1.15 + sin(flame_clock * 11.0 + float(index)) * 0.28

    for index in range(star_nodes.size()):
        var star := star_nodes[index]
        var phase := star_phases[index]
        star.position.y = star_base_positions[index].y + sin(flame_clock * 1.35 + phase) * 0.10
        star.rotation.z += delta * (0.22 + float(index % 4) * 0.08)

    if is_instance_valid(halo_ring):
        halo_ring.rotate_z(delta * 0.12)

    _poll_ipc()


func _setup_environment() -> void:
    var environment := Environment.new()
    environment.background_mode = Environment.BG_CLEAR_COLOR
    environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color("#b9c9e8")
    environment.ambient_light_energy = 0.62
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    environment.glow_enabled = true
    environment.glow_intensity = 0.72
    environment.glow_strength = 1.0
    environment.glow_bloom = 0.08

    var world := WorldEnvironment.new()
    world.name = "PremiumWorldEnvironment"
    world.environment = environment
    add_child(world)


func _build_scene() -> void:
    var chocolate := _make_material(Color("#35151b"), 0.10, 0.24)
    var dark_chocolate := _make_material(Color("#211016"), 0.18, 0.19)
    var ganache := _make_material(Color("#24121b"), 0.24, 0.16)
    var sponge := _make_material(Color("#d99a55"), 0.02, 0.42)
    var cream := _make_material(Color("#fff0dc"), 0.0, 0.31)
    var plate_material := _make_material(Color("#e7edf8"), 0.28, 0.20)
    var gold := _make_material(Color("#f6bd62"), 0.72, 0.20, Color("#ffbf55"), 0.28)
    var blue := _make_material(Color("#55c5e8"), 0.28, 0.23)
    var candle_white := _make_material(Color("#eaf8ff"), 0.06, 0.25)
    var candy_colors: Array[Color] = [
        Color("#ff5f83"),
        Color("#55d8ee"),
        Color("#ffd166"),
        Color("#a68cff"),
        Color("#7bd7a0"),
        Color("#ff9c55"),
    ]

    cake_root = Node3D.new()
    cake_root.name = "HeroCake"
    add_child(cake_root)

    # Porcelain stand: a raised foot, broad plate and fine metallic rim.
    _add_cylinder(cake_root, "StandFoot", 0.60, 0.68, 0.13, -0.73, plate_material)
    _add_cylinder(cake_root, "PorcelainPlate", 1.48, 1.55, 0.12, -0.62, plate_material)
    _add_torus(cake_root, "GoldPlateRim", 1.43, 1.47, 0.018, -0.555, gold)

    # Two soft sponge layers separated by a visible cream filling.
    _add_cylinder(cake_root, "LowerSponge", 1.12, 1.15, 0.53, -0.285, sponge)
    _add_cylinder(cake_root, "LowerChocolateCoat", 1.155, 1.155, 0.43, -0.235, chocolate)
    _add_cylinder(cake_root, "CreamFilling", 1.17, 1.17, 0.075, 0.015, cream)
    _add_cylinder(cake_root, "UpperSponge", 1.075, 1.10, 0.50, 0.305, sponge)
    _add_cylinder(cake_root, "UpperChocolateCoat", 1.105, 1.105, 0.43, 0.34, dark_chocolate)
    _add_cylinder(cake_root, "GlossyGanacheTop", 1.145, 1.145, 0.105, 0.585, ganache)
    _add_cylinder(cake_root, "TopChocolateSurface", 1.125, 1.125, 0.035, 0.65, ganache)

    # Chocolate drips of varied lengths around the top edge.
    for index in range(22):
        var angle := TAU * float(index) / 22.0
        var length := rng.randf_range(0.12, 0.34)
        var drip := _add_sphere(
            cake_root,
            "GanacheDrip_%02d" % index,
            rng.randf_range(0.075, 0.105),
            ganache,
            Vector3(cos(angle) * 1.105, 0.57 - length * 0.43, sin(angle) * 1.105)
        )
        drip.scale = Vector3(0.86, length / 0.15, 0.86)

    # Piped cream rosettes around the rim.
    for index in range(14):
        var angle := TAU * float(index) / 14.0
        var position := Vector3(cos(angle) * 0.91, 0.715, sin(angle) * 0.91)
        var rosette := _add_sphere(cake_root, "CreamRosette_%02d" % index, 0.13, cream, position)
        rosette.scale = Vector3(1.0, 0.78, 1.0)
        _add_sphere(
            cake_root,
            "RosettePeak_%02d" % index,
            0.065,
            cream,
            position + Vector3(0.0, 0.075, 0.0)
        )

    # Fine sugar sprinkles and glossy candy pearls on the top.
    for index in range(105):
        var angle := rng.randf_range(0.0, TAU)
        var radius := sqrt(rng.randf()) * 0.78
        var color: Color = candy_colors[index % candy_colors.size()]
        var sprinkle := MeshInstance3D.new()
        var box := BoxMesh.new()
        box.size = Vector3(rng.randf_range(0.035, 0.095), 0.014, 0.022)
        sprinkle.mesh = box
        sprinkle.material_override = _make_material(color, 0.05, 0.25, color * 0.16, 0.12)
        sprinkle.position = Vector3(cos(angle) * radius, 0.686, sin(angle) * radius)
        sprinkle.rotation = Vector3(
            rng.randf_range(-0.10, 0.10),
            rng.randf_range(0.0, TAU),
            rng.randf_range(-0.10, 0.10)
        )
        cake_root.add_child(sprinkle)

    for index in range(28):
        var angle := rng.randf_range(0.0, TAU)
        var radius := rng.randf_range(0.20, 0.86)
        var pearl_color: Color = candy_colors[(index * 3) % candy_colors.size()]
        _add_sphere(
            cake_root,
            "CandyPearl_%02d" % index,
            rng.randf_range(0.025, 0.045),
            _make_material(pearl_color, 0.18, 0.16, pearl_color * 0.2, 0.18),
            Vector3(cos(angle) * radius, 0.70, sin(angle) * radius)
        )

    _add_candles(candle_white, blue, cream)
    _add_side_decorations(gold, cream, candy_colors)
    _add_ribbons()
    _add_floating_stars()
    _add_lighting()
    _add_camera()
    _add_ambient_particles()
    _add_burst_particles(gold)
    _add_birthday_text()


func _add_candles(candle_white: Material, blue: Material, cream: Material) -> void:
    var candle_positions: Array[Vector3] = [
        Vector3(-0.43, 0.0, 0.10),
        Vector3(0.0, 0.0, -0.16),
        Vector3(0.43, 0.0, 0.10),
    ]

    for index in range(candle_positions.size()):
        var candle_group := Node3D.new()
        candle_group.position = candle_positions[index]
        cake_root.add_child(candle_group)

        var candle := MeshInstance3D.new()
        var candle_mesh := CylinderMesh.new()
        candle_mesh.top_radius = 0.047
        candle_mesh.bottom_radius = 0.052
        candle_mesh.height = 0.54
        candle_mesh.radial_segments = 32
        candle.mesh = candle_mesh
        candle.material_override = candle_white if index == 1 else blue
        candle.position.y = 0.99
        candle_group.add_child(candle)

        for stripe_index in range(5):
            var stripe := MeshInstance3D.new()
            var stripe_mesh := TorusMesh.new()
            stripe_mesh.inner_radius = 0.044
            stripe_mesh.outer_radius = 0.055
            stripe_mesh.rings = 8
            stripe_mesh.ring_segments = 20
            stripe.mesh = stripe_mesh
            stripe.material_override = cream if stripe_index % 2 == 0 else candle_white
            stripe.position.y = 0.79 + float(stripe_index) * 0.095
            stripe.rotation_degrees.x = 90.0
            candle_group.add_child(stripe)

        var wick := _add_cylinder(candle_group, "Wick_%d" % index, 0.008, 0.008, 0.075, 1.295, darken_material(cream))
        wick.position.z = 0.0

        var flame := MeshInstance3D.new()
        var flame_mesh := SphereMesh.new()
        flame_mesh.radius = 0.092
        flame_mesh.height = 0.25
        flame_mesh.radial_segments = 24
        flame.mesh = flame_mesh
        flame.material_override = _make_material(
            Color("#ff9a36"), 0.0, 0.16, Color("#ff6b24"), 2.8
        )
        flame.position.y = 1.47
        flame.scale = Vector3(0.68, 1.15, 0.68)
        candle_group.add_child(flame)
        flame_nodes.append(flame)

        var inner_flame := MeshInstance3D.new()
        var inner_mesh := SphereMesh.new()
        inner_mesh.radius = 0.045
        inner_mesh.height = 0.16
        inner_flame.mesh = inner_mesh
        inner_flame.material_override = _make_material(
            Color("#fff0a8"), 0.0, 0.12, Color("#ffe28a"), 2.4
        )
        inner_flame.position = Vector3(0.0, 1.455, 0.025)
        inner_flame.scale = Vector3(0.58, 1.12, 0.58)
        candle_group.add_child(inner_flame)

        var flame_light := OmniLight3D.new()
        flame_light.light_color = Color("#ffad58")
        flame_light.light_energy = 1.15
        flame_light.omni_range = 2.2
        flame_light.position.y = 1.48
        candle_group.add_child(flame_light)
        flame_lights.append(flame_light)


func darken_material(source: Material) -> Material:
    var result := _make_material(Color("#3b2630"), 0.0, 0.5)
    return result


func _add_side_decorations(gold: Material, cream: Material, candy_colors: Array[Color]) -> void:
    # Small pearl chain around the lower edge adds a finished patisserie detail.
    for index in range(34):
        var angle := TAU * float(index) / 34.0
        var position := Vector3(cos(angle) * 1.145, -0.43, sin(angle) * 1.145)
        _add_sphere(
            cake_root,
            "GoldPearl_%02d" % index,
            0.026,
            gold,
            position
        )

    # Alternating candy medallions on the front-facing side.
    for index in range(9):
        var angle := PI * 0.5 + (float(index) - 4.0) * 0.19
        var color: Color = candy_colors[index % candy_colors.size()]
        var position := Vector3(cos(angle) * 1.13, -0.02, sin(angle) * 1.13)
        var medallion := _add_sphere(
            cake_root,
            "SideCandy_%02d" % index,
            0.065,
            _make_material(color, 0.28, 0.18, color * 0.15, 0.12),
            position
        )
        medallion.scale = Vector3(1.0, 0.75, 0.42)


func _add_ribbons() -> void:
    var pink := _make_material(Color("#f28ab5"), 0.42, 0.22, Color("#f28ab5"), 0.16)
    var cyan := _make_material(Color("#67d7ed"), 0.48, 0.18, Color("#67d7ed"), 0.18)
    var gold := _make_material(Color("#f6c56e"), 0.72, 0.20, Color("#ffcf75"), 0.22)

    var left_points: Array[Vector3] = []
    var right_points: Array[Vector3] = []
    for index in range(90):
        var t := float(index) / 89.0
        var angle := t * TAU * 1.25
        left_points.append(Vector3(
            -1.62 + 0.30 * sin(angle),
            -0.38 + t * 2.55,
            -1.12 + 0.12 * cos(angle)
        ))
        right_points.append(Vector3(
            1.62 + 0.28 * sin(angle + 1.2),
            -0.24 + t * 2.25,
            -1.18 + 0.12 * cos(angle + 1.2)
        ))

    _add_ribbon_mesh(left_points, 0.105, pink, "FloatingPinkRibbon")
    _add_ribbon_mesh(right_points, 0.095, cyan, "FloatingBlueRibbon")

    var gold_points: Array[Vector3] = []
    for index in range(100):
        var t := float(index) / 99.0
        var angle := t * TAU * 1.7
        gold_points.append(Vector3(
            -2.05 + t * 4.10,
            1.62 + sin(angle) * 0.19,
            -1.35 + cos(angle) * 0.08
        ))
    _add_ribbon_mesh(gold_points, 0.045, gold, "GoldenStreamer")


func _add_ribbon_mesh(points: Array[Vector3], width: float, material: Material, node_name: String) -> void:
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)

    for index in range(points.size() - 1):
        var tangent := (points[index + 1] - points[index]).normalized()
        var side := tangent.cross(Vector3.FORWARD).normalized()
        if side.length() < 0.01:
            side = Vector3.RIGHT
        side *= width * 0.5

        var a := points[index] - side
        var b := points[index] + side
        var c := points[index + 1] - side
        var d := points[index + 1] + side

        surface.add_vertex(a)
        surface.add_vertex(b)
        surface.add_vertex(c)
        surface.add_vertex(b)
        surface.add_vertex(d)
        surface.add_vertex(c)

    surface.generate_normals()
    var mesh := surface.commit()
    var ribbon := MeshInstance3D.new()
    ribbon.name = node_name
    ribbon.mesh = mesh
    ribbon.material_override = material
    if material is StandardMaterial3D:
        material.cull_mode = BaseMaterial3D.CULL_DISABLED
    add_child(ribbon)


func _add_floating_stars() -> void:
    var star_mesh := _create_star_mesh()
    var colors: Array[Color] = [
        Color("#ffd166"),
        Color("#79dff1"),
        Color("#ff8db5"),
        Color("#fff0b0"),
        Color("#a997ff"),
    ]

    for index in range(17):
        var star := MeshInstance3D.new()
        star.name = "FloatingStar_%02d" % index
        star.mesh = star_mesh
        var color: Color = colors[index % colors.size()]
        var material := _make_material(color, 0.24, 0.20, color, 0.72)
        material.cull_mode = BaseMaterial3D.CULL_DISABLED
        star.material_override = material

        var side := -1.0 if index % 2 == 0 else 1.0
        var base_position := Vector3(
            side * rng.randf_range(1.55, 2.35),
            rng.randf_range(-0.10, 2.05),
            rng.randf_range(-0.55, -0.10)
        )
        star.position = base_position
        var size := rng.randf_range(0.10, 0.23)
        star.scale = Vector3(size, size, size)
        star.rotation = Vector3(0.0, 0.0, rng.randf_range(-PI, PI))
        add_child(star)

        star_nodes.append(star)
        star_phases.append(rng.randf_range(0.0, TAU))
        star_base_positions.append(base_position)


func _create_star_mesh() -> ArrayMesh:
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)

    var points: Array[Vector3] = []
    for index in range(10):
        var angle := -PI * 0.5 + TAU * float(index) / 10.0
        var radius := 0.5 if index % 2 == 0 else 0.22
        points.append(Vector3(cos(angle) * radius, sin(angle) * radius, 0.0))

    for index in range(10):
        surface.add_vertex(Vector3.ZERO)
        surface.add_vertex(points[index])
        surface.add_vertex(points[(index + 1) % 10])

    surface.generate_normals()
    return surface.commit()


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
    mesh.radial_segments = 64

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
    mesh.radial_segments = 24
    mesh.rings = 16

    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.material_override = material
    instance.position = position
    parent.add_child(instance)
    return instance


func _add_torus(
    parent: Node3D,
    node_name: String,
    inner_radius: float,
    outer_radius: float,
    thickness: float,
    y_position: float,
    material: Material
) -> MeshInstance3D:
    var mesh := TorusMesh.new()
    mesh.inner_radius = inner_radius
    mesh.outer_radius = outer_radius
    mesh.rings = 64
    mesh.ring_segments = 12

    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.material_override = material
    instance.position.y = y_position
    instance.scale = Vector3.ONE * (1.0 + thickness * 0.0)
    parent.add_child(instance)
    return instance


func _add_lighting() -> void:
    var key_light := DirectionalLight3D.new()
    key_light.name = "SoftboxKey"
    key_light.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
    key_light.light_color = Color("#fff0dc")
    key_light.light_energy = 1.75
    key_light.shadow_enabled = true
    add_child(key_light)

    var fill_light := OmniLight3D.new()
    fill_light.name = "CoolFill"
    fill_light.position = Vector3(-2.8, 2.2, 3.0)
    fill_light.light_color = Color("#9bdcff")
    fill_light.light_energy = 0.72
    fill_light.omni_range = 6.5
    add_child(fill_light)

    var rim_light := OmniLight3D.new()
    rim_light.name = "WarmRim"
    rim_light.position = Vector3(2.8, 1.8, -2.2)
    rim_light.light_color = Color("#ffb76e")
    rim_light.light_energy = 1.35
    rim_light.omni_range = 5.5
    add_child(rim_light)

    var front_light := OmniLight3D.new()
    front_light.name = "FrontSoftbox"
    front_light.position = Vector3(0.0, 0.4, 4.0)
    front_light.light_color = Color("#ffffff")
    front_light.light_energy = 0.42
    front_light.omni_range = 5.0
    add_child(front_light)


func _add_camera() -> void:
    var camera := Camera3D.new()
    camera.name = "HeroCamera"
    camera.position = Vector3(0.0, 2.45, 8.4)
    camera.fov = 39.0
    camera.current = true
    add_child(camera)
    camera.look_at(Vector3(0.0, 0.05, 0.0), Vector3.UP)


func _add_ambient_particles() -> void:
    var particle_mesh := SphereMesh.new()
    particle_mesh.radius = 0.025
    particle_mesh.height = 0.05
    particle_mesh.material = _make_material(Color("#ffe3a0"), 0.0, 0.2, Color("#ffe3a0"), 1.6)

    var process_material := ParticleProcessMaterial.new()
    process_material.direction = Vector3(0.0, 1.0, 0.0)
    process_material.spread = 180.0
    process_material.initial_velocity_min = 0.05
    process_material.initial_velocity_max = 0.26
    process_material.gravity = Vector3(0.0, 0.015, 0.0)
    process_material.scale_min = 0.35
    process_material.scale_max = 1.25

    var particles := GPUParticles3D.new()
    particles.name = "AmbientGlitter"
    particles.amount = 95
    particles.lifetime = 5.0
    particles.preprocess = 2.5
    particles.visibility_aabb = AABB(Vector3(-4.0, -2.0, -2.0), Vector3(8.0, 6.0, 4.0))
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
    process_material.initial_velocity_min = 1.4
    process_material.initial_velocity_max = 3.2
    process_material.gravity = Vector3(0.0, -1.5, 0.0)
    process_material.scale_min = 0.45
    process_material.scale_max = 1.4

    burst_particles = GPUParticles3D.new()
    burst_particles.name = "GoldenSurpriseBurst"
    burst_particles.amount = 140
    burst_particles.lifetime = 1.8
    burst_particles.one_shot = true
    burst_particles.explosiveness = 0.96
    burst_particles.position = Vector3(0.0, 0.45, 0.1)
    burst_particles.visibility_aabb = AABB(Vector3(-4.0, -2.0, -2.0), Vector3(8.0, 6.0, 4.0))
    burst_particles.process_material = process_material
    burst_particles.draw_pass_1 = particle_mesh
    burst_particles.emitting = false
    add_child(burst_particles)


func _add_birthday_text() -> void:
    var shadow := Label3D.new()
    shadow.name = "BirthdayTextShadow"
    shadow.text = "Happy Birthday"
    shadow.font_size = 58
    shadow.pixel_size = 0.0037
    shadow.modulate = Color("#25131c")
    shadow.outline_size = 0
    shadow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    shadow.position = Vector3(0.025, -1.57, 0.42)
    add_child(shadow)

    birthday_label = Label3D.new()
    birthday_label.name = "BirthdayText"
    birthday_label.text = "Happy Birthday"
    birthday_label.font_size = 58
    birthday_label.pixel_size = 0.0037
    birthday_label.modulate = Color("#ffe0a2")
    birthday_label.outline_size = 7
    birthday_label.outline_modulate = Color("#4b2530")
    birthday_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    birthday_label.position = Vector3(0.0, -1.54, 0.46)
    add_child(birthday_label)

    subtitle_label = Label3D.new()
    subtitle_label.name = "BirthdaySubtitle"
    subtitle_label.text = "MAKE A WISH"
    subtitle_label.font_size = 20
    subtitle_label.pixel_size = 0.0032
    subtitle_label.modulate = Color("#9fe5f2")
    subtitle_label.outline_size = 4
    subtitle_label.outline_modulate = Color("#172b3a")
    subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    subtitle_label.position = Vector3(0.0, -1.82, 0.46)
    add_child(subtitle_label)


func _setup_mouse_region() -> void:
    var polygon := PackedVector2Array()
    var center := Vector2(WINDOW_WIDTH * 0.5, WINDOW_HEIGHT * 0.50)
    for index in range(40):
        var angle := TAU * float(index) / 40.0
        polygon.append(center + Vector2(cos(angle) * 355.0, sin(angle) * 315.0))
    DisplayServer.window_set_mouse_passthrough(polygon)


func _set_passthrough(enabled: bool) -> void:
    passthrough_enabled = enabled
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, enabled)
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
    DisplayServer.window_set_size(Vector2i(WINDOW_WIDTH, WINDOW_HEIGHT))
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
            rotation_speed_degrees = clampf(float(command.get("value", 12.0)), 0.0, 120.0)
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
        tween.tween_property(cake_root, "scale", Vector3(1.075, 1.075, 1.075), 0.20)
        tween.tween_property(cake_root, "scale", Vector3.ONE, 0.36)

    for index in range(star_nodes.size()):
        var star := star_nodes[index]
        var original_scale := star.scale
        var pop := create_tween()
        pop.tween_property(star, "scale", original_scale * 1.45, 0.16)
        pop.tween_property(star, "scale", original_scale, 0.30)


func _input(event: InputEvent) -> void:
    if passthrough_enabled:
        return

    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            dragging = true
            drag_moved = false
            drag_mouse_origin = DisplayServer.mouse_get_position()
            drag_window_origin = DisplayServer.window_get_position()
            DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
        else:
            if dragging and not drag_moved:
                _trigger_surprise()
            dragging = false
            if not passthrough_enabled:
                _setup_mouse_region()

    elif event is InputEventMouseMotion and dragging:
        var current_mouse := DisplayServer.mouse_get_position()
        if current_mouse.distance_to(drag_mouse_origin) > 4:
            drag_moved = true
        if drag_moved:
            DisplayServer.window_set_position(
                drag_window_origin + current_mouse - drag_mouse_origin
            )
