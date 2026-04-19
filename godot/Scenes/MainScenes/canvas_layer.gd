extends CanvasLayer

@onready var info_panel: InfoPanel = $"InfoPanel"
@onready var particle_parent = $"SubViewport/InspectNodeParent/ParticleLocation"
@onready var object3D_parent = $"SubViewport/InspectNodeParent/Object3DLocation"
@onready var inspect_node_parent: Node3D = $"SubViewport/InspectNodeParent"
@onready var camera3D = $SubViewport/Camera3D
@onready var blur_background = $BlurBakground
@onready var closeup = $ObjectCloseup
@onready var welcome_overlay = $WelcomeOverlay
@onready var explore_button: Button = %ExploreButton
@onready var reticle = $Reticle
@onready var credits_button: Button = %CreditsButton
@onready var credits_overlay: Control = $WelcomeOverlay/CreditsOverlay
@onready var credits_backdrop: ColorRect = $WelcomeOverlay/CreditsOverlay/Backdrop
@onready var back_button: Button = %BackButton
@onready var sub_viewport: SubViewport = $SubViewport
@onready var welcome_margin: MarginContainer = $WelcomeOverlay/MarginContainer
@onready var credits_panel: PanelContainer = $WelcomeOverlay/CreditsOverlay/PanelContainer
@onready var controls_label: RichTextLabel = $WelcomeOverlay/MarginContainer/VBoxContainer/RichTextLabel3
@onready var cta_label: RichTextLabel = $WelcomeOverlay/MarginContainer/VBoxContainer/RichTextLabel4
@onready var welcome_desc: RichTextLabel = $WelcomeOverlay/MarginContainer/VBoxContainer/RichTextLabel
@onready var en_button: Button = %EnButton
@onready var pt_button: Button = %PtButton
@onready var credits_label: RichTextLabel = $WelcomeOverlay/CreditsOverlay/PanelContainer/VBoxContainer/ScrollContainer/RichTextLabel
@onready var _fps_player = $"../Basic FPS Player"

var _prev_reticle_visible: bool
var _portrait := false
var _touch_device := false
var _is_mobile_web := false
var _exploring := false
var _edge_overlay: ColorRect
var _edge_material: ShaderMaterial
var _smooth_edge_dir := Vector2.ZERO
var _smooth_edge_intensity := 0.0

var _cursor_texture = preload("res://Assets/Particles/halo_small.png")
var _edge_shader = preload("res://Shaders/edge_rotation.gdshader")

var _lang_selected_style: StyleBoxFlat
var _lang_unselected_style: StyleBoxFlat

const _WELCOME_DESC := {
	"en": "[center]An interactive visualization of the biodiversity behind [b]Venn Canteen[/b] in Porto, Portugal, exploring the regenerative farms and foragers who supply the restaurant.[/center]",
	"pt": "[center]Uma visualização interativa da biodiversidade por detrás do [b]Venn Canteen[/b] no Porto, Portugal, explorando as quintas regenerativas e catadores que abastecem o restaurante.[/center]"
}
const _WELCOME_CONTROLS_MOUSE := {
	"en": "[center][b]Controls[/b]\nMove your mouse to look around  ·  Click a species to learn more[/center]",
	"pt": "[center][b]Controlos[/b]\nMova o rato para explorar  ·  Clique numa espécie para saber mais[/center]"
}
const _WELCOME_CONTROLS_TOUCH := {
	"en": "[center][b]Controls[/b]\nDrag to look around  ·  Hold a species to learn more[/center]",
	"pt": "[center][b]Controlos[/b]\nArraste para explorar  ·  Segure numa espécie para saber mais[/center]"
}
const _WELCOME_CTA_MOUSE := {
	"en": "[center]— Click anywhere to explore —[/center]",
	"pt": "[center]— Clique em qualquer lado para explorar —[/center]"
}
const _WELCOME_CTA_TOUCH := {
	"en": "[center]— Tap anywhere to explore —[/center]",
	"pt": "[center]— Toque em qualquer lado para explorar —[/center]"
}
const _ABOUT_LABEL := {"en": "About", "pt": "Sobre"}
const _CLOSE_LABEL := {"en": "Close", "pt": "Fechar"}
const _CREDITS_TEXT := {
"en": """[center][font_size=20][b]About EAT.BITZ[/b][/font_size][/center]

EAT.BITZ is a three-part artistic experience for exploring biodiversity of the kitchen.

Through an ingredient oracle reading, a kaleidoscope viewer, and an interactive digital platform, visitors get an intimate view of the ecological multitudes behind various dishes served in the restaurant.

EAT.BITZ uses data collected by the [b]BITZ[/b] (Biodiversity in Transition Zones) digital tool — a participatory platform for place-based species quests that explore and document biodiversity in various landscapes.

For EAT.BITZ: Venn Canteen, BITZ data was collected from local regenerative farms and foragers who supply the restaurant. This data was translated into an interactive datascape and set of bespoke oracle cards that illustrate the biodiversity behind Venn Canteen's menu and mission. Through EAT.BITZ: Venn Canteen, visitors can learn about key ingredients and feel connected to the wild species that support the agroecological systems of Northern Portugal.


[center][color=#666666]────────────────────[/color][/center]


[center][font_size=20][b]Credits[/b][/font_size][/center]

[b]Bernat Cuní[/b]
[color=#aaaaaa]Artist and digital craftsman working with emerging technologies from a post-capitalist lens.[/color]

[b]Ruben Gres[/b]
[color=#aaaaaa]Machine learning engineer turned creative technologist. Specializes in generative AI and interactive systems, focused on bringing high-level concepts to everyone through playful experiences.[/color]

[b]Genomic Gastronomy[/b]
[color=#aaaaaa]Artist-led think tank examining the biotechnologies and biodiversity of human food systems. Their mission: map food controversies, prototype alternative culinary futures, and imagine a more just, biodiverse & beautiful food system.[/color]

[b]Venn Canteen[/b]
[color=#aaaaaa]100% plant-based restaurant in Porto's Baixa district. Founded in 2023 by Monika Bloch, Snider Rodrigues, and Julian Fernandes. Works closely with small-scale regenerative farms and foragers across Portugal.[/color]

[b]ST3ER[/b]
[color=#aaaaaa]Scaling Twin Transition in Tourism by harnessing the Experience Economy for greater Resilience.

This Project has indirectly received funding from the European Union's COSME - SMP programme, via an Open Call issued and executed under project ST3ER (grant agreement No 101121592)[/color]
""",
"pt": """[center][font_size=20][b]Sobre o EAT.BITZ[/b][/font_size][/center]

EAT.BITZ é uma experiência artística em três partes para explorar a biodiversidade da cozinha.

Através de uma leitura oracular de ingredientes, um visualizador caleidoscópico e uma plataforma digital interativa, os visitantes têm uma visão íntima das multidões ecológicas por detrás de vários pratos servidos no restaurante.

EAT.BITZ usa dados recolhidos pela ferramenta digital [b]BITZ[/b] (Biodiversidade em Zonas de Transição) — uma plataforma participativa para missões de espécies baseadas no lugar que exploram e documentam a biodiversidade em várias paisagens.

Para o EAT.BITZ: Venn Canteen, os dados BITZ foram recolhidos em quintas regenerativas locais e catadores que abastecem o restaurante. Estes dados foram traduzidos num datascape interativo e num conjunto de cartas oraculares feitas à medida que ilustram a biodiversidade por detrás do menu e da missão do Venn Canteen. Através do EAT.BITZ: Venn Canteen, os visitantes podem conhecer ingredientes-chave e sentir-se ligados às espécies selvagens que suportam os sistemas agroecológicos do norte de Portugal.


[center][color=#666666]────────────────────[/color][/center]


[center][font_size=20][b]Créditos[/b][/font_size][/center]

[b]Bernat Cuní[/b]
[color=#aaaaaa]Artista e artesão digital que trabalha com tecnologias emergentes a partir de uma perspetiva pós-capitalista.[/color]

[b]Ruben Gres[/b]
[color=#aaaaaa]Engenheiro de machine learning reconvertido em tecnólogo criativo. Especializa-se em IA generativa e sistemas interativos, focado em trazer conceitos de alto nível a todos através de experiências lúdicas.[/color]

[b]Genomic Gastronomy[/b]
[color=#aaaaaa]Think tank liderado por artistas que examina as biotecnologias e a biodiversidade dos sistemas alimentares humanos. A sua missão: mapear controvérsias alimentares, prototipar futuros culinários alternativos e imaginar um sistema alimentar mais justo, biodiverso e belo.[/color]

[b]Venn Canteen[/b]
[color=#aaaaaa]Restaurante 100% plant-based no bairro da Baixa do Porto. Fundado em 2023 por Monika Bloch, Snider Rodrigues e Julian Fernandes. Trabalha de perto com pequenas quintas regenerativas e catadores em todo Portugal.[/color]

[b]ST3ER[/b]
[color=#aaaaaa]Escalando a Dupla Transição no Turismo aproveitando a Economia da Experiência para maior Resiliência.

Este Projeto recebeu indiretamente financiamento do programa COSME - SMP da União Europeia, através de um Open Call emitido e executado no âmbito do projeto ST3ER (acordo de subvenção n.º 101121592)[/color]
"""
}

const INSPECT_MAX_TILT_X_DEG := 15.0
const INSPECT_MAX_TILT_Y_DEG := 15.0
const INSPECT_TILT_SMOOTH_SPEED := 6.0

const _BASE_FONT_TITLE := 54
const _BASE_FONT_DESC := 17
const _BASE_FONT_CONTROLS := 15
const _BASE_FONT_CTA := 22
const _BASE_FONT_FOOTER := 13
const _BASE_FONT_BUTTON := 16
const _BASE_FONT_LANG := 18
const _BASE_FONT_CLOSE := 15
const _BASE_FONT_CREDITS := 14

func _ready() -> void:
	_touch_device = DisplayServer.is_touchscreen_available()
	_is_mobile_web = OS.has_feature("web_android") or OS.has_feature("web_ios")

	if _is_mobile_web:
		_apply_mobile_perf_tweaks()

	info_panel.focused.connect(_on_node_focused)
	info_panel.closed.connect(_on_closed)
	info_panel.opened.connect(_on_info_panel_opened)
	explore_button.pressed.connect(_on_explore_button_pressed)
	credits_button.pressed.connect(_on_credits_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)
	credits_backdrop.gui_input.connect(_on_credits_backdrop_input)
	en_button.pressed.connect(func(): _set_locale("en"))
	pt_button.pressed.connect(func(): _set_locale("pt"))
	var uk_flag: Texture2D = load("res://Assets/Flags/uk.svg")
	var pt_flag: Texture2D = load("res://Assets/Flags/pt.svg")
	en_button.text = ""
	pt_button.text = ""
	en_button.icon = uk_flag
	pt_button.icon = pt_flag
	en_button.expand_icon = true
	pt_button.expand_icon = true
	blur_background.visible = false
	closeup.visible = false
	reticle.visible = false
	welcome_overlay.visible = true

	_lang_selected_style = StyleBoxFlat.new()
	_lang_selected_style.bg_color = Color(1, 1, 1, 1)
	_lang_selected_style.set_border_width_all(2)
	_lang_selected_style.border_color = Color(1, 1, 1, 1)
	_lang_selected_style.set_corner_radius_all(6)

	_lang_unselected_style = StyleBoxFlat.new()
	_lang_unselected_style.bg_color = Color(0, 0, 0, 0.92)
	_lang_unselected_style.set_border_width_all(2)
	_lang_unselected_style.border_color = Color(1, 1, 1, 1)
	_lang_unselected_style.set_corner_radius_all(6)

	_setup_edge_overlay()
	_set_locale("en")

	get_viewport().size_changed.connect(_update_layout)
	_update_layout.call_deferred()

func _set_locale(locale: String) -> void:
	TranslationServer.set_locale(locale)
	_update_welcome_texts(locale)
	_update_language_buttons(locale)
	info_panel.sync_language(locale)

func _update_welcome_texts(locale: String) -> void:
	welcome_desc.text = _WELCOME_DESC[locale]
	if _touch_device:
		controls_label.text = _WELCOME_CONTROLS_TOUCH[locale]
		cta_label.text = _WELCOME_CTA_TOUCH[locale]
	else:
		controls_label.text = _WELCOME_CONTROLS_MOUSE[locale]
		cta_label.text = _WELCOME_CTA_MOUSE[locale]
	credits_button.text = _ABOUT_LABEL[locale]
	back_button.text = _CLOSE_LABEL[locale]
	credits_label.text = _CREDITS_TEXT[locale]

func _update_language_buttons(locale: String) -> void:
	var en_selected := locale == "en"
	en_button.add_theme_stylebox_override("normal", _lang_selected_style if en_selected else _lang_unselected_style)
	pt_button.add_theme_stylebox_override("normal", _lang_unselected_style if en_selected else _lang_selected_style)

func _on_explore_button_pressed() -> void:
	_exploring = true
	_fps_player.sensitivity_scale = 1.0
	if not _touch_device:
		_enter_explore_mode()
	else:
		_fps_player.set_gyro_active(true)
	reticle.visible = false
	welcome_overlay.visible = false

func _update_layout() -> void:
	var vp_size = get_viewport().get_visible_rect().size
	var new_portrait = vp_size.y > vp_size.x

	if new_portrait != _portrait:
		_portrait = new_portrait
		blur_background.visible = false
		closeup.visible = false
		info_panel.portrait_mode = _portrait

	_update_inspection_layout(vp_size)
	_update_welcome_layout(vp_size)
	_update_info_panel_scale(vp_size)

func _update_info_panel_scale(vp_size: Vector2) -> void:
	var scale := 1.0
	if _portrait:
		scale = clamp(vp_size.x / 300.0, 1.8, 3.0)
	info_panel.set_font_scale(scale)

func _update_inspection_layout(vp_size: Vector2) -> void:
	var render_scale := 0.7 if _is_mobile_web else 1.0
	if _portrait:
		closeup.anchor_left = 0.0
		closeup.anchor_top = 0.0
		closeup.anchor_right = 1.0
		closeup.anchor_bottom = 0.4
		closeup.offset_left = 0
		closeup.offset_top = 0
		closeup.offset_right = 0
		closeup.offset_bottom = 0
		sub_viewport.size = Vector2i(int(vp_size.x * render_scale), int(vp_size.y * 0.4 * render_scale))
	else:
		var closeup_width = min(813.0, vp_size.x * 0.6)
		closeup.anchor_left = 0.0
		closeup.anchor_top = 0.0
		closeup.anchor_right = 0.0
		closeup.anchor_bottom = 1.0
		closeup.offset_left = 0
		closeup.offset_top = 0
		closeup.offset_right = closeup_width
		closeup.offset_bottom = 0
		sub_viewport.size = Vector2i(int(closeup_width * render_scale), int(vp_size.y * render_scale))

func _update_welcome_layout(vp_size: Vector2) -> void:
	var margin_h: float
	var margin_v_top: float
	var margin_v_bottom: float

	if _portrait:
		var portrait_scale = clamp(vp_size.x / 420.0, 1.4, 2.4)
		margin_h = vp_size.x * 0.05
		margin_v_top = vp_size.y * 0.03
		margin_v_bottom = max(vp_size.y * 0.10, 80.0 * portrait_scale)
	else:
		var max_content_width := 560.0
		margin_h = max((vp_size.x - max_content_width) / 2.0, vp_size.x * 0.05)
		margin_v_top = vp_size.y * 0.05
		margin_v_bottom = vp_size.y * 0.10

	welcome_margin.anchor_left = 0.0
	welcome_margin.anchor_top = 0.0
	welcome_margin.anchor_right = 1.0
	welcome_margin.anchor_bottom = 1.0
	welcome_margin.offset_left = margin_h
	welcome_margin.offset_top = margin_v_top
	welcome_margin.offset_right = -margin_h
	welcome_margin.offset_bottom = -margin_v_bottom

	if _portrait:
		credits_panel.anchor_left = 0.0
		credits_panel.anchor_top = 0.0
		credits_panel.anchor_right = 1.0
		credits_panel.anchor_bottom = 1.0
		credits_panel.offset_left = vp_size.x * 0.03
		credits_panel.offset_top = vp_size.y * 0.03
		credits_panel.offset_right = -vp_size.x * 0.03
		credits_panel.offset_bottom = -vp_size.y * 0.05
	else:
		var pw = min(380.0, vp_size.x * 0.4)
		var ph = min(320.0, vp_size.y * 0.45)
		credits_panel.anchor_left = 0.5
		credits_panel.anchor_top = 0.5
		credits_panel.anchor_right = 0.5
		credits_panel.anchor_bottom = 0.5
		credits_panel.offset_left = -pw
		credits_panel.offset_top = -ph
		credits_panel.offset_right = pw
		credits_panel.offset_bottom = ph

	_update_font_scale(vp_size)

func _apply_rtl_font_size(rtl: RichTextLabel, base_size: int, scale: float) -> void:
	var size := int(base_size * scale)
	rtl.add_theme_font_size_override("normal_font_size", size)
	rtl.add_theme_font_size_override("bold_font_size", size)
	rtl.add_theme_font_size_override("italics_font_size", size)
	rtl.add_theme_font_size_override("bold_italics_font_size", size)
	rtl.add_theme_font_size_override("mono_font_size", size)
	rtl.fit_content = true

func _update_font_scale(vp_size: Vector2) -> void:
	var scale := 1.0
	if _portrait:
		scale = clamp(vp_size.x / 420.0, 1.4, 2.4)

	var title: RichTextLabel = $WelcomeOverlay/MarginContainer/VBoxContainer/Title
	_apply_rtl_font_size(title, _BASE_FONT_TITLE, scale)
	_apply_rtl_font_size(welcome_desc, _BASE_FONT_DESC, scale)
	_apply_rtl_font_size(controls_label, _BASE_FONT_CONTROLS, scale)
	_apply_rtl_font_size(cta_label, _BASE_FONT_CTA, scale)

	var footer: RichTextLabel = $WelcomeOverlay/MarginContainer/VBoxContainer/RichTextLabel2
	_apply_rtl_font_size(footer, _BASE_FONT_FOOTER, scale)

	credits_button.add_theme_font_size_override("font_size", int(_BASE_FONT_BUTTON * scale))
	back_button.add_theme_font_size_override("font_size", int(_BASE_FONT_CLOSE * scale))
	en_button.add_theme_font_size_override("font_size", int(_BASE_FONT_LANG * scale))
	pt_button.add_theme_font_size_override("font_size", int(_BASE_FONT_LANG * scale))
	_apply_rtl_font_size(credits_label, _BASE_FONT_CREDITS, scale)

	var lang_toggle: HBoxContainer = $WelcomeOverlay/LanguageToggle
	var bottom_margin := -18.0 * scale
	var btn_h := 40.0 * scale
	var lang_w := 54.0 * scale
	en_button.custom_minimum_size = Vector2(lang_w, btn_h)
	pt_button.custom_minimum_size = Vector2(lang_w, btn_h)
	lang_toggle.offset_left = 20.0 * scale
	lang_toggle.offset_top = bottom_margin - btn_h
	lang_toggle.offset_right = lang_toggle.offset_left + (lang_w * 2 + 8 * scale)
	lang_toggle.offset_bottom = bottom_margin

	var about_w := 150.0 * scale
	credits_button.offset_left = -about_w - 20.0 * scale
	credits_button.offset_top = bottom_margin - btn_h
	credits_button.offset_right = -20.0 * scale
	credits_button.offset_bottom = bottom_margin

func _apply_mobile_perf_tweaks() -> void:
	get_tree().root.scaling_3d_scale = 0.7
	var env: Environment = camera3D.environment
	if env:
		env.glow_enabled = false
		env.ssao_enabled = false

func _setup_edge_overlay() -> void:
	_edge_material = ShaderMaterial.new()
	_edge_material.shader = _edge_shader
	_edge_overlay = ColorRect.new()
	_edge_overlay.material = _edge_material
	_edge_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_edge_overlay.color = Color.WHITE
	_edge_overlay.visible = false
	add_child(_edge_overlay)
	move_child(_edge_overlay, 0)

func _set_custom_cursor() -> void:
	var hotspot = _cursor_texture.get_size() / 2.0
	Input.set_custom_mouse_cursor(_cursor_texture, Input.CURSOR_ARROW, hotspot)

func _enter_explore_mode() -> void:
	_set_custom_cursor()
	_fps_player.set_edge_rotation_active(true)
	_edge_overlay.visible = true

func _exit_explore_mode() -> void:
	Input.set_custom_mouse_cursor(null)
	_fps_player.set_edge_rotation_active(false)
	_edge_overlay.visible = false
	_smooth_edge_dir = Vector2.ZERO
	_smooth_edge_intensity = 0.0

func _on_info_panel_opened() -> void:
	if _exploring and not _touch_device:
		_exit_explore_mode()

func _update_edge_overlay(delta: float) -> void:
	if not _edge_overlay.visible:
		return
	var target_dir = _fps_player.edge_direction
	var target_int = _fps_player.edge_intensity
	_smooth_edge_dir = _smooth_edge_dir.lerp(target_dir, clamp(delta * 10.0, 0.0, 1.0))
	_smooth_edge_intensity = lerpf(_smooth_edge_intensity, target_int, clamp(delta * 10.0, 0.0, 1.0))
	_edge_material.set_shader_parameter("edge_input", _smooth_edge_dir)
	_edge_material.set_shader_parameter("intensity", _smooth_edge_intensity)

func _return_to_landing() -> void:
	_exploring = false
	if not _touch_device:
		_exit_explore_mode()
	else:
		_fps_player.set_gyro_active(false)
	reticle.visible = false
	welcome_overlay.visible = true

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if credits_overlay.visible:
			_close_credits()
			get_viewport().set_input_as_handled()
		elif closeup.visible:
			info_panel.slide_out()
			get_viewport().set_input_as_handled()
		elif _exploring:
			_return_to_landing()
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_update_edge_overlay(delta)

	var closeup_rect = closeup.get_global_rect()
	var mouse_pos := get_viewport().get_mouse_position()
	var is_hovering_closeup = closeup.visible and closeup_rect.has_point(mouse_pos)

	var target_tilt_x_deg := 0.0
	var target_tilt_y_deg := 0.0

	if is_hovering_closeup:
		var normalized_x = (
			(mouse_pos.x - closeup_rect.position.x) / closeup_rect.size.x
		) * 2.0 - 1.0
		var normalized_y = (
			(mouse_pos.y - closeup_rect.position.y) / closeup_rect.size.y
		) * 2.0 - 1.0
		target_tilt_y_deg = clamp(normalized_x, -1.0, 1.0) * INSPECT_MAX_TILT_Y_DEG
		target_tilt_x_deg = clamp(normalized_y, -1.0, 1.0) * INSPECT_MAX_TILT_X_DEG

	var target_basis = camera3D.global_transform.basis
	target_basis = target_basis * Basis(Vector3.RIGHT, deg_to_rad(target_tilt_x_deg))
	target_basis = target_basis * Basis(Vector3.UP, deg_to_rad(target_tilt_y_deg))

	var current_quat = inspect_node_parent.global_transform.basis.get_rotation_quaternion()
	var target_quat = target_basis.orthonormalized().get_rotation_quaternion()
	var blend = clamp(delta * INSPECT_TILT_SMOOTH_SPEED, 0.0, 1.0)
	var next_quat := current_quat.slerp(target_quat, blend)
	inspect_node_parent.global_transform.basis = Basis(next_quat)

func _on_node_focused(object: Node3D):
	if not object:
		return

	for child in object3D_parent.get_children():
		child.queue_free()

	for child in particle_parent.get_children():
		child.queue_free()

	var duplicated_object = object.duplicate()

	if duplicated_object is BitzCompanion:
		object3D_parent.add_child(duplicated_object)
		duplicated_object.billboard_camera = false
		duplicated_object.lifetime = 99999
		duplicated_object.texture_res = "medium" if _is_mobile_web else "large"
		duplicated_object._fetch()
	else:
		particle_parent.add_child(duplicated_object)

	duplicated_object.position = Vector3.ZERO
	duplicated_object.scale = Vector3.ONE
	duplicated_object.rotation = Vector3.ZERO
	duplicated_object.target = null
	duplicated_object.is_highlighted = false

	blur_background.visible = true
	closeup.visible = true

func _on_closed():
	blur_background.visible = false
	closeup.visible = false
	if _exploring and not _touch_device:
		_enter_explore_mode()

func _on_credits_button_pressed() -> void:
	_prev_reticle_visible = reticle.visible
	if _exploring and not _touch_device:
		_exit_explore_mode()
	credits_overlay.visible = true
	credits_button.visible = false
	reticle.visible = false

func _on_credits_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_credits()

func _on_back_button_pressed() -> void:
	_close_credits()

func _close_credits() -> void:
	credits_overlay.visible = false
	credits_button.visible = true
	if _exploring and not _touch_device:
		_enter_explore_mode()
	reticle.visible = _prev_reticle_visible
