extends Node3D

const DEFAULT_PORT := 49261
const WINDOW_WIDTH := 1120
const WINDOW_HEIGHT := 630
const BALLOON_WAVE_END := 5.90
const BALLOON_LANES := 10
const BALLOON_COUNT := 30

var udp := PacketPeerUDP.new()
var export_mode := false
var cake_platform: Node3D
var cake_root: Node3D
var mascot_root: Node3D
var birthday_label: Label3D
var music_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer
var export_backdrop: MeshInstance3D
var flame_nodes: Array[MeshInstance3D] = []
var flame_lights: Array[OmniLight3D] = []
var star_nodes: Array[MeshInstance3D] = []
var star_phases: Array[float] = []
var star_base_positions: Array[Vector3] = []
var rotation_speed_degrees := 8.0
var flame_clock := 0.0
var passthrough_enabled := false
var dragging := false
var drag_moved := false
var drag_mouse_origin := Vector2i.ZERO
var drag_window_origin := Vector2i.ZERO
var rng := RandomNumberGenerator.new()
var warm_rim: OmniLight3D
var softbox: DirectionalLight3D
var star_sizes: Array[float] = []
var backdrop_material: ShaderMaterial
var balloon_nodes: Array[Node3D] = []
var balloon_base_x: Array[float] = []
var balloon_flights: Array[Vector2] = []


func _ready() -> void:
    rng.seed = 19117
    export_mode = OS.get_environment("MAGIC_DESKTOP_EXPORT") == "1"

    get_viewport().transparent_bg = not export_mode
    get_viewport().msaa_3d = Viewport.MSAA_4X

    if not export_mode:
        DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
        DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
        DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
        DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, false)
    else:
        DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
        DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)
        DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, false)

    _setup_environment()
    _build_scene()
    _setup_audio()
    _apply_startup_settings()
    _animate_scene(0.0, 0.0)

    if not export_mode:
        _setup_mouse_region()
        _setup_ipc()
        _center_window()
    else:
        # Movie Maker writes the scene audio to frame.wav beside the PNG sequence.
        if music_player.stream != null:
            music_player.play()

    print("Magic Desktop premium 3D scene is ready. Export mode: ", export_mode)


func _process(delta: float) -> void:
    flame_clock += delta

    _animate_scene(flame_clock, delta)
    _poll_ipc()


func _animate_scene(time: float, delta: float) -> void:
    var intro := smoothstep(0.0, 1.6, time)
    var platform_lift := smoothstep(BALLOON_WAVE_END, 8.10, time)
    var focus := smoothstep(6.65, 8.25, time)
    var reveal := smoothstep(8.55, 10.45, time)
    birthday_label.modulate.a = reveal
    birthday_label.position.y = 2.81 + reveal * 0.13
    softbox.light_energy = 0.17 + 0.37 * intro + 0.16 * focus
    warm_rim.light_energy = 0.22 + 0.66 * focus
    backdrop_material.set_shader_parameter("arrival", intro)
    # The porcelain stand and its companions travel with the stage lift.
    cake_platform.visible = time >= BALLOON_WAVE_END
    cake_platform.position.y = lerpf(-8.5, 0.0, platform_lift)
    cake_root.rotate_y(deg_to_rad(rotation_speed_degrees) * delta)
    mascot_root.rotation.x = 0.03 * sin(time * 1.5)
    mascot_root.rotation.y = -0.24 + 0.06 * sin(time * 0.92)

    for index in range(flame_nodes.size()):
        var phase := time * 8.0 + float(index) * 2.1
        var flicker := 0.68 * sin(phase) + 0.32 * sin(phase * 1.83)
        var flame := flame_nodes[index]
        flame.scale = Vector3(0.68 - flicker * 0.045, 1.15 + flicker * 0.10, 0.68)
        flame.rotation.z = 0.09 * sin(phase * 0.52)
        flame_lights[index].light_energy = (0.23 + focus * 0.22) * (1.0 + flicker * 0.18)

    for index in range(star_nodes.size()):
        var star := star_nodes[index]
        var phase := star_phases[index]
        var drift := time * (0.32 + float(index % 7) * 0.09) + phase
        var twinkle := smoothstep(-0.60, 0.93, sin(drift * 1.8))
        star.position = star_base_positions[index] + Vector3(0.14 * sin(drift), 0.09 * cos(drift * 0.72), 0.09 * sin(drift))
        star.rotation.z = phase + drift * 0.15
        star.scale = Vector3.ONE * maxf(0.0001, intro * star_sizes[index] * twinkle)

    for index in range(balloon_nodes.size()):
        var balloon := balloon_nodes[index]
        var flight := balloon_flights[index]
        balloon.visible = time >= flight.x and time < minf(flight.y, BALLOON_WAVE_END)
        if not balloon.visible:
            continue
        var age := time - flight.x
        var lift := age / (flight.y - flight.x)
        var phase := float(index) * 2.39
        balloon.position.y = lerpf(-5.0, 6.8, lift)
        balloon.position.x = balloon_base_x[index] + 0.25 * sin(age * 1.9 + phase)
        balloon.rotation.z = 0.16 * sin(age * 1.7 + phase)
        balloon.rotation.y = 0.28 * sin(age * 1.3 + phase)


func _setup_environment() -> void:
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR if export_mode else Environment.BG_CLEAR_COLOR
    environment.background_color = Color("#0b1020") if export_mode else Color(0.0, 0.0, 0.0, 0.0)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color("#b9c9e8")
    environment.ambient_light_energy = 0.30
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    var world := WorldEnvironment.new()
    world.name = "PremiumWorldEnvironment"
    world.environment = environment
    add_child(world)


func _build_scene() -> void:
    cake_platform = Node3D.new()
    cake_platform.name = "CakePlatform"
    add_child(cake_platform)

    var chocolate := _make_material(Color("#eaa0b5"), 0.04, 0.30)
    var dark_chocolate := _make_material(Color("#c96d8a"), 0.06, 0.28)
    var ganache := _make_material(Color("#f4a9bf"), 0.10, 0.22)
    var sponge := _make_material(Color("#f2d5b8"), 0.0, 0.48)
    var cream := _make_material(Color("#fff4e8"), 0.0, 0.38)
    var plate_material := _make_material(Color("#fffaf3"), 0.12, 0.26)
    ganache.clearcoat_enabled = true
    ganache.clearcoat = 0.82
    ganache.clearcoat_roughness = 0.12
    var gold := _make_material(Color("#f6bd62"), 0.72, 0.20, Color("#ffbf55"), 0.28)
    var blue := _make_material(Color("#8ddcf0"), 0.12, 0.30)
    var candle_white := _make_material(Color("#fff7ee"), 0.02, 0.34)
    var candy_colors: Array[Color] = [
        Color("#ff5f83"),
        Color("#55d8ee"),
        Color("#ffd166"),
        Color("#a68cff"),
        Color("#7bd7a0"),
        Color("#ff9c55"),
    ]
    var candy_materials: Array[Material] = []
    for candy_color in candy_colors:
        candy_materials.append(
            _make_material(candy_color, 0.16, 0.20, candy_color * 0.18, 0.14)
        )

    cake_root = Node3D.new()
    cake_root.name = "HeroCake"
    cake_root.scale = Vector3.ONE * 1.12
    cake_platform.add_child(cake_root)

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

    # Hand-piped cream swirls around the top edge.
    for index in range(14):
        var angle := TAU * float(index) / 14.0
        var position := Vector3(cos(angle) * 0.91, 0.705, sin(angle) * 0.91)
        _add_cream_swirl(cake_root, position, cream, "CreamRosette_%02d" % index)

    # Fine sugar sprinkles and glossy candy pearls on the top.
    for index in range(105):
        var angle := rng.randf_range(0.0, TAU)
        var radius := sqrt(rng.randf()) * 0.78
        var sprinkle := MeshInstance3D.new()
        var box := BoxMesh.new()
        box.size = Vector3(rng.randf_range(0.035, 0.095), 0.014, 0.022)
        sprinkle.mesh = box
        sprinkle.material_override = candy_materials[index % candy_materials.size()]
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
        _add_sphere(
            cake_root,
            "CandyPearl_%02d" % index,
            rng.randf_range(0.025, 0.045),
            candy_materials[(index * 3) % candy_materials.size()],
            Vector3(cos(angle) * radius, 0.70, sin(angle) * radius)
        )

    _add_candles(candle_white, blue, cream)
    _add_side_decorations(gold, cream, candy_colors)
    _add_strawberries()
    _add_floating_stars()
    _add_export_backdrop()
    _add_lighting()
    _add_camera()
    _add_birthday_text()
    _add_mascot_bear()
    _add_gift_box()
    _add_balloons()
    _add_stage()


func _add_cream_swirl(parent: Node3D, center: Vector3, material: Material, node_name: String) -> void:
    const STEPS := 34
    const RING_SEGMENTS := 10

    var path_points: Array[Vector3] = []
    for step in range(STEPS):
        var t := float(step) / float(STEPS - 1)
        var angle := t * TAU * 1.45
        var orbit_radius := 0.105 * (1.0 - t * 0.76)
        path_points.append(center + Vector3(
            cos(angle) * orbit_radius,
            t * 0.16,
            sin(angle) * orbit_radius
        ))

    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    var vertices := PackedVector3Array()

    for step in range(STEPS):
        var previous_index := maxi(0, step - 1)
        var next_index := mini(STEPS - 1, step + 1)
        var tangent := (path_points[next_index] - path_points[previous_index]).normalized()
        var side := tangent.cross(Vector3.UP).normalized()
        if side.length() < 0.01:
            side = Vector3.RIGHT
        var normal := tangent.cross(side).normalized()
        var t := float(step) / float(STEPS - 1)
        var tube_radius := 0.040 * (1.0 - t * 0.62)
        for ring_index in range(RING_SEGMENTS):
            var ring_angle := TAU * float(ring_index) / float(RING_SEGMENTS)
            var offset := (
                side * cos(ring_angle) + normal * sin(ring_angle)
            ) * tube_radius
            vertices.append(path_points[step] + offset)

    for step in range(STEPS - 1):
        for ring_index in range(RING_SEGMENTS):
            var next_index := (ring_index + 1) % RING_SEGMENTS
            var current_base := step * RING_SEGMENTS
            var next_base := (step + 1) * RING_SEGMENTS
            surface.add_vertex(vertices[current_base + ring_index])
            surface.add_vertex(vertices[current_base + next_index])
            surface.add_vertex(vertices[next_base + ring_index])
            surface.add_vertex(vertices[current_base + next_index])
            surface.add_vertex(vertices[next_base + next_index])
            surface.add_vertex(vertices[next_base + ring_index])

    surface.generate_normals()
    var swirl := MeshInstance3D.new()
    swirl.name = node_name
    swirl.mesh = surface.commit()
    swirl.material_override = material
    parent.add_child(swirl)


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
            Color("#ff9a36"), 0.0, 0.16, Color("#ff6b24"), 1.12
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
            Color("#fff0a8"), 0.0, 0.12, Color("#ffe28a"), 1.45
        )
        inner_flame.position = Vector3(0.0, -0.014, 0.059)
        inner_flame.scale = Vector3(0.58, 1.12, 0.58)
        flame.add_child(inner_flame)

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


func _add_strawberries() -> void:
    var berry_material := _make_material(Color("#e94e70"), 0.02, 0.30)
    var seed_material := _make_material(Color("#ffe7ad"), 0.0, 0.42)
    var leaf_material := _make_material(Color("#5f9d70"), 0.0, 0.48)
    var positions: Array[Vector3] = [
        Vector3(-0.78, 0.77, -0.18),
        Vector3(0.78, 0.77, -0.18),
        Vector3(-0.63, 0.77, 0.48),
        Vector3(0.63, 0.77, 0.48),
        Vector3(0.0, 0.77, -0.82),
    ]

    for index in range(positions.size()):
        var berry_root := Node3D.new()
        berry_root.name = "FreshStrawberry_%02d" % index
        berry_root.position = positions[index]
        berry_root.rotation.y = float(index) * 0.85
        cake_root.add_child(berry_root)

        var fruit := _add_sphere(
            berry_root, "StrawberryBody", 0.13, berry_material, Vector3.ZERO
        )
        fruit.scale = Vector3(0.82, 1.08, 0.78)

        for seed_index in range(7):
            var angle := TAU * float(seed_index) / 7.0
            var seed := _add_sphere(
                berry_root,
                "StrawberrySeed_%02d" % seed_index,
                0.012,
                seed_material,
                Vector3(cos(angle) * 0.082, -0.015 + sin(angle * 2.0) * 0.035, 0.092)
            )
            seed.scale = Vector3(0.75, 1.25, 0.55)

        for leaf_index in range(5):
            var leaf_angle := TAU * float(leaf_index) / 5.0
            var leaf := _add_sphere(
                berry_root,
                "StrawberryLeaf_%02d" % leaf_index,
                0.055,
                leaf_material,
                Vector3(cos(leaf_angle) * 0.045, 0.105, sin(leaf_angle) * 0.045)
            )
            leaf.scale = Vector3(1.0, 0.32, 0.58)


func _add_mascot_bear() -> void:
    mascot_root = Node3D.new()
    mascot_root.name = "CuteTeddyMascot"
    mascot_root.position = Vector3(2.10, -0.89, 0.40)
    cake_platform.add_child(mascot_root)

    var fur := _make_material(Color("#c98d62"), 0.0, 0.62)
    var muzzle := _make_material(Color("#fff0d9"), 0.0, 0.52)
    var inner_ear := _make_material(Color("#ef9eaa"), 0.0, 0.48)
    var eye := _make_material(Color("#35232b"), 0.0, 0.25)
    var cheek := _make_material(Color("#f48da5"), 0.0, 0.48)
    var bow := _make_material(Color("#f06f9c"), 0.05, 0.28)
    var nose := _make_material(Color("#4b2d35"), 0.0, 0.25)

    var body := _add_sphere(
        mascot_root, "TeddyBody", 0.22, fur, Vector3(0.0, 0.28, 0.0)
    )
    body.scale = Vector3(1.0, 1.18, 0.82)

    var head := _add_sphere(
        mascot_root, "TeddyHead", 0.24, fur, Vector3(0.0, 0.62, 0.025)
    )
    head.scale = Vector3(1.0, 0.94, 0.86)

    for side in [-1.0, 1.0]:
        var ear := _add_sphere(
            mascot_root, "TeddyEar", 0.105, fur,
            Vector3(side * 0.175, 0.80, 0.015)
        )
        ear.scale = Vector3(1.0, 1.12, 0.62)
        var ear_center := _add_sphere(
            mascot_root, "TeddyInnerEar", 0.060, inner_ear,
            Vector3(side * 0.175, 0.805, 0.078)
        )
        ear_center.scale = Vector3(0.9, 1.0, 0.45)

        _add_sphere(
            mascot_root, "TeddyEye", 0.025, eye,
            Vector3(side * 0.085, 0.655, 0.218)
        )
        var blush := _add_sphere(
            mascot_root, "TeddyCheek", 0.045, cheek,
            Vector3(side * 0.145, 0.535, 0.19)
        )
        blush.scale = Vector3(1.0, 0.62, 0.42)

        var arm := _add_sphere(
            mascot_root, "TeddyArm", 0.105, fur,
            Vector3(side * 0.235, 0.31, 0.035)
        )
        arm.scale = Vector3(0.76, 1.18, 0.76)
        arm.rotation.z = side * -0.38

        var foot := _add_sphere(
            mascot_root, "TeddyFoot", 0.105, muzzle,
            Vector3(side * 0.125, 0.055, 0.075)
        )
        foot.scale = Vector3(1.0, 0.72, 0.78)

    var muzzle_patch := _add_sphere(
        mascot_root, "TeddyMuzzle", 0.105, muzzle, Vector3(0.0, 0.555, 0.215)
    )
    muzzle_patch.scale = Vector3(1.18, 0.78, 0.48)
    _add_sphere(
        mascot_root, "TeddyNose", 0.026, nose, Vector3(0.0, 0.575, 0.265)
    )

    var bow_left := _add_sphere(
        mascot_root, "BowLeft", 0.075, bow, Vector3(-0.075, 0.425, 0.18)
    )
    bow_left.scale = Vector3(1.0, 0.62, 0.52)
    var bow_right := _add_sphere(
        mascot_root, "BowRight", 0.075, bow, Vector3(0.075, 0.425, 0.18)
    )
    bow_right.scale = Vector3(1.0, 0.62, 0.52)
    _add_sphere(
        mascot_root, "BowKnot", 0.040, gold_material_for_mascot(),
        Vector3(0.0, 0.425, 0.215)
    )


func gold_material_for_mascot() -> Material:
    return _make_material(Color("#f7c76b"), 0.45, 0.25, Color("#f7c76b"), 0.12)


func _add_gift_box() -> void:
    var gift_root := Node3D.new()
    gift_root.name = "TinyBirthdayGift"
    gift_root.position = Vector3(-2.08, -0.89, 0.47)
    cake_platform.add_child(gift_root)

    var gift_pink := _make_material(Color("#f28eb0"), 0.08, 0.30)
    var ribbon_gold := _make_material(Color("#f6c56e"), 0.55, 0.22)
    var body_mesh := BoxMesh.new()
    body_mesh.size = Vector3(0.30, 0.27, 0.27)
    var body := MeshInstance3D.new()
    body.name = "GiftBoxBody"
    body.mesh = body_mesh
    body.material_override = gift_pink
    body.position.y = 0.135
    gift_root.add_child(body)

    var lid_mesh := BoxMesh.new()
    lid_mesh.size = Vector3(0.35, 0.065, 0.32)
    var lid := MeshInstance3D.new()
    lid.name = "GiftBoxLid"
    lid.mesh = lid_mesh
    lid.material_override = gift_pink
    lid.position.y = 0.30
    gift_root.add_child(lid)

    var vertical_mesh := BoxMesh.new()
    vertical_mesh.size = Vector3(0.055, 0.34, 0.29)
    var vertical := MeshInstance3D.new()
    vertical.name = "GiftRibbonVertical"
    vertical.mesh = vertical_mesh
    vertical.material_override = ribbon_gold
    vertical.position.y = 0.17
    gift_root.add_child(vertical)

    var horizontal_mesh := BoxMesh.new()
    horizontal_mesh.size = Vector3(0.34, 0.34, 0.055)
    var horizontal := MeshInstance3D.new()
    horizontal.name = "GiftRibbonHorizontal"
    horizontal.mesh = horizontal_mesh
    horizontal.material_override = ribbon_gold
    horizontal.position.y = 0.17
    gift_root.add_child(horizontal)

    for side in [-1.0, 1.0]:
        var loop := _add_sphere(
            gift_root, "GiftBowLoop", 0.09, ribbon_gold,
            Vector3(side * 0.085, 0.39, 0.0)
        )
        loop.scale = Vector3(1.0, 0.48, 0.62)
        loop.rotation.z = side * 0.35


func _add_floating_stars() -> void:
    var star_mesh := _create_star_mesh()
    var colors := [Color("#daa25b"), Color("#82afd6"), Color("#cb80ac")]
    for index in range(72):
        var layer := index % 3
        var star := MeshInstance3D.new()
        star.name = "Starlight_%d_%02d" % [layer, index]
        star.mesh = star_mesh
        var color: Color = colors[index % 5 % colors.size()]
        var material := _make_material(color, 0.0, 0.5)
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        material.cull_mode = BaseMaterial3D.CULL_DISABLED
        star.material_override = material

        var side := -1.0 if index % 2 == 0 else 1.0
        var depth := -4.5 + float(layer) * 2.45
        var spread := 5.4 - float(layer) * 1.07
        var base := Vector3(
            side * rng.randf_range(2.35 if layer > 0 else 0.25, spread),
            rng.randf_range(-0.78, 2.12 + 0.34 * float(2 - layer)),
            depth
        )
        add_child(star)
        star_nodes.append(star)
        star_phases.append(rng.randf_range(0.0, TAU))
        star_base_positions.append(base)
        star_sizes.append(rng.randf_range(0.014, 0.068) * (1.0 if index % 7 else 1.45))


func _create_star_mesh() -> ArrayMesh:
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)

    var points: Array[Vector3] = []
    for index in range(8):
        var angle := -PI * 0.5 + TAU * float(index) / 8.0
        var radius := 0.5 if index % 2 == 0 else 0.10
        points.append(Vector3(cos(angle) * radius, sin(angle) * radius, 0.0))

    for index in range(8):
        surface.add_vertex(Vector3.ZERO)
        surface.add_vertex(points[index])
        surface.add_vertex(points[(index + 1) % 8])

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
    softbox = key_light
    key_light.shadow_enabled = true
    add_child(key_light)

    var fill_light := OmniLight3D.new()
    fill_light.name = "CoolFill"
    fill_light.position = Vector3(-2.8, 2.2, 3.0)
    fill_light.light_color = Color("#9bdcff")
    fill_light.light_energy = 0.37
    fill_light.omni_range = 6.5
    add_child(fill_light)

    var rim_light := OmniLight3D.new()
    rim_light.name = "WarmRim"
    rim_light.position = Vector3(2.8, 1.8, -2.2)
    rim_light.light_color = Color("#ffb76e")
    warm_rim = rim_light
    rim_light.omni_range = 5.5
    add_child(rim_light)

    var front_light := OmniLight3D.new()
    front_light.name = "FrontSoftbox"
    front_light.position = Vector3(0.0, 0.4, 4.0)
    front_light.light_color = Color("#ffffff")
    front_light.light_energy = 0.14
    front_light.omni_range = 5.0
    add_child(front_light)


func _add_camera() -> void:
    var camera := Camera3D.new()
    camera.name = "HeroCamera"
    camera.position = Vector3(0.0, 2.18, 8.35)
    camera.fov = 38.0
    camera.current = true
    add_child(camera)
    camera.look_at(Vector3(0.0, 0.56, 0.0), Vector3.UP)


func _add_birthday_text() -> void:
    birthday_label = Label3D.new()
    birthday_label.name = "BirthdayText"
    birthday_label.text = "Happy Birthday"
    var display_font := SystemFont.new()
    display_font.font_names = PackedStringArray(["Georgia", "DejaVu Serif"])
    display_font.font_italic = true
    birthday_label.font = display_font
    birthday_label.font_size = 104
    birthday_label.pixel_size = 0.00335
    birthday_label.width = 1180.0
    birthday_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    birthday_label.modulate = Color("#f4d7a2")
    birthday_label.outline_size = 0
    birthday_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    birthday_label.position = Vector3(0.0, 2.81, -0.42)
    add_child(birthday_label)


func _add_balloons() -> void:
    var colors: Array[Color] = [
        Color("#f6a9c9"),
        Color("#a8e9f3"),
        Color("#c3b2ff"),
        Color("#ffdc91"),
        Color("#fff0df"),
        Color("#9fe0cf"),
        Color("#e9b8ef"),
        Color("#9ec8ff"),
    ]
    for index in range(BALLOON_COUNT):
        var lane := index % BALLOON_LANES
        var cohort := floorf(float(index) / float(BALLOON_LANES))
        var x := lerpf(-3.9, 3.9, float(lane) / float(BALLOON_LANES - 1))
        x += rng.randf_range(-0.27, 0.27)
        var departure := 0.08 + cohort * 0.63 + rng.randf_range(0.0, 0.52)
        var arrival := minf(departure + rng.randf_range(3.65, 4.35), BALLOON_WAVE_END)
        var root := Node3D.new()
        root.name = "RisingBalloon_%02d" % index
        root.position = Vector3(x, -5.0, rng.randf_range(-2.35, 0.48))
        root.scale = Vector3.ONE * rng.randf_range(0.64, 1.03)
        add_child(root)

        var color: Color = colors[(index * 3 + int(cohort)) % colors.size()]
        var balloon_material := _make_material(color, 0.04, 0.22, color * 0.10, 0.08)

        balloon_material.metallic = 0.40 if index % 3 == 0 else 0.04
        balloon_material.clearcoat_enabled = true
        balloon_material.clearcoat = 0.8
        var body := MeshInstance3D.new()
        body.name = "PearlescentEnvelope"
        var body_mesh := SphereMesh.new()
        body_mesh.radius = 0.40 if index % 3 == 0 else 0.29
        body_mesh.height = 0.94 if index % 3 == 0 else 0.72
        body_mesh.radial_segments = 32
        body_mesh.rings = 20
        body.mesh = body_mesh
        body.material_override = balloon_material
        body.scale = Vector3(0.85, 1.0, 0.86)
        root.add_child(body)

        var knot := _add_sphere(
            root,
            "BalloonKnot",
            0.045,
            balloon_material,
            Vector3(0.0, -body_mesh.height * 0.5, 0.0)
        )
        knot.scale = Vector3(0.72, 0.8, 0.72)

        var tether := Curve3D.new()
        var tail := -0.67 - float(index % 3) * 0.13
        for step in range(22):
            var u := float(step) / 21.0
            tether.add_point(knot.position + Vector3(0.13 * sin(u * TAU + float(index)) * u, tail * u, 0.08 * sin(u * PI)))
        _add_tube(root, "CurledSilkTether", tether, 0.006, _make_material(Color("#ba936b"), 0.42, 0.45))

        balloon_nodes.append(root)
        balloon_base_x.append(x)
        balloon_flights.append(Vector2(departure, arrival))


func _add_stage() -> void:
    var brass := _make_material(Color("#bf8750"), 0.56, 0.29, Color("#b98347"), 0.18)
    var velvet := _make_material(Color("#34223e"), 0.12, 0.59)
    _add_cylinder(cake_platform, "VelvetDais", 2.48, 2.55, 0.17, -0.98, velvet)
    _add_torus(cake_platform, "DaisBrassInlay", 2.45, 2.49, 0.024, -0.907, brass)
    _add_torus(cake_platform, "DaisLowerInlay", 2.49, 2.54, 0.019, -1.016, brass)

    _add_bell_cloche()


func _add_bell_cloche() -> void:
    const RADIUS := 1.82
    const HEIGHT := 3.38
    const BASE_Y := -0.88
    const ROWS := 44
    const SEGMENTS := 96
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for row in range(ROWS + 1):
        var theta := PI * 0.5 * float(row) / float(ROWS)
        for segment in range(SEGMENTS + 1):
            var azimuth := TAU * float(segment) / float(SEGMENTS)
            var radial := Vector3(cos(azimuth), 0.0, sin(azimuth))
            surface.set_normal((radial * sin(theta) / RADIUS + Vector3.UP * cos(theta) / HEIGHT).normalized())
            surface.add_vertex(radial * (RADIUS * sin(theta)) + Vector3.UP * (BASE_Y + HEIGHT * cos(theta)))
    for row in range(ROWS):
        for segment in range(SEGMENTS):
            var a := row * (SEGMENTS + 1) + segment
            var b := a + SEGMENTS + 1
            if row > 0:
                surface.add_index(a)
                surface.add_index(b)
                surface.add_index(a + 1)
            surface.add_index(a + 1)
            surface.add_index(b)
            surface.add_index(b + 1)

    var glass := ShaderMaterial.new()
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;
void fragment() {
    vec3 normal = normalize(NORMAL);
    float facing = clamp(dot(normal, normalize(VIEW)), 0.0, 1.0);
    float fresnel = pow(1.0 - facing, 3.4);
    float warm = exp(-pow((normal.x + 0.77) * 12.0, 2.0))
        * smoothstep(0.08, 0.63, normal.y);
    float cool = exp(-pow((normal.x - 0.88) * 15.0, 2.0))
        * smoothstep(-0.15, 0.45, normal.y);
    vec3 tint = mix(vec3(0.54, 0.70, 0.90), vec3(0.96, 0.76, 0.50),
        smoothstep(-0.10, 0.64, normal.y - normal.x * 0.24));
    ALBEDO = mix(tint, vec3(1.0, 0.87, 0.66), warm * 0.54);
    ALPHA = 0.008 + 0.57 * fresnel + 0.18 * warm + 0.12 * cool;
}
"""
    glass.shader = shader
    var dome := MeshInstance3D.new()
    dome.name = "GoldRimGlassCloche"
    dome.mesh = surface.commit()
    dome.material_override = glass
    dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    cake_platform.add_child(dome)

    var bronze := _make_material(Color("#a16a3d"), 0.60, 0.29, Color("#ab6835"), 0.12)
    var gold := _make_material(Color("#dfae66"), 0.52, 0.22, Color("#d7a364"), 0.25)
    _add_torus(cake_platform, "ClocheBronzeSeat", 1.77, 1.86, 0.03, BASE_Y, bronze)
    _add_torus(cake_platform, "ClocheGoldLip", 1.805, 1.84, 0.016, BASE_Y + 0.029, gold)


func _add_tube(parent: Node3D, title: String, path: Curve3D, radius: float, material: Material) -> void:
    const SIDES := 12
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    var last := path.point_count - 1
    for row in range(path.point_count):
        var center := path.get_point_position(row)
        var tangent := (path.get_point_position(mini(row + 1, last)) -
            path.get_point_position(maxi(row - 1, 0))).normalized()
        var across := tangent.cross(Vector3.BACK).normalized()
        var up := tangent.cross(across)
        for column in range(SIDES + 1):
            var angle := TAU * float(column) / float(SIDES)
            var normal := across * cos(angle) + up * sin(angle)
            surface.set_normal(normal)
            surface.set_uv(Vector2(float(column) / float(SIDES), float(row) / float(last)))
            surface.add_vertex(center + radius * normal)
    for row in range(last):
        for column in range(SIDES):
            var a := row * (SIDES + 1) + column
            var b := a + SIDES + 1
            for vertex in [a, b, a + 1, a + 1, b, b + 1]:
                surface.add_index(vertex)
    var mesh := MeshInstance3D.new()
    mesh.name = title
    mesh.mesh = surface.commit()
    mesh.material_override = material
    parent.add_child(mesh)


func _add_export_backdrop() -> void:
    var quad := QuadMesh.new()
    quad.size = Vector2(22.0, 15.0)

    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float arrival = 0.0;
void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    float bloom = exp(-dot(p * vec2(1.8, 1.6), p * vec2(1.8, 1.6)));
    float rose = exp(-length((p - vec2(-0.43, -0.04)) * vec2(2.3, 1.6)) * 3.2);
    float blue = exp(-length((p - vec2(0.46, 0.11)) * vec2(2.0, 1.5)) * 3.0);
    vec3 night = vec3(0.017, 0.012, 0.041);
    vec3 light = bloom * vec3(0.14, 0.075, 0.17);
    light += rose * vec3(0.18, 0.045, 0.10) + blue * vec3(0.034, 0.085, 0.17);
    float pool = exp(-length((p - vec2(0.0, 0.35)) * vec2(2.0, 5.5)) * 2.5);
    ALBEDO = night + arrival * (light + pool * vec3(0.10, 0.047, 0.078));
}
"""
    var shader_material := ShaderMaterial.new()
    shader_material.shader = shader

    export_backdrop = MeshInstance3D.new()
    export_backdrop.name = "ExportOnlyGradientBackdrop"
    export_backdrop.mesh = quad
    backdrop_material = shader_material
    export_backdrop.material_override = shader_material
    export_backdrop.position = Vector3(0.0, -0.56, -5.8)
    export_backdrop.visible = export_mode
    add_child(export_backdrop)


func _setup_audio() -> void:
    music_player = AudioStreamPlayer.new()
    music_player.name = "BackgroundMusic"
    music_player.bus = "Master"
    add_child(music_player)

    sfx_player = AudioStreamPlayer.new()
    sfx_player.name = "SparkleSound"
    sfx_player.volume_db = -5.0
    sfx_player.stream = _make_sparkle_sound()
    add_child(sfx_player)


func _apply_startup_settings() -> void:
    var env_speed := OS.get_environment("MAGIC_DESKTOP_SPEED")
    if not env_speed.is_empty() and env_speed.is_valid_float():
        rotation_speed_degrees = clampf(float(env_speed), 0.0, 120.0)

    var env_text := OS.get_environment("MAGIC_DESKTOP_TEXT").strip_edges()
    if not env_text.is_empty():
        birthday_label.text = env_text.left(32)

    var env_volume := OS.get_environment("MAGIC_DESKTOP_MUSIC_VOLUME")
    if not env_volume.is_empty() and env_volume.is_valid_float():
        _set_music_volume(float(env_volume))

    var music_path := OS.get_environment("MAGIC_DESKTOP_MUSIC")
    if not music_path.is_empty():
        _load_music_file(music_path)


func _load_music_file(path: String) -> void:
    if not FileAccess.file_exists(path):
        push_warning("Music file does not exist: " + path)
        return

    var extension := path.get_extension().to_lower()
    var stream: AudioStream

    match extension:
        "mp3":
            var mp3 := AudioStreamMP3.load_from_file(path)
            if mp3 == null:
                push_warning("Could not decode MP3: " + path)
                return
            mp3.loop = true
            stream = mp3
        "ogg":
            var ogg := AudioStreamOggVorbis.load_from_file(path)
            if ogg == null:
                push_warning("Could not decode OGG: " + path)
                return
            ogg.loop = true
            stream = ogg
        "wav":
            var wav := AudioStreamWAV.load_from_file(path)
            if wav == null:
                push_warning("Could not decode WAV: " + path)
                return
            wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
            wav.loop_begin = 0
            var bytes_per_frame := 4 if wav.stereo else 2
            wav.loop_end = int(wav.data.size() / bytes_per_frame)
            stream = wav
        _:
            push_warning("Supported music formats are MP3, OGG and WAV.")
            return

    music_player.stop()
    music_player.stream = stream
    music_player.stream_paused = false
    print("Loaded background music: ", path)


func _set_music_volume(value: float) -> void:
    if not is_instance_valid(music_player):
        return
    var volume := clampf(value, 0.0, 1.0)
    music_player.volume_db = -80.0 if volume <= 0.001 else linear_to_db(volume)


func _make_sparkle_sound() -> AudioStreamWAV:
    const SAMPLE_RATE := 22050
    const DURATION := 0.62
    var sample_count := int(SAMPLE_RATE * DURATION)
    var pcm := PackedByteArray()

    for index in range(sample_count):
        var time := float(index) / float(SAMPLE_RATE)
        var envelope := pow(maxf(0.0, 1.0 - time / DURATION), 2.8)
        var note := sin(TAU * 880.0 * time) * 0.46
        note += sin(TAU * 1320.0 * time) * 0.30
        note += sin(TAU * 1760.0 * time) * 0.18
        note += sin(TAU * 2093.0 * maxf(0.0, time - 0.08)) * 0.08
        var sample_value := clampf(note * envelope * 0.24, -1.0, 1.0)
        var sample_int := int(sample_value * 32767.0)
        pcm.append(sample_int & 0xff)
        pcm.append((sample_int >> 8) & 0xff)

    var stream := AudioStreamWAV.new()
    stream.format = AudioStreamWAV.FORMAT_16_BITS
    stream.mix_rate = SAMPLE_RATE
    stream.stereo = false
    stream.data = pcm
    return stream


func _play_sparkle_sound() -> void:
    if is_instance_valid(sfx_player):
        sfx_player.stop()
        sfx_player.play()


func _setup_mouse_region() -> void:
    var polygon := PackedVector2Array()
    var center := Vector2(WINDOW_WIDTH * 0.5, WINDOW_HEIGHT * 0.50)
    for index in range(48):
        var angle := TAU * float(index) / 48.0
        polygon.append(center + Vector2(cos(angle) * 535.0, sin(angle) * 295.0))
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
    if export_mode:
        return
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
            var new_text := str(command.get("value", "Happy Birthday")).strip_edges()
            var display_text := new_text.left(32) if not new_text.is_empty() else "Happy Birthday"
            if is_instance_valid(birthday_label):
                birthday_label.text = display_text
        "set_music":
            _load_music_file(str(command.get("path", "")))
        "play_music":
            if is_instance_valid(music_player) and music_player.stream != null:
                music_player.play()
        "pause_music":
            if is_instance_valid(music_player):
                music_player.stream_paused = true
        "stop_music":
            if is_instance_valid(music_player):
                music_player.stop()
        "set_music_volume":
            _set_music_volume(float(command.get("value", 0.55)))
        "play_sfx":
            _play_sparkle_sound()
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
    _play_sparkle_sound()


func _input(event: InputEvent) -> void:
    if export_mode or passthrough_enabled:
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
