# Dungeondraft mod to add ability to search for walls, terrain and patterns in the tool panel
var script_class = "tool"

# Variables
var tool_panel
var tags_panel
var ui_config = {}
var swap_scroll = null
var store_swap_index = -1
var swap_vbox = null
var panel = null
var rh_panel_box = null
var rh_panel_preset_label = null
var swap_list_location = ""

var list_of_swaps = []

# Pack replacement state. These mappings are intentionally kept separate from
# the normal preset data until PresetsDropdown support is added.
var pack_replacement_mappings = []
var pack_highlighted_nodes = []
var pack_result_list = null
var pack_status_label = null
var pack_from_dropdown = null
var pack_to_dropdown = null
var pack_asset_catalog = {}
var pack_scope_dropdown = null
var pack_result_entries = []
var pack_selected_result_index = -1
var pack_found_ids = []
var pack_scope_all_levels = false
var pack_focus_pixel_spinbox = null
var pack_result_cycle_indices = {}
var pack_selected_single_entry = null

# Absolute map-size reference used by the camera focus calculation.
# Dungeondraft map coordinates are expected to use pixels/world units, where
# one visible grid cell normally corresponds to 256 world units.
var pack_map_width_spinbox = null
var pack_map_height_spinbox = null
var pack_map_size_override_hbox = null
var pack_map_size_status_label = null

const DUNGEONDRAFT_GRID_CELL_SIZE = 256.0

const ASSET_TYPES = {"Objects": "objects", "Object Custom Colours": "object_colours", "Paths": "paths", "Terrain": "terrain", "Patterns": "pattern_shapes", "Environment Light": "environment_light", "Lights": "lights",  "Walls": "walls", "Portals": "portals"}
const DEFAULT_PRESET_DATA = {"objects": [], "paths": [], "lights": [], "pattern_shapes": [], "terrain": [], "object_colours": [], "walls": [], "portals": [], "environment_light": []}

const TOOL_TYPE_LOOKUP = {"objects": "ObjectTool", "paths": "PathTool", "pattern_shapes": "PatternShapeTool", "walls": "WallTool", "portals": "PortalTool", "terrain": "TerrainBrush", "lights": "LightTool"}
const RH_TOOL_TYPES = ["PatternShapeTool", "TerrainBrush", "WallTool", "PortalTool"]
const HIDE_SPINBOX_ASSET_LIST = ["pattern_shapes","terrain","walls","portals"]
const TEXTURE_SWAP_ASSETS = ["objects", "paths", "pattern_shapes", "terrain", "walls", "portals"]
const COLOUR_SWAP_ASSETS = ["object_colours", "lights", "environment_light"]

var presetsdropdown = null
var export_import_vbox = null

var timer = null

#########################################################################################################
##
## LOGGING FUNCTIONS
##
#########################################################################################################

const ENABLE_LOGGING = true
const LOGGING_LEVEL = 0

func outputlog(msg,level=0):
	if ENABLE_LOGGING:
		if level <= LOGGING_LEVEL:
			printraw("(%d) <SwapAssets>: " % OS.get_ticks_msec())
			print(msg)
	else:
		pass

#########################################################################################################
##
## UTILITY FUNCTIONS
##
#########################################################################################################

# Function to get the texture of a node based on tool_type
func get_asset_texture(node, tool_type: String):
	var texture = null

	match tool_type:
		"ObjectTool","ScatterTool","WallTool","PortalTool","objects","portals","walls":
			texture = node.Texture
		"PathTool", "LightTool","paths","lights":
			texture = node.get_texture()
		"PatternShapeTool","pattern_shapes":
			texture = node._Texture
		"RoofTool","roofs":
			texture = node.TilesTexture
		_:
			return null

	return texture

# Find the width scale of a path
func find_path_width_scale(path) -> float:

	if path == null: return 1.0

	if not Global.World.HasNodeID(path.get_meta("node_id")):
		return -1.0

	# Get the path metadata - surely there is a better way to do this
	var path_dictionary = path.Save(true)
	var texture_height = get_asset_texture(path, "paths").get_height()

	return float(path_dictionary["width"]) / texture_height

# Loads an image texture from ResourceLoader if that is possible or direct from a file if not
func safe_load_texture(path: String) -> Texture:

	outputlog("safe_load_texture: " + str(path),2)

	var texture = null
	if ResourceLoader.exists(path):
		texture = ResourceLoader.load(path)
	else:
		var file = File.new()
		if file.file_exists(path):
			texture = load_runtime_image(path)
			if texture != null:
				texture.resource_path = path

	return texture

# Load an image from a file
func load_runtime_image(path: String) -> Texture:
	var img := Image.new()
	if img.load(path) != OK:
		return null

	var tex := ImageTexture.new()
	tex.create_from_image(img)
	return tex

# Function to set a property on an object but block any signals for it
func set_property_but_block_signals(obj: Object, property: String, value):

	outputlog("set_property_but_block_signals: " + str(obj) + " property: " + str(property) + " value: " + str(value),3)

	obj.set_block_signals(true)
	if obj.get(property) != null:
		obj.set(property,value)
	obj.set_block_signals(false)

# Function to take a string and add a space before any internal Capital letter
func split_camel_case(text: String) -> String:
	var result := ""
	for _i in text.length():
		if _i > 0 and text[_i] in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
			result += " "
		result += text[_i]
	return result


#########################################################################################################
##
## CORE FUNCTIONS
##
#########################################################################################################

# Validate that the data from a configuration file is correctly formatted for use (which is should be if it is a saved file)
func validate_swap_config_data(data):
	# Only configurations that are structurally complete and reference
	# resources that can actually be loaded are allowed into valid_list.
	# Invalid entries are archived by PresetsDropdown and therefore never
	# reach SwapController during startup. This is important because a saved
	# preset can outlive the asset packs/map it was created with.
	if not data is Dictionary:
		return false

	if data.has("from_texture_path") or data.has("to_texture_path"):
		if not data.has("from_texture_path") or not data.has("to_texture_path"):
			return false
		var from_path = str(data["from_texture_path"]).strip_edges()
		var to_path = str(data["to_texture_path"]).strip_edges()
		if from_path == "" or to_path == "":
			return false
		if not pack_resource_exists(from_path) or not pack_resource_exists(to_path):
			return false
		if data.has("scale_multiplier") and float(data["scale_multiplier"]) <= 0.0:
			return false
		return true

	if data.has("from_colour") or data.has("to_colour"):
		if not data.has("from_colour") or not data.has("to_colour"):
			return false
		return str(data["from_colour"]).strip_edges() != "" and str(data["to_colour"]).strip_edges() != ""

	return false

# Swap all objects with new ones on this level
func swap_all_assets():

	outputlog("swap_all_assets",2)
	var reverse = ui_config["core"]["reverse_button"].pressed

	var flat_data = make_flat_swap_lists(presetsdropdown.get_current_group_data(), reverse)
	if flat_data == null: return
	var list = []

	outputlog("flat_data: " + str(flat_data),2)
	var last_valid_history = get_history_record_from_end()

	for type in DEFAULT_PRESET_DATA.keys():
		outputlog("type: "+ str(type),2)
		if type in TEXTURE_SWAP_ASSETS && type != "terrain":
			match type:
				"objects":
					list = Global.World.GetCurrentLevel().Objects.get_children()
				"paths":
					list = Global.World.GetCurrentLevel().Pathways.get_children()
				"pattern_shapes":
					list = Global.World.GetCurrentLevel().PatternShapes.GetShapes()
				"walls":
					list = Global.World.GetCurrentLevel().Walls.get_children()
				"portals":
					list = []
			# Check through each node in the list
			for node in list:
				var texture = get_asset_texture(node, type)
				if texture != null:
					if flat_data[type].has(texture.resource_path):
						# Do the swap
						swap_asset_texture(node, type, flat_data[type][texture.resource_path], reverse)
		else:
			match type:
				"terrain":
					swap_terrain(flat_data[type], reverse)
				
				"object_colours":
					for node in Global.World.GetCurrentLevel().Objects.get_children():
						swap_custom_colour_object(node, flat_data[type], reverse)
						
				"lights":
					for node in Global.World.GetCurrentLevel().Lights.get_children():
						swap_light_colour(node, flat_data[type], reverse)
				
				"environment_light":
					swap_environment_light(flat_data[type], reverse)

	purge_history_back_to_record(last_valid_history)		

# Swap the environment light, noting that we ignore the source list setting but simply set to the new
func swap_environment_light(data: Dictionary, reverse: bool):

	outputlog("swap_environment_light: " + str(data),2)
	var target_path_name = "to_colour"
	if reverse:
		target_path_name = "from_colour"
	
	if data.keys().size() > 0:
		var light_data = Global.World.GetCurrentLevel().SaveEnvironment()
		light_data["ambient_light"] = data[data.keys()[0]][target_path_name]
		Global.World.GetCurrentLevel().LoadEnvironment(light_data)


# swap a custom coloured object
func swap_custom_colour_object(node: Node2D, data: Dictionary, reverse: bool = false):

	var target_path_name = "to_colour"
	if reverse:
		target_path_name = "from_colour"

	if node.HasCustomColor():
		if data.has(node.GetCustomColor().to_html()):
			# Do the swap
			if data[node.GetCustomColor().to_html()].has(target_path_name):
				node.SetCustomColor(Color(data[node.GetCustomColor().to_html()][target_path_name]))

# Swap light colour if needed
func swap_light_colour(node: Node2D, data: Dictionary, reverse: bool = false):
	
	outputlog("swap_light_colour: " + str(node),2)
	outputlog("node.color.to_html(): " + str(node.color.to_html()),2)
	var target_path_name = "to_colour"
	if reverse:
		target_path_name = "from_colour"

	if data.has(node.color.to_html()):
		outputlog("has record",2)
		if data[node.color.to_html()].has(target_path_name):
		# Do the swap
			node.color = Color(data[node.color.to_html()][target_path_name])

# Function to swap the terrain
func swap_terrain(terrain_data: Dictionary, reverse: bool = false):

	outputlog("swap_terrain: " + str(terrain_data))

	var terrain = Global.World.GetCurrentLevel().Terrain
	var target_path_name = "to_texture_path"
	if reverse:
		target_path_name = "from_texture_path"

	for _i in terrain.textures.size():
		outputlog("current terrain: " + str(_i) + " " + str(terrain.textures[_i].resource_path),2)
		if terrain_data.has(terrain.textures[_i].resource_path):
			outputlog("matched terrain",2)
			var texture_path = terrain_data[terrain.textures[_i].resource_path][target_path_name]
			var texture = safe_load_texture(str(texture_path))
			if texture == null: return
			terrain.SetTexture(texture, _i)

	terrain.UpdateSplat()

# Function to actually do the swap
func get_texture_size(texture):
	# Godot 3 Texture/ImageTexture exposes get_size(). Return null if the
	# texture does not provide a usable size so callers can fall back safely.
	if texture == null or not texture.has_method("get_size"):
		return null
	var size = texture.get_size()
	if size == null or size.x <= 0.0 or size.y <= 0.0:
		return null
	return Vector2(float(size.x), float(size.y))

# Calculate a scale which preserves the placed asset's displayed dimensions
# when the replacement texture has different native dimensions. X and Y are
# deliberately calculated independently because Dungeondraft assets can be
# non-uniformly scaled.
func get_preserved_scale(original_scale: Vector2, original_texture, replacement_texture, scale_multiplier: float) -> Vector2:
	var old_size = get_texture_size(original_texture)
	var new_size = get_texture_size(replacement_texture)

	if old_size != null and new_size != null:
		var preserved_x = original_scale.x * old_size.x / new_size.x
		var preserved_y = original_scale.y * old_size.y / new_size.y
		return Vector2(preserved_x, preserved_y) * scale_multiplier

	# Safe fallback: if texture dimensions cannot be read, restore both
	# captured scale components rather than accepting Dungeondraft's automatic
	# recalculation.
	return original_scale * scale_multiplier

# Function to actually do the swap
func swap_asset_texture(node: Node2D, type: String, config: Dictionary, reverse: bool = false):

	outputlog("swap_asset_texture: " + str(node) + " type " + str(type) + " config: " + str(config),3)
	var scale_multiplier = config["scale_multiplier"]
	var target_path = config["to_texture_path"]
	var target_colourable_key = "to_is_colourable"
	
	if reverse:
		scale_multiplier = 1.0/scale_multiplier
		target_path = config["from_texture_path"]
		target_colourable_key = "from_is_colourable"
	
	var texture = safe_load_texture(str(target_path))
	if texture == null: return

	# Capture both scale components and the source texture dimensions before
	# changing the texture. Dungeondraft may recalculate the node transform when
	# SetTexture/SetOptions/etc. receives a texture with different dimensions.
	# We therefore preserve the *displayed* width and height rather than merely
	# restoring node.scale. This is especially important for non-uniformly scaled
	# assets where scale.x != scale.y.
	var original_scale = null
	var original_texture = null
	if node != null and node.get("scale") != null:
		original_scale = Vector2(node.scale.x, node.scale.y)
		original_texture = get_asset_texture(node, type)

	var preserved_scale = null
	if original_scale != null:
		preserved_scale = get_preserved_scale(original_scale, original_texture, texture, float(scale_multiplier))

	match type:
		"objects":
			# Preserve the existing custom colour before changing the texture.
			var had_custom_color = false
			var original_custom_color = Color.white
			if node != null:
				if node.get("hasCustomColor") != null:
					had_custom_color = bool(node.get("hasCustomColor"))
				if had_custom_color and node.has_method("GetCustomColor"):
					original_custom_color = node.GetCustomColor()

			node.SetTexture(texture)
			if preserved_scale != null:
				node.scale = preserved_scale
			else:
				node.scale *= scale_multiplier

			if had_custom_color and node.has_method("SetCustomColor"):
				node.hasCustomColor = true
				node.SetCustomColor(original_custom_color)
		"paths":
			var width_scale = find_path_width_scale(node)
			node.texture = texture
			node.SetWidthScale(width_scale * scale_multiplier)
			node.Smooth()
			# Path width is handled separately by Dungeondraft; preserve the
			# node's X/Y scale as well when it is available.
			if preserved_scale != null:
				node.scale = preserved_scale
			else:
				node.scale *= scale_multiplier
		"pattern_shapes":
			var pattern_save = node.Save(true)
			node.SetOptions(texture, Color(pattern_save['color']), node._Rotation)
			if preserved_scale != null:
				node.scale = preserved_scale
			else:
				node.scale *= scale_multiplier
		"walls":
			node.UpdateTexture(texture)
			node.RemakeLines()
			if preserved_scale != null:
				node.scale = preserved_scale
			else:
				node.scale *= scale_multiplier
		"portals":
			node.SetTexture(texture)
			if preserved_scale != null:
				node.scale = preserved_scale
			else:
				node.scale *= scale_multiplier

# Function to take the list of presets and flatten it into a single list for each type that can be iterated on
func make_flat_swap_lists(group_data: Dictionary, reverse: bool = false):

	outputlog("make_flat_swap_lists: " + str(group_data),2)

	if not group_data.has("valid_list"): return null

	var data = {}

	# For each preset
	for preset in group_data["valid_list"]:
		outputlog("preset: " + str(preset),3)
		# For each type
		for type in DEFAULT_PRESET_DATA.keys():
			outputlog("type: " + str(type),3)
			if not data.has(type):
				data[type] = {}
			for entry in preset[type]:
				outputlog("entry: " + str(entry),3)
				if type in TEXTURE_SWAP_ASSETS:
					# Add a key with the from texture path
					if not reverse:
						data[type][entry["from_texture_path"]] = entry.duplicate(true)
					else:
						data[type][entry["to_texture_path"]] = entry.duplicate(true)
				elif type in COLOUR_SWAP_ASSETS:
					if not reverse:
						data[type][entry["from_colour"]] = entry.duplicate(true)
					else:
						data[type][entry["to_colour"]] = entry.duplicate(true)

	return data

# Reset the swap list to empty
func reset_swap_list():

	# For each swap value in the swap vbox
	for swap in swap_vbox.get_children():
		swap_vbox.remove_child(swap)
		swap.queue_free()

#########################################################################################################
##
## PACK REPLACEMENT FUNCTIONS
##
#########################################################################################################

func normalize_pack_id(value: String) -> String:
	var pack_id = value.strip_edges()
	if pack_id == "":
		return ""
	if pack_id.begins_with("res://packs/"):
		var parts = pack_id.split("/")
		if parts.size() >= 3:
			pack_id = parts[2]
	return pack_id

func get_pack_relative_path(resource_path: String) -> String:
	var marker = "res://packs/"
	if not resource_path.begins_with(marker):
		return ""
	var remainder = resource_path.substr(marker.length())
	var slash = remainder.find("/")
	if slash < 0 or slash + 1 >= remainder.length():
		return ""
	return remainder.substr(slash + 1)

func get_pack_id_from_path(resource_path: String) -> String:
	var marker = "res://packs/"
	if not resource_path.begins_with(marker):
		return ""
	var remainder = resource_path.substr(marker.length())
	var slash = remainder.find("/")
	if slash < 0:
		return ""
	return remainder.substr(0, slash)

func make_pack_path(pack_id: String, relative_path: String) -> String:
	return "res://packs/" + pack_id + "/" + relative_path

func pack_resource_exists(resource_path: String) -> bool:
	if resource_path == "":
		return false
	if ResourceLoader.exists(resource_path):
		return true
	var file = File.new()
	return file.file_exists(resource_path)

# Return all levels in the current map. The World API exposes these directly.
func get_pack_levels(all_levels: bool = false) -> Array:
	if Global.World == null:
		return []
	if all_levels:
		return Global.World.levels
	var current = Global.World.GetCurrentLevel()
	if current == null:
		return []
	return [current]

# Return all map nodes which can carry a texture resource path for one level.
func get_map_texture_nodes_for_level(level) -> Array:
	var nodes = []
	if level == null:
		return nodes

	for node in level.Objects.get_children():
		nodes.append([node, "objects"])
	for node in level.Pathways.get_children():
		nodes.append([node, "paths"])
	for node in level.PatternShapes.GetShapes():
		nodes.append([node, "pattern_shapes"])
	for node in level.Walls.get_children():
		nodes.append([node, "walls"])
	for node in level.Portals.get_children():
		nodes.append([node, "portals"])
	for node in level.Roofs.get_children():
		nodes.append([node, "roofs"])

	return nodes

func get_pack_map_entries(pack_id: String, all_levels: bool = false) -> Array:
	var entries = []
	var levels = get_pack_levels(all_levels)

	for level in levels:
		if level == null:
			continue
		for item in get_map_texture_nodes_for_level(level):
			var node = item[0]
			var type = item[1]
			var texture = get_asset_texture(node, type)
			if texture == null:
				continue
			var path = str(texture.resource_path)
			if get_pack_id_from_path(path) == pack_id:
				entries.append({
					"node": node,
					"level": level,
					"level_id": level.ID,
					"level_label": level.Label,
					"type": type,
					"path": path,
					"relative_path": get_pack_relative_path(path)
				})

		# Terrain textures are palette slots, not individual nodes.
		var terrain = level.Terrain
		if terrain != null:
			for index in terrain.textures.size():
				var texture = terrain.textures[index]
				if texture == null:
					continue
				var path = str(texture.resource_path)
				if get_pack_id_from_path(path) == pack_id:
					entries.append({
						"node": terrain,
						"level": level,
						"level_id": level.ID,
						"level_label": level.Label,
						"type": "terrain",
						"index": index,
						"path": path,
						"relative_path": get_pack_relative_path(path)
					})

	return entries

func get_all_pack_ids_in_map() -> Array:
	var found = {}
	for level in get_pack_levels(true):
		if level == null:
			continue
		for item in get_map_texture_nodes_for_level(level):
			var texture = get_asset_texture(item[0], item[1])
			if texture == null:
				continue
			var pack_id = get_pack_id_from_path(str(texture.resource_path))
			if pack_id != "":
				found[pack_id] = true
		var terrain = level.Terrain
		if terrain != null:
			for texture in terrain.textures:
				if texture == null:
					continue
				var terrain_pack_id = get_pack_id_from_path(str(texture.resource_path))
				if terrain_pack_id != "":
					found[terrain_pack_id] = true

	var result = found.keys()
	result.sort()
	return result

func get_asset_pack_manifest() -> Array:
	var result = []
	if Global.Header == null:
		return result
	var manifest = Global.Header.AssetManifest
	if manifest == null:
		return result
	for pack in manifest:
		if pack == null:
			continue
		var pack_id = normalize_pack_id(str(pack.ID))
		if pack_id == "":
			continue
		var pack_name = str(pack.Name)
		if pack_name == "":
			pack_name = "(name unavailable)"
		result.append({"id": pack_id, "name": pack_name})
	return result

func get_asset_pack_catalog() -> Dictionary:
	# Loaded asset packs for the current map. This is used for PackID From/To.
	var catalog = {}
	for pack in get_asset_pack_manifest():
		catalog[pack["id"]] = pack["name"]
	return catalog

func get_map_pack_catalog() -> Dictionary:
	# Only PackIDs that actually occur in map resources. Used by inspection.
	var catalog = {}
	var manifest_catalog = get_asset_pack_catalog()
	for pack_id in get_all_pack_ids_in_map():
		if manifest_catalog.has(pack_id):
			catalog[pack_id] = manifest_catalog[pack_id]
		else:
			catalog[pack_id] = "(name unavailable)"
	return catalog

func get_sorted_asset_pack_ids() -> Array:
	var catalog = get_map_pack_catalog()
	var ids = catalog.keys()
	ids.sort()
	return ids

func add_pack_dropdown_items(dropdown: OptionButton, ids: Array):
	if dropdown == null:
		return
	dropdown.clear()
	for pack_id in ids:
		var pack_name = "(name unavailable)"
		if pack_asset_catalog.has(pack_id):
			pack_name = str(pack_asset_catalog[pack_id])
		dropdown.add_item("%s — %s" % [pack_id, pack_name])
		dropdown.set_item_metadata(dropdown.get_item_count() - 1, pack_id)

func reload_pack_id_dropdown():
	# PackID To contains all loaded asset packs because any loaded pack can be
	# used as a replacement target.
	pack_asset_catalog = get_asset_pack_catalog()
	# PackID From / Inspect contains only PackIDs actually present in the map.
	pack_found_ids = get_sorted_asset_pack_ids()
	var loaded_ids = pack_asset_catalog.keys()
	loaded_ids.sort()

	add_pack_dropdown_items(pack_to_dropdown, loaded_ids)
	add_pack_dropdown_items(pack_from_dropdown, pack_found_ids)

	if pack_found_ids.size() > 0:
		pack_from_dropdown.select(0)
		set_pack_status("Found %d PackID(s) currently present in the map." % pack_found_ids.size())
	else:
		set_pack_status("No PackID is currently present in the map.")

	if loaded_ids.size() > 0:
		pack_to_dropdown.select(0 if loaded_ids.size() == 1 else 1)
	get_pack_map_size()

func get_dropdown_pack_id(dropdown: OptionButton) -> String:
	if dropdown == null or dropdown.get_item_count() == 0:
		return ""
	var metadata = dropdown.get_item_metadata(dropdown.selected)
	if metadata != null:
		return normalize_pack_id(str(metadata))
	return normalize_pack_id(dropdown.get_item_text(dropdown.selected).split(" — ")[0])

func get_selected_pack_from_id() -> String:
	return get_dropdown_pack_id(pack_from_dropdown)

func get_selected_pack_to_id() -> String:
	return get_dropdown_pack_id(pack_to_dropdown)

func on_pack_dropdown_selected(_index: int):
	pass


func get_pack_entry_key(entry: Dictionary) -> String:
	return str(entry["type"]) + "|" + str(entry["path"])

# Capture the complete local transform of a node before invoking any Dungeondraft
# selection/highlight operation. Older Dungeondraft versions can recalculate an
# asset transform while the SelectTool changes its internal selection state.
func capture_node_transform_state(node):
	if node == null or not is_instance_valid(node):
		return null
	return {
		"node": node,
		"position": Vector2(node.position.x, node.position.y),
		"rotation": float(node.rotation),
		"scale": Vector2(node.scale.x, node.scale.y)
	}

func restore_node_transform_state(state):
	if state == null:
		return
	var node = state.get("node")
	if node == null or not is_instance_valid(node):
		return
	# Restore all three components explicitly. Do not rely on assigning only
	# scale because some Dungeondraft asset classes rebuild their transform.
	node.position = state["position"]
	node.rotation = state["rotation"]
	node.scale = state["scale"]

func restore_node_transform_state_deferred(state):
	restore_node_transform_state(state)

func capture_nodes_transform_states(nodes: Array) -> Array:
	var states = []
	var seen = {}
	for node in nodes:
		if node == null or not is_instance_valid(node):
			continue
		var id = node.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		var state = capture_node_transform_state(node)
		if state != null:
			states.append(state)
	return states

func restore_transform_states(states: Array, deferred: bool = true):
	for state in states:
		restore_node_transform_state(state)
		if deferred:
			call_deferred("restore_node_transform_state_deferred", state)

func get_current_selection_nodes() -> Array:
	var nodes = []
	var select_tool = Global.Editor.Tools["SelectTool"]
	if select_tool != null:
		var selected = select_tool.Selected
		if selected != null:
			for node in selected:
				if node != null and is_instance_valid(node):
					nodes.append(node)
	for node in pack_highlighted_nodes:
		if node != null and is_instance_valid(node):
			nodes.append(node)
	return nodes

func clear_node_visual_state(node):
	if node == null or not is_instance_valid(node):
		return
	var state = capture_node_transform_state(node)
	if node.has_method("Highlight"):
		node.Highlight(false)
	if node.has_method("Select"):
		node.Select(false)
	restore_node_transform_state(state)
	call_deferred("restore_node_transform_state_deferred", state)

func clear_all_current_level_visual_selection():
	var current = Global.World.GetCurrentLevel()
	if current == null:
		return

	var states = capture_nodes_transform_states(get_current_selection_nodes())
	var select_tool = Global.Editor.Tools["SelectTool"]
	if select_tool != null:
		select_tool.DeselectAll()
		if select_tool.has_method("ClearTransformSelection"):
			select_tool.ClearTransformSelection()

	for item in get_map_texture_nodes_for_level(current):
		clear_node_visual_state(item[0])

	restore_transform_states(states, true)
	pack_highlighted_nodes.clear()

func clear_all_pack_visual_state():
	# DeselectAll/ClearTransformSelection can trigger a transform recalculation.
	# Capture every currently selected/highlighted node first and restore it both
	# immediately and on the next idle frame.
	var states = capture_nodes_transform_states(get_current_selection_nodes())
	var select_tool = Global.Editor.Tools["SelectTool"]
	if select_tool != null:
		select_tool.DeselectAll()
		if select_tool.has_method("ClearTransformSelection"):
			select_tool.ClearTransformSelection()

	for level in get_pack_levels(true):
		if level == null:
			continue
		for item in get_map_texture_nodes_for_level(level):
			clear_node_visual_state(item[0])

	restore_transform_states(states, true)
	pack_highlighted_nodes.clear()

func clear_pack_highlights():
	clear_all_pack_visual_state()

# Find & Highlight must be a PURE HIGHLIGHT operation.
#
# In particular, do NOT call node.Select(true) here. In Dungeondraft the Select
# state is not merely a yellow visual marker: it participates in the editor's
# selection/transform machinery and therefore produces the blue selection
# state the user normally gets from the Select Tool.
#
# Find & Highlight therefore uses Highlight(true) ONLY. The blue Select state
# is applied later by a single click to exactly one instance, and the real
# SelectTool selection is applied only by double-click.
func highlight_pack_node(node, visual_select: bool = false):
	# Find & Highlight uses Highlight(true) ONLY. This is the yellow inspection
	# state and does not enter the SelectTool selection.
	#
	# visual_select is true only for the single instance currently inspected by
	# a normal click in the result list. Select(true) here is only the node's
	# visual blue state; SelectTool.Selected is not modified.
	if node == null or not is_instance_valid(node):
		return

	var state = capture_node_transform_state(node)
	if node.has_method("Highlight"):
		node.Highlight(true)
	if visual_select and node.has_method("Select"):
		node.Select(true)
	restore_node_transform_state(state)
	call_deferred("restore_node_transform_state_deferred", state)

	if not node in pack_highlighted_nodes:
		pack_highlighted_nodes.append(node)


func set_pack_status(text: String):
	if pack_status_label != null:
		pack_status_label.text = text

func clear_pack_result_list():
	pack_result_entries.clear()
	pack_result_cycle_indices.clear()
	pack_selected_result_index = -1
	pack_selected_single_entry = null
	if pack_result_list != null:
		pack_result_list.clear()

func add_pack_result_entry(text: String, tooltip: String, entry_group: Array):
	if pack_result_list == null:
		return
	var index = pack_result_list.get_item_count()
	pack_result_list.add_item(text)
	pack_result_list.set_item_tooltip(index, tooltip)
	pack_result_entries.append(entry_group)



func get_pack_focus_pixels() -> float:
	# Absolute screen-pixel target. 256 means the focused asset uses about 256x256 pixels.
	if pack_focus_pixel_spinbox != null:
		return max(1.0, float(pack_focus_pixel_spinbox.value))
	return 256.0

func get_current_camera_zoom_scalar() -> float:
	# Dungeondraft uses a Camera2D where a SMALLER zoom value means a CLOSER
	# view. 0.5 is twice as magnified as 1.0.
	if Global.Camera == null:
		return 1.0
	var zoom = Global.Camera.get("zoom")
	if zoom is Vector2:
		return max(0.000001, (abs(float(zoom.x)) + abs(float(zoom.y))) * 0.5)
	return max(0.000001, abs(float(zoom)))

func get_node_world_rect(node) -> Rect2:
	if node == null or not is_instance_valid(node):
		return Rect2()

	# 1) Try explicit Rect property first (some Dungeondraft nodes expose this).
	if node.get("Rect") != null:
		var local_rect = node.get("Rect")
		# Some nodes have a Rect property but it is empty/zero-sized. Skip those.
		if local_rect is Rect2 and local_rect.size.x > 0.0 and local_rect.size.y > 0.0:
			var transform = node.get_global_transform()
			var p1 = transform.xform(local_rect.position)
			var p2 = transform.xform(Vector2(local_rect.position.x + local_rect.size.x, local_rect.position.y))
			var p3 = transform.xform(Vector2(local_rect.position.x, local_rect.position.y + local_rect.size.y))
			var p4 = transform.xform(local_rect.position + local_rect.size)
			var min_x = min(min(p1.x, p2.x), min(p3.x, p4.x))
			var max_x = max(max(p1.x, p2.x), max(p3.x, p4.x))
			var min_y = min(min(p1.y, p2.y), min(p3.y, p4.y))
			var max_y = max(max(p1.y, p2.y), max(p3.y, p4.y))
			return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))

	# 2) Fallback: build rect from the asset texture.
	#    Dungeondraft uses different property names for different node types.
	var texture = null
	if node.get("Texture") != null and node.Texture != null:
		texture = node.Texture
	elif node.get("texture") != null and node.texture != null:
		texture = node.texture
	elif node.get("_Texture") != null and node._Texture != null:
		texture = node._Texture
	elif node.get("TilesTexture") != null and node.TilesTexture != null:
		texture = node.TilesTexture

	if texture != null and texture is Texture:
		var tex_size = texture.get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			# Most Dungeondraft assets are centred on their origin.
			var half_size = tex_size * 0.5
			var local_rect = Rect2(-half_size, tex_size)
			var transform = node.get_global_transform()
			var p1 = transform.xform(local_rect.position)
			var p2 = transform.xform(Vector2(local_rect.position.x + local_rect.size.x, local_rect.position.y))
			var p3 = transform.xform(Vector2(local_rect.position.x, local_rect.position.y + local_rect.size.y))
			var p4 = transform.xform(local_rect.position + local_rect.size)
			var min_x = min(min(p1.x, p2.x), min(p3.x, p4.x))
			var max_x = max(max(p1.x, p2.x), max(p3.x, p4.x))
			var min_y = min(min(p1.y, p2.y), min(p3.y, p4.y))
			var max_y = max(max(p1.y, p2.y), max(p3.y, p4.y))
			return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))

	# 3) Ultimate fallback for nodes without texture or valid Rect.
	if node.get("global_position") != null:
		return Rect2(node.global_position - Vector2(1, 1), Vector2(2, 2))
	return Rect2()

func get_world_rect_displayed_pixel_size(world_rect: Rect2) -> Vector2:
	# Measure actual screen pixels through Godot's canvas transform. This avoids
	# assuming a particular viewport scale or a fixed world-unit/pixel ratio.
	if Global.Camera == null:
		return Vector2.ZERO
	var viewport = Global.Camera.get_viewport()
	if viewport == null:
		return Vector2.ZERO
	var canvas_transform = viewport.get_canvas_transform()
	var p1 = canvas_transform.xform(world_rect.position)
	var p2 = canvas_transform.xform(Vector2(world_rect.position.x + world_rect.size.x, world_rect.position.y))
	var p3 = canvas_transform.xform(Vector2(world_rect.position.x, world_rect.position.y + world_rect.size.y))
	var p4 = canvas_transform.xform(world_rect.position + world_rect.size)
	var min_x = min(min(p1.x, p2.x), min(p3.x, p4.x))
	var max_x = max(max(p1.x, p2.x), max(p3.x, p4.x))
	var min_y = min(min(p1.y, p2.y), min(p3.y, p4.y))
	var max_y = max(max(p1.y, p2.y), max(p3.y, p4.y))
	return Vector2(max(0.0, max_x - min_x), max(0.0, max_y - min_y))


func get_node_displayed_pixel_size(world_rect: Rect2) -> Vector2:
	return get_world_rect_displayed_pixel_size(world_rect)


# Center the camera on the supplied nodes and set an ABSOLUTE zoom so the larger
# dimension of the supplied world-space rectangle occupies the requested number
# of screen pixels. The previous camera zoom is never used to calculate the target.
func focus_camera_on_nodes(nodes: Array):
	# For single-click inspection this is called with exactly one node. Keeping the
	# calculation node-based prevents a stack/group bounding box from determining
	# the zoom level.
	if nodes.size() == 0 or Global.Camera == null:
		return

	var rect = Rect2()
	var have_rect = false
	for node in nodes:
		if node == null or not is_instance_valid(node):
			continue
		var node_rect = get_node_world_rect(node)
		if node_rect.size.x <= 0.0 or node_rect.size.y <= 0.0:
			continue
		if not have_rect:
			rect = node_rect
			have_rect = true
		else:
			rect = rect.merge(node_rect)

	if not have_rect:
		set_pack_status("Could not determine the selected asset bounds.")
		return

	var viewport = Global.Camera.get_viewport()
	if viewport == null:
		set_pack_status("Could not access the Dungeondraft map viewport.")
		return

	var displayed_size = get_world_rect_displayed_pixel_size(rect)
	var current_dimension = max(displayed_size.x, displayed_size.y)
	if current_dimension <= 0.01:
		set_pack_status("Selected asset has no measurable screen size.")
		return

	var target_pixels = get_pack_focus_pixels()
	var current_zoom = get_current_camera_zoom_scalar()
	if current_zoom <= 0.000001:
		current_zoom = 1.0

	# Dungeondraft Camera2D zoom works inversely to displayed size: a smaller
	# zoom value magnifies the map. Therefore, if the object currently occupies
	# 128 screen pixels and the target is 256 pixels, the zoom must be HALVED.
	var target_zoom = current_zoom * current_dimension / target_pixels
	target_zoom = clamp(target_zoom, 0.01, 100.0)

	var center = rect.position + rect.size * 0.5
	# Use global_position, not position. The Dungeondraft editor camera is
	# attached to the editor scene hierarchy; global_position is the camera
	# coordinate that actually represents the map point shown at the viewport
	# center.
	Global.Camera.global_position = center
	Global.Camera.zoom = Vector2(target_zoom, target_zoom)
	# Keep Dungeondraft's native zoom display synchronized with the raw camera.
	if Global.Editor.has_method("SetZoomOptionByRaw"):
		Global.Editor.SetZoomOptionByRaw(target_zoom)

	# Dungeondraft may update its camera once more after the input event. Apply the
	# same absolute camera state on the next idle frame. This is NOT cumulative: the
	# target was calculated from the measured pre-click display size and target px.
	call_deferred("apply_pack_camera_focus_deferred", center, target_zoom, rect, target_pixels)
	set_pack_status("Focused: target %d px | before %.0fx%.0f px | zoom %.4f" % [int(target_pixels), displayed_size.x, displayed_size.y, target_zoom])

func apply_pack_camera_focus_deferred(center: Vector2, target_zoom: float, rect: Rect2, target_pixels: float):
	if Global.Camera == null:
		return
	Global.Camera.global_position = center
	Global.Camera.zoom = Vector2(target_zoom, target_zoom)
	if Global.Editor.has_method("SetZoomOptionByRaw"):
		Global.Editor.SetZoomOptionByRaw(target_zoom)

	# Read back the resulting screen size for diagnostics.
	var actual_size = get_world_rect_displayed_pixel_size(rect)
	set_pack_status("Focused: target %d px | actual %.0fx%.0f px | zoom %.4f" % [int(target_pixels), actual_size.x, actual_size.y, target_zoom])


# Select the actual Dungeondraft Selectables represented by a result entry.
# SelectThing() is the correct API for making objects part of the SelectTool's
# real selection; OnSelect() exposes the editing controls and OnFinishSelection()
# creates the normal transform box used after a manual selection.
func select_pack_result_with_select_tool(index: int):
	if index < 0 or index >= pack_result_entries.size():
		return

	var select_tool = Global.Editor.Tools["SelectTool"]
	if select_tool == null:
		set_pack_status("Select Tool is unavailable.")
		return

	var current_level = Global.World.GetCurrentLevel()
	var nodes_to_select = []
	var states = []
	var seen = {}

	for entry in pack_result_entries[index]:
		if entry["level"] != current_level:
			continue
		if entry["type"] == "terrain":
			continue
		var node = entry["node"]
		if node == null or not is_instance_valid(node):
			continue
		var id = node.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		nodes_to_select.append(node)

	states = capture_nodes_transform_states(nodes_to_select)

	# SelectThing is deliberately used ONLY here, for the actual Select Tool
	# selection requested by double-click.
	for node in nodes_to_select:
		select_tool.SelectThing(node, true)

	# Tell the Select Tool panel which selectable type is active. This is what
	# makes the normal editing controls appear just as they do for a manual click.
	if nodes_to_select.size() > 0:
		var select_panel = Global.Editor.Toolset.GetToolPanel("SelectTool")
		if select_panel != null and select_panel.has_method("OnSelect"):
			select_panel.OnSelect(select_tool.GetSelectableType(nodes_to_select[0]))

	# Build the normal blue transform/rotation/scale box around the whole
	# selection. Calling this ONCE after all nodes are selected is equivalent to
	# finishing a manual multi-selection rather than creating separate selections.
	if select_tool.has_method("OnFinishSelection"):
		select_tool.OnFinishSelection()
	elif select_tool.has_method("EnableTransformBox"):
		select_tool.EnableTransformBox(true)

	# Selection internals may recalculate transforms immediately and/or one frame
	# later. Restore both times, exactly as for Find & Highlight clearing.
	restore_transform_states(states, true)
	return nodes_to_select

# Select exactly the instances represented by the selected result entry.
# Everything else is deselected/de-highlighted. This remains a visual selection;
# it deliberately does NOT enter the SelectTool's internal selection state.
func get_current_level_entries_for_result(index: int) -> Array:
	var result = []
	if index < 0 or index >= pack_result_entries.size():
		return result
	var current_level = Global.World.GetCurrentLevel()
	var seen = {}
	for entry in pack_result_entries[index]:
		if entry["level"] != current_level or entry["type"] == "terrain":
			continue
		var node = entry["node"]
		if node == null or not is_instance_valid(node):
			continue
		var id = node.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		result.append(entry)
	return result

# Single-click inspection cycles through instances belonging to the result entry.
# Only the current level is considered, even when the search scope is All Levels.
func on_pack_result_item_selected(index: int):
	# This handler is connected to ItemList.item_selected. After processing the
	# click we immediately clear the ItemList's own row-selection state. This is
	# intentional: it makes the next click on the SAME row emit item_selected
	# again, allowing the instance cycle to work reliably in Godot 3.
	if index < 0 or index >= pack_result_entries.size():
		return

	var entries = get_current_level_entries_for_result(index)
	if entries.size() == 0:
		clear_all_pack_visual_state()
		pack_selected_result_index = index
		pack_selected_single_entry = null
		if pack_result_list != null and index < pack_result_list.get_item_count():
			pack_result_list.unselect(index)
		set_pack_status("No instance of this asset exists on the current level.")
		return

	# Remove the previous inspection state first. Find & Highlight will be
	# reapplied below as yellow highlights, and only the current instance becomes
	# visually selected blue.
	clear_all_pack_visual_state()
	pack_selected_result_index = index

	var cursor = int(pack_result_cycle_indices.get(index, 0))
	if cursor >= entries.size():
		cursor = 0
	var selected_entry = entries[cursor]
	pack_result_cycle_indices[index] = (cursor + 1) % entries.size()
	pack_selected_single_entry = selected_entry

	# Keep the complete result group yellow. The selected instance receives the
	# additional blue visual Select state. No SelectTool.SelectThing() is called.
	for entry in entries:
		var entry_node = entry["node"]
		if entry_node == null or not is_instance_valid(entry_node):
			continue
		highlight_pack_node(entry_node, entry_node == selected_entry["node"])

	# Focus ONLY the selected instance. The group is never used for the camera
	# calculation, so stacks/groups cannot cause excessive zoom-out.
	focus_camera_on_nodes([selected_entry["node"]])

	# Remove the ItemList's own selection highlight. The blue state visible on the
	# map is supplied by the asset node itself, not by the result list.
	if pack_result_list != null and index < pack_result_list.get_item_count():
		pack_result_list.unselect(index)

	set_pack_status("Showing instance %d of %d on the current level." % [cursor + 1, entries.size()])


# Kept for compatibility with any older connection that still calls the former
# three-argument item_clicked handler.
func on_pack_result_item_clicked(index: int, _position: Vector2, mouse_button_index: int):
	if mouse_button_index == BUTTON_LEFT:
		on_pack_result_item_selected(index)

# Compatibility wrapper for any older signal connection.
func select_pack_result_entry(index: int):
	on_pack_result_item_clicked(index, Vector2.ZERO, BUTTON_LEFT)

# Double-clicking a result switches to the Select Tool and creates the same real
# transform selection as a manual selection. If the scan scope is All Levels,
# ONLY instances on the currently displayed level are considered.
func activate_pack_result_entry(index: int):
	if index < 0 or index >= pack_result_entries.size():
		return

	clear_all_current_level_visual_selection()

	var select_tool = Global.Editor.Tools["SelectTool"]
	if select_tool == null:
		set_pack_status("Select Tool is unavailable.")
		return

	if Global.Editor.Toolset != null:
		Global.Editor.Toolset.Quickswitch("SelectTool")

	# Quickswitch can itself touch the selection state, so give Dungeondraft a
	# frame to finish switching before creating the real SelectTool selection.
	call_deferred("finish_pack_select_tool_activation", index)

func finish_pack_select_tool_activation(index: int):
	if index < 0 or index >= pack_result_entries.size():
		return
	var nodes = select_pack_result_with_select_tool(index)
	pack_highlighted_nodes.clear()
	for node in nodes:
		if not node in pack_highlighted_nodes:
			pack_highlighted_nodes.append(node)
	pack_selected_result_index = index
	set_pack_status("Select Tool active: %d instance(s) selected on the current level." % nodes.size())

# Find all instances of the selected PackID and visibly select/highlight them.
func set_pack_inspect_scope(index: int):
	# Kept as a compatibility wrapper for older signal connections.
	set_pack_scope(index)

func inspect_pack():
	var pack_id = get_selected_pack_from_id()
	if pack_id == "":
		set_pack_status("No PackID is available. Press Reload PackIDs after loading a map.")
		return

	clear_pack_highlights()
	clear_pack_result_list()
	var entries = get_pack_map_entries(pack_id, pack_scope_all_levels)
	var unique_assets = {}

	for entry in entries:
		var key = get_pack_entry_key(entry)
		if not unique_assets.has(key):
			unique_assets[key] = []
		unique_assets[key].append(entry)

	var keys = unique_assets.keys()
	keys.sort()
	var visible_instances = 0

	for key in keys:
		var group = unique_assets[key]
		var first = group[0]
		var current_level_count = 0
		for entry in group:
			if entry["type"] == "terrain":
				continue
			if pack_scope_all_levels:
				# Hidden levels cannot be selected by SelectTool, but their
				# asset-instance highlight can persist and becomes visible when
				# that level is opened.
				var node = entry["node"]
				if node != null and is_instance_valid(node):
					if node.has_method("Highlight"):
						node.Highlight(true)
					pack_highlighted_nodes.append(node)
					if entry["level"] == Global.World.GetCurrentLevel():
						visible_instances += 1
			else:
				if entry["level"] == Global.World.GetCurrentLevel():
					highlight_pack_node(entry["node"])
					visible_instances += 1
					current_level_count += 1

		add_pack_result_entry(
			"[%s] x%d  %s" % [first["type"], group.size(), first["relative_path"]],
			first["path"],
			group
		)

	set_pack_status("Pack %s: %d instances, %d unique assets. %d visible instances selected on current level." % [pack_id, entries.size(), unique_assets.size(), visible_instances])

func deduplicate_swap_data(data: Dictionary) -> Dictionary:
	# Remove duplicate assignments by type + source path/colour. This also
	# repairs duplicates that may already exist in an older JSON file.
	for type in DEFAULT_PRESET_DATA.keys():
		if not data.has(type) or not data[type] is Array:
			data[type] = []
			continue
		var seen = {}
		var unique = []
		for entry in data[type]:
			if not entry is Dictionary:
				continue
			var key = ""
			if entry.has("from_texture_path"):
				key = "texture|" + str(entry.get("from_texture_path", ""))
			elif entry.has("from_colour"):
				key = "colour|" + str(entry.get("from_colour", ""))
			else:
				key = JSON.print(entry)
			if key == "" or seen.has(key):
				continue
			seen[key] = true
			unique.append(entry)
		data[type] = unique
	return data

func add_pack_entries_to_current_swap_list(groups: Array) -> int:
	if groups.size() == 0:
		return 0

	var data = presetsdropdown.get_current_preset_data()
	if data == null:
		data = DEFAULT_PRESET_DATA.duplicate(true)
	else:
		data = data.duplicate(true)

	var added_count = 0
	for group in groups:
		if group.size() == 0:
			continue
		var entry = group[0]
		var type = str(entry["type"])
		if not DEFAULT_PRESET_DATA.has(type):
			continue

		var source_path = str(entry["path"])
		# A swap is identified by its asset type and source texture path.
		# Do not add the same source twice, even when the user first clicks
		# Add Swap and later clicks Add all to Swap.
		var already_exists = false
		for existing in data[type]:
			if existing is Dictionary and str(existing.get("from_texture_path", "")) == source_path:
				already_exists = true
				break
		if already_exists:
			continue

		data[type].append({
			"from_texture_path": source_path,
			"from_is_colourable": get_node_colourable_state(entry["node"], type),
			"to_texture_path": "",
			"to_is_colourable": false,
			"scale_multiplier": 1.0
		})
		added_count += 1

	data = deduplicate_swap_data(data)
	presetsdropdown.save_current_preset_values(data)
	load_preset_values_into_ui(data)
	refresh_list_label_size()
	return added_count

func add_pack_swap_entry():
	# Add exactly the currently selected result entry. Keep this separate from
	# Add all to Swap so a single texture/asset can be added independently.
	var index = pack_selected_result_index
	var selected = pack_result_list.get_selected_items()
	if selected.size() > 0:
		index = selected[0]

	if index < 0 or index >= pack_result_entries.size():
		set_pack_status("Select exactly one asset in the result list first, then press Add Swap.")
		return

	var selected_type = ui_config["core"]["asset_type_button"].get_item_metadata(ui_config["core"]["asset_type_button"].selected)
	var selected_group = pack_result_entries[index]
	if selected_group.size() == 0 or str(selected_group[0]["type"]) != str(selected_type):
		set_pack_status("Add Swap only accepts results of the currently selected Asset Type (%s)." % selected_type)
		return

	# Add Swap operates on the individual instance currently shown by a single
	# click. This allows a stack of identical assets to be inspected and added
	# one at a time. If no individual instance was selected, fall back to the
	# complete result entry for backwards compatibility.
	var add_group = [pack_selected_single_entry] if pack_selected_single_entry != null and pack_selected_result_index == index else [selected_group[0]]
	var added = add_pack_entries_to_current_swap_list([add_group])
	set_pack_status("Added %d selected asset to the current Swap List." % added)

func add_all_pack_results_to_swap():
	if pack_result_entries.size() == 0:
		set_pack_status("No displayed PackID results to add to the Swap List. Run Find & Highlight first.")
		return

	# Add All means all results of the SAME asset type that is currently selected
	# for the Swap List. This prevents portals/doors or other asset classes from
	# accidentally entering an Objects/Paths/etc. swap list.
	var selected_type = ui_config["core"]["asset_type_button"].get_item_metadata(ui_config["core"]["asset_type_button"].selected)
	var filtered_groups = []
	for group in pack_result_entries:
		if group.size() == 0:
			continue
		if str(group[0]["type"]) == str(selected_type):
			filtered_groups.append(group)

	if filtered_groups.size() == 0:
		set_pack_status("No displayed results match the selected Asset Type: %s." % selected_type)
		return

	var added = add_pack_entries_to_current_swap_list(filtered_groups)
	set_pack_status("Added %d unique %s asset(s) from the current PackID result to the current Swap List." % [added, selected_type])

func set_pack_scope(index: int):
	pack_scope_all_levels = index == 1
	if pack_scope_all_levels:
		set_pack_status("Scope: all levels for Find & Highlight and Generate Replacements.")
	else:
		set_pack_status("Scope: current level for Find & Highlight and Generate Replacements.")

# Build replacement mappings from the selected source pack. Matching is strict:
# the relative resource path must exist under the target pack ID.
func compare_packs():
	var pack_from = get_selected_pack_from_id()
	var pack_to = get_selected_pack_to_id()

	if pack_from == "" or pack_to == "":
		set_pack_status("Enter both PackID From and PackID To first.")
		return
	if pack_from == pack_to:
		set_pack_status("PackID From and PackID To must be different.")
		return

	clear_pack_highlights()
	clear_pack_result_list()
	pack_replacement_mappings.clear()

	var entries = get_pack_map_entries(pack_from, pack_scope_all_levels)
	var unique_sources = {}
	var missing_count = 0
	var matched_count = 0

	for entry in entries:
		var key = get_pack_entry_key(entry)
		if not unique_sources.has(key):
			unique_sources[key] = {
				"entries": [],
				"target_path": make_pack_path(pack_to, str(entry["relative_path"])),
				"matched": false
			}
		unique_sources[key]["entries"].append(entry)

	var keys = unique_sources.keys()
	keys.sort()
	for key in keys:
		var record = unique_sources[key]
		var group = record["entries"]
		var entry = group[0]
		var target_path = record["target_path"]
		record["matched"] = pack_resource_exists(target_path)

		if record["matched"]:
			matched_count += 1
			pack_replacement_mappings.append({
				"type": entry["type"],
				"from_texture_path": entry["path"],
				"to_texture_path": target_path,
				"from_is_colourable": get_node_colourable_state(entry["node"], entry["type"]),
				"to_is_colourable": get_node_colourable_state(entry["node"], entry["type"]),
				"scale_multiplier": 1.0
			})
			add_pack_result_entry(
				"MATCH   [%s] x%d  %s" % [entry["type"], group.size(), entry["relative_path"]],
				target_path,
				group
			)
		else:
			missing_count += 1
			for missing_entry in group:
				if missing_entry["type"] == "terrain":
					continue
				if pack_scope_all_levels:
					highlight_pack_node(missing_entry["node"])
				elif missing_entry["level"] == Global.World.GetCurrentLevel():
					highlight_pack_node(missing_entry["node"])
			add_pack_result_entry(
				"MISSING [%s] x%d  %s" % [entry["type"], group.size(), entry["relative_path"]],
				target_path,
				group
			)

	var scope_text = "all levels"
	if not pack_scope_all_levels:
		scope_text = "current level"
	set_pack_status("%s -> %s: %d unique matches, %d missing. %d map instances checked (%s)." % [pack_from, pack_to, matched_count, missing_count, entries.size(), scope_text])

func get_node_colourable_state(node, type: String) -> bool:
	if type == "objects" and node != null:
		if node.get("hasCustomColor") != null:
			return bool(node.get("hasCustomColor"))
	return false

func execute_pack_replacements():
	if pack_replacement_mappings.size() == 0:
		set_pack_status("No generated replacements. Compare two packs first.")
		return

	var last_valid_history = get_history_record_from_end()
	var replacement_count = 0
	var failed_count = 0

	for mapping in pack_replacement_mappings:
		var type = mapping["type"]
		var source_path = mapping["from_texture_path"]

		for level in get_pack_levels(pack_scope_all_levels):
			if level == null:
				continue

			if type == "terrain":
				var terrain = level.Terrain
				if terrain == null:
					continue
				for index in terrain.textures.size():
					var texture = terrain.textures[index]
					if texture != null and str(texture.resource_path) == source_path:
						var target_texture = safe_load_texture(str(mapping["to_texture_path"]))
						if target_texture != null:
							terrain.SetTexture(target_texture, index)
							replacement_count += 1
						else:
							failed_count += 1
				continue

			for item in get_map_texture_nodes_for_level(level):
				var node = item[0]
				var node_type = item[1]
				if node_type != type:
					continue
				var texture = get_asset_texture(node, node_type)
				if texture == null or str(texture.resource_path) != source_path:
					continue

				var config = mapping.duplicate(true)
				if node_type == "roofs":
					var target_texture = safe_load_texture(str(config["to_texture_path"]))
					if target_texture != null:
						# SetTileTexture may recalculate both transform components from
						# the replacement texture. Preserve displayed width and height
						# independently, including non-uniform scaling.
						var original_scale = Vector2(node.scale.x, node.scale.y)
						var original_texture = get_asset_texture(node, "roofs")
						var preserved_scale = get_preserved_scale(original_scale, original_texture, target_texture, float(config["scale_multiplier"]))
						node.SetTileTexture(target_texture)
						node.scale = preserved_scale
						replacement_count += 1
					else:
						failed_count += 1
				else:
					swap_asset_texture(node, node_type, config, false)
					replacement_count += 1

			level.Terrain.UpdateSplat()

	purge_history_back_to_record(last_valid_history)
	var scope_text = "all levels"
	if not pack_scope_all_levels:
		scope_text = "current level"
	set_pack_status("Replacement complete: %d assets replaced, %d failed (%s)." % [replacement_count, failed_count, scope_text])

#########################################################################################################
##
## UI CONTROL FUNCTIONS
##
#########################################################################################################


# Function to add a new swap config to the current swap list
func add_new_swap(save_after_add: bool = true):

	outputlog("add_new_swap")

	var type = ui_config["core"]["asset_type_button"].get_item_metadata(ui_config["core"]["asset_type_button"].selected)
	var new = null

	if type in TEXTURE_SWAP_ASSETS:
		new = SwapController.new(Global.Root, swap_vbox)
		new.connect("set_to_new_value", self, "on_request_to_set_swap_texture")
		new.connect("deleted", self, "refresh_list_label_size")
		update_list_label_size(new)
			
		new.type = type
		if new.type in HIDE_SPINBOX_ASSET_LIST:
			new.spinbox.visible = false

	elif type in COLOUR_SWAP_ASSETS:
		if type == "environment_light" && swap_vbox.get_child_count() > 0:
			return null
		new = SwapColourController.new(Global.Root, swap_vbox, tool_panel)
		new.type = type
	
	else:
		pass

	if new != null and save_after_add:
		# Keep the persistent JSON synchronized when the user explicitly adds
		# a new swap row. Loading a preset passes false to avoid saving while
		# the UI is being reconstructed.
		save_current_preset_values()

	return new

# Function to refresh the list label size
func refresh_list_label_size():

	var min_width = 0.0
	var width

	for swap in swap_vbox:
		width = swap.get_width()
		if min_width < width:
			min_width = width
	
	ui_config["core"]["list_label"].rect_min_size = Vector2(min_width,ui_config["core"]["list_label"].rect_min_size.y)


# Function to scale up or down the list_label size based on a swap size
func update_list_label_size(swap):

	# Wait two idle frames
	timer.start(0.05)
	yield(timer,"timeout")

	outputlog("update_list_label_size: " + str(swap.get_width()),2)

	ui_config["core"]["list_label"].rect_min_size = Vector2(swap.get_width(),ui_config["core"]["list_label"].rect_min_size.y)


# Function respond to a request to swap the texture which requires access to the UI
func on_request_to_set_swap_texture(swap, target: TextureRect):

	outputlog("on_request_to_set_swap_texture",2)
	var gridmenu = null
	var texture_path

	# Check that we should be setting the value at all, i.e. check the right tool is open
	if TOOL_TYPE_LOOKUP[swap.type] in RH_TOOL_TYPES && swap_list_location != TOOL_TYPE_LOOKUP[swap.type]:
		var warn_string = "Use the open tool button to open up the " + str(split_camel_case(str(TOOL_TYPE_LOOKUP[swap.type]))) + " and move the swap list to the right hand panel. You can set the swap textures there and then use the back button to return to this view."
		Global.Editor.Warn("Swap Asset Selection", warn_string)
		return
	
	match swap.type:
		"objects", "paths", "pattern_shapes", "walls", "portals":
			match swap.type:
				"objects":
					gridmenu = Global.Editor.ObjectLibraryPanel.objectMenu
				"paths":
					gridmenu = Global.Editor.PathLibraryPanel.PathMenu
				"pattern_shapes":
					gridmenu = Global.Editor.Tools["PatternShapeTool"].Controls["Texture"]
				"walls":
					gridmenu = Global.Editor.Tools["WallTool"].Controls["Texture"]
				"portals":
					gridmenu = Global.Editor.Tools["PortalTool"].Controls["Texture"]
			if gridmenu.Selected != null:
				if gridmenu.get_selected_items().size() > 0:
					var index = gridmenu.get_selected_items()[0]
					# If this is one of the pattern tool or portal tool and the first entry is the blank entry, then we need to move the index back one
					if gridmenu.get_item_icon(0).resource_path == "res://textures/ui/null.png":
						# If we have selected the blank texture then do nothing
						if index == 0:
							return
						index -= 1
					texture_path = gridmenu.Lookup.keys()[index]
					match swap.type:
						"objects":
							# If the item is colourable, record that so we set that on migration
							if gridmenu.get_item_icon_modulate(index) == Color(1.0,0.0,0.0,1.0):
								swap.set_new_texture(target, texture_path, true)
							else:
								swap.set_new_texture(target, texture_path)
						_:
							swap.set_new_texture(target, texture_path)
			
		"terrain":
			var itemlist = Global.Editor.Tools["TerrainBrush"].terrainList
			if itemlist.get_selected_items().size() > 0:
				texture_path = Global.World.GetCurrentLevel().Terrain.textures[itemlist.get_selected_items()[0]].resource_path
				swap.set_new_texture(target, texture_path)
	
	update_list_label_size(swap)
	# Persist user changes immediately so the JSON remains synchronized.
	# During preset reconstruction this callback is not used.
	if presetsdropdown != null and presetsdropdown.dropdown != null:
		save_current_preset_values()

# Function to show hide the import menus
func on_import_menu_button_toggled(button_pressed: bool):

	export_import_vbox.visible = button_pressed

	ui_config["core"]["swap_hbox"].visible = not button_pressed
	ui_config["core"]["add_button"].visible = not button_pressed
	ui_config["core"]["asset_type_hbox"].visible = not button_pressed
	ui_config["core"]["group_name_label"].visible = not button_pressed
	ui_config["core"]["list_label"].visible = not button_pressed
	swap_scroll.visible = not button_pressed

	presetsdropdown.show_or_hide(not button_pressed)

	if button_pressed:
		hide_asset_specific_ui()
	else:
		on_asset_type_selected(ui_config["core"]["asset_type_button"].selected)

# Function to move the swap list to the right hand panel and opens the correct tool panel
func move_swap_list(button_pressed: bool, open_tool: bool = false):

	outputlog("move_swap_list: button_pressed: " + str(button_pressed) + " open_tool: " + str(open_tool),2)

	var move_list = [swap_scroll,ui_config["core"]["list_label"],ui_config["core"]["add_button"]]

	# If we are moving the swap list
	if button_pressed:
		for item in move_list:
			item.get_parent().remove_child(item)
			rh_panel_box.add_child(item)
			rh_panel_box.move_child(item, 2)
		# Quickswitch to the selected asset type tool
		if open_tool:
			swap_list_location = TOOL_TYPE_LOOKUP[ui_config["core"]["asset_type_button"].get_item_metadata(ui_config["core"]["asset_type_button"].selected)]
			Global.Editor.Toolset.Quickswitch(TOOL_TYPE_LOOKUP[ui_config["core"]["asset_type_button"].get_item_metadata(ui_config["core"]["asset_type_button"].selected)])
		panel.visible = true
		rh_panel_preset_label.text = presetsdropdown.dropdown.get_item_text(presetsdropdown.dropdown.selected)
	else:
		for item in move_list:
			item.get_parent().remove_child(item)
			tool_panel.Align.add_child(item)
			tool_panel.Align.move_child(item, store_swap_index)
		if ui_config["core"]["move_button"].pressed && open_tool:
			ui_config["core"]["move_button"].pressed = false
		else:
			set_property_but_block_signals(ui_config["core"]["move_button"], "pressed", false)
		panel.visible = false
		if open_tool:
			swap_list_location = "SwapAssets"
			Global.Editor.Toolset.Quickswitch("SwapAssets")
	
	outputlog("swap_list_location: " + str(swap_list_location),2)

# When the asset type dropdown is selected
func on_asset_type_selected(index: int):

	var type = ui_config["core"]["asset_type_button"].get_item_metadata(index)

	outputlog("on_asset_type_selected: " + str(type),2)

	# Hide all specific UI
	hide_asset_specific_ui()

	# Based on the index dropdown
	match type:
		# Reveal Objects UI
		"objects":
			tags_panel.visible = true
			Global.Editor.ObjectLibraryPanel.visible = true
		# Reveal Path UI
		"paths":
			Global.Editor.PathLibraryPanel.visible = true
		# Reveal the move button
		"pattern_shapes", "terrain", "walls", "portals":
			ui_config["core"]["move_button"].visible = true
			var image_path = "res://ui/icons/tools/" + split_camel_case(TOOL_TYPE_LOOKUP[type]).replace(" ","_").to_lower().replace("portal","door") + ".png" 
			ui_config["core"]["move_button"].icon = ResourceLoader.load(image_path)
	
	# Load the right data into the UI
	load_preset_values_into_ui(presetsdropdown.get_current_preset_data())
	refresh_list_label_size()

# Hide the specific ui for each type
func hide_asset_specific_ui():

	# Hide all specific UI
	tags_panel.visible = false
	Global.Editor.ObjectLibraryPanel.visible = false
	Global.Editor.PathLibraryPanel.visible = false
	ui_config["core"]["move_button"].visible = false


#########################################################################################################
##
## PRESETS FUNCTIONS
##
#########################################################################################################

# Function to get the data from the swap list
func get_data_from_current_swap_list():

	outputlog("get_data_from_current_swap_list",2)

	var list = []
	# For each swap value in the swap vbox
	for swap in swap_vbox.get_children():
		list.append(swap.get_definition())
	
	return list

# Respond to a request from the presets to call the presetsdropdown with the current UI's values so it will save the data
func save_current_preset_values():

	outputlog("save_current_preset_values",2)

	# Get the current data from this preset
	var data = presetsdropdown.get_current_preset_data()

	# If there is no data then use a default value for the data
	if data == null:
		data = DEFAULT_PRESET_DATA.duplicate(true)

	outputlog("data: " + str(data),2)
	# Set the right data element from the current swap list
	data[ui_config["core"]["asset_type_button"].get_item_metadata(ui_config["core"]["asset_type_button"].selected)] = get_data_from_current_swap_list()
	# Remove duplicate assignments before persisting.
	data = deduplicate_swap_data(data)
	# Save it back into the presets data
	presetsdropdown.save_current_preset_values(data)

# Respond to a request from the presets dropdown to load the data into the swap ui
func load_preset_values_into_ui(data):

	outputlog("load_preset_values_into_ui: " + str(data),2)

	if data == null: return

	var type = ui_config["core"]["asset_type_button"].get_item_metadata(ui_config["core"]["asset_type_button"].selected)
	var swap = null

	reset_swap_list()

	# If there is a type in the data
	if data.has(type):
		for entry in data[type]:
			swap = add_new_swap(false)
			if swap != null:
				swap.set_from_config(entry)

# Function to respond when a new group is selected
func on_group_selected(group_name: String):

	ui_config["core"]["group_name_label"].text = "Swap Group: " + group_name

# Function to respond when the preset group button is toggled, ie to show or hide details for swaps.
func on_presets_group_button_toggled(button_pressed: bool):

	ui_config["core"]["asset_type_hbox"].visible = not button_pressed
	ui_config["core"]["add_button"].visible = not button_pressed
	ui_config["core"]["list_label"].visible = not button_pressed
	swap_scroll.visible = not button_pressed

	# If the group is toggled, then hide the detailed Swap UI
	if button_pressed:
		# Hide the asset specific UI
		hide_asset_specific_ui()
	# Unhide the swap UI
	else:
		# Set and therefore unhide the asset type UI as needed
		on_asset_type_selected(ui_config["core"]["asset_type_button"].selected)

# Function to cover if the back button is pressed, which saves the content before going back to the main swap page
func on_back_button_pressed():

	# save the current data 
	save_current_preset_values()
	# return to the swap assets location
	move_swap_list(false, true)

#########################################################################################################
##
## UI CREATION FUNCTIONS
##
#########################################################################################################

func make_swap_assets_ui():

	outputlog("make_swap_assets_ui")

	ui_config["core"]["import_button"] = Button.new()
	ui_config["core"]["import_button"].icon = safe_load_texture(Global.Root + "icons/settings-icon.png")
	ui_config["core"]["import_button"].text = "Import/Export Menu"
	ui_config["core"]["import_button"].toggle_mode = true
	ui_config["core"]["import_button"].connect("toggled", self, "on_import_menu_button_toggled")
	ui_config["core"]["import_button"].hint_tooltip = "Enable to show the options for importing and exporting pre-existing configs."
	tool_panel.Align.add_child(ui_config["core"]["import_button"])

	ui_config["core"]["swap_hbox"] = HBoxContainer.new()
	ui_config["core"]["swap_hbox"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_panel.Align.add_child(ui_config["core"]["swap_hbox"])

	# Pack inspection/replacement UI
	var pack_separator = HSeparator.new()
	tool_panel.Align.add_child(pack_separator)

	var pack_title = Label.new()
	pack_title.text = "Pack Inspection / Replacement"
	tool_panel.Align.add_child(pack_title)

	# Target pack comes first because it is the destination for generated replacements.
	var pack_to_label = Label.new()
	pack_to_label.text = "PackID To"
	tool_panel.Align.add_child(pack_to_label)

	pack_to_dropdown = OptionButton.new()
	pack_to_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pack_to_dropdown.hint_tooltip = "Loaded asset pack to replace with."
	pack_to_dropdown.connect("item_selected", self, "on_pack_dropdown_selected")
	tool_panel.Align.add_child(pack_to_dropdown)

	# One scope selector is shared by Find & Highlight and Generate Replacements.
	var pack_scope_hbox = HBoxContainer.new()
	var pack_reload_button = Button.new()
	pack_reload_button.text = "Reload PackIDs"
	pack_reload_button.hint_tooltip = "Reload the PackID lists after saving or loading a map."
	pack_reload_button.connect("pressed", self, "reload_pack_id_dropdown")
	pack_scope_hbox.add_child(pack_reload_button)

	pack_scope_dropdown = OptionButton.new()
	pack_scope_dropdown.add_item("Current Level")
	pack_scope_dropdown.add_item("All Levels")
	pack_scope_dropdown.select(0)
	pack_scope_dropdown.hint_tooltip = "Choose whether Find & Highlight and Generate Replacements operate on the current level or every level."
	pack_scope_dropdown.connect("item_selected", self, "set_pack_scope")
	pack_scope_hbox.add_child(pack_scope_dropdown)

	var pack_focus_label = Label.new()
	pack_focus_label.text = "Focus px"
	pack_focus_label.hint_tooltip = "Target displayed size. The larger asset dimension occupies approximately this many screen pixels."
	pack_scope_hbox.add_child(pack_focus_label)

	pack_focus_pixel_spinbox = SpinBox.new()
	pack_focus_pixel_spinbox.min_value = 16.0
	pack_focus_pixel_spinbox.max_value = 4096.0
	pack_focus_pixel_spinbox.step = 1.0
	pack_focus_pixel_spinbox.value = 256.0
	pack_focus_pixel_spinbox.allow_greater = false
	pack_focus_pixel_spinbox.allow_lesser = false
	pack_focus_pixel_spinbox.rect_min_size = Vector2(80, 0)
	pack_focus_pixel_spinbox.hint_tooltip = "Target screen size in pixels. Example: 256 means approximately 256 x 256 pixels."
	pack_focus_pixel_spinbox.get_line_edit().expand_to_text_length = true
	pack_focus_pixel_spinbox.get_line_edit().align = LineEdit.ALIGN_CENTER
	pack_scope_hbox.add_child(pack_focus_pixel_spinbox)
	tool_panel.Align.add_child(pack_scope_hbox)

	# -------------------------------------------------------------------------
	# Manual map-size fallback
	# -------------------------------------------------------------------------
	#
	# These inputs are hidden while the map size can be read directly from
	# Dungeondraft or derived from grid dimensions. They are shown only if both
	# automatic strategies fail.
	# -------------------------------------------------------------------------
	pack_map_size_override_hbox = HBoxContainer.new()
	pack_map_size_override_hbox.visible = false

	var pack_map_width_label = Label.new()
	pack_map_width_label.text = "Map W"
	pack_map_width_label.hint_tooltip = "Manual fallback map width in Dungeondraft world units/pixels."
	pack_map_size_override_hbox.add_child(pack_map_width_label)

	pack_map_width_spinbox = SpinBox.new()
	pack_map_width_spinbox.min_value = 1.0
	pack_map_width_spinbox.max_value = 262144.0
	pack_map_width_spinbox.step = 1.0
	pack_map_width_spinbox.value = 4096.0
	pack_map_width_spinbox.rect_min_size = Vector2(85, 0)
	pack_map_width_spinbox.hint_tooltip = "Manual map width. Used only when Dungeondraft map and grid dimensions cannot be read."
	pack_map_size_override_hbox.add_child(pack_map_width_spinbox)

	var pack_map_height_label = Label.new()
	pack_map_height_label.text = "Map H"
	pack_map_height_label.hint_tooltip = "Manual fallback map height in Dungeondraft world units/pixels."
	pack_map_size_override_hbox.add_child(pack_map_height_label)

	pack_map_height_spinbox = SpinBox.new()
	pack_map_height_spinbox.min_value = 1.0
	pack_map_height_spinbox.max_value = 262144.0
	pack_map_height_spinbox.step = 1.0
	pack_map_height_spinbox.value = 4096.0
	pack_map_height_spinbox.rect_min_size = Vector2(85, 0)
	pack_map_height_spinbox.hint_tooltip = "Manual map height. Used only when Dungeondraft map and grid dimensions cannot be read."
	pack_map_size_override_hbox.add_child(pack_map_height_spinbox)

	tool_panel.Align.add_child(pack_map_size_override_hbox)

	pack_map_size_status_label = Label.new()
	pack_map_size_status_label.text = "Map size will be determined when focusing a result."
	pack_map_size_status_label.autowrap = true
	tool_panel.Align.add_child(pack_map_size_status_label)

	# Source pack / inspection selector. It is restricted to PackIDs actually present in the map.
	var pack_from_label = Label.new()
	pack_from_label.text = "PackID From / Inspect"
	tool_panel.Align.add_child(pack_from_label)

	pack_from_dropdown = OptionButton.new()
	pack_from_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pack_from_dropdown.hint_tooltip = "PackID present in the map. It is used as the source for Generate Replacements and as the PackID searched by Find & Highlight."
	pack_from_dropdown.connect("item_selected", self, "on_pack_dropdown_selected")
	tool_panel.Align.add_child(pack_from_dropdown)

	var pack_find_generate_hbox = HBoxContainer.new()
	var pack_inspect_button = Button.new()
	pack_inspect_button.text = "Find & Highlight"
	pack_inspect_button.hint_tooltip = "Find all assets from the selected PackID using the selected level scope."
	pack_inspect_button.connect("pressed", self, "inspect_pack")
	pack_find_generate_hbox.add_child(pack_inspect_button)

	var pack_compare_button = Button.new()
	pack_compare_button.text = "Generate Replacements"
	pack_compare_button.hint_tooltip = "Generate mappings by replacing PackID From with PackID To while keeping the relative asset path unchanged. Missing targets are highlighted."
	pack_compare_button.connect("pressed", self, "compare_packs")
	pack_find_generate_hbox.add_child(pack_compare_button)
	tool_panel.Align.add_child(pack_find_generate_hbox)

	var pack_action_hbox = HBoxContainer.new()
	var pack_clear_button = Button.new()
	pack_clear_button.text = "Clear Selection"
	pack_clear_button.hint_tooltip = "Deselect and remove highlighting from all asset instances on all levels."
	pack_clear_button.connect("pressed", self, "clear_pack_highlights")
	pack_action_hbox.add_child(pack_clear_button)

	var pack_execute_button = Button.new()
	pack_execute_button.text = "Execute Generated Replacements"
	pack_execute_button.hint_tooltip = "Replace every matching asset using the generated pack mappings and selected level scope."
	pack_execute_button.connect("pressed", self, "execute_pack_replacements")
	pack_action_hbox.add_child(pack_execute_button)
	tool_panel.Align.add_child(pack_action_hbox)

	pack_status_label = Label.new()
	pack_status_label.text = "No PackID scan performed."
	pack_status_label.autowrap = true
	tool_panel.Align.add_child(pack_status_label)

	pack_result_list = ItemList.new()
	pack_result_list.select_mode = ItemList.SELECT_SINGLE
	pack_result_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pack_result_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pack_result_list.rect_min_size = Vector2(0, 100)
	pack_result_list.hint_tooltip = "Single-click to focus the next instance of this asset on the current level. Repeated clicks cycle through stacked instances. Double-click to switch to the Select Tool and select all matching instances on the current level."
	# item_clicked is used instead of item_selected because Dungeondraft's
	# Godot 3 ItemList can keep the same row selected; item_selected therefore
	# does not reliably fire for every repeated click. We need every click so a
	# row can cycle through multiple instances of the same asset.
	pack_result_list.connect("item_selected", self, "on_pack_result_item_selected")
	# item_activated is reserved for double-click and enters the real Select Tool
	# selection mode.
	pack_result_list.connect("item_activated", self, "activate_pack_result_entry")
	tool_panel.Align.add_child(pack_result_list)

	# Swap-list additions belong directly below the Find & Highlight result list
	# and therefore above the normal Swap Group controls.
	var pack_swap_action_hbox = HBoxContainer.new()
	var pack_add_swap_button = Button.new()
	pack_add_swap_button.text = "Add Swap"
	pack_add_swap_button.hint_tooltip = "Add the selected result entry to the current Swap List, if its asset type matches the selected Swap List type."
	pack_add_swap_button.connect("pressed", self, "add_pack_swap_entry")
	pack_swap_action_hbox.add_child(pack_add_swap_button)

	var pack_add_all_swap_button = Button.new()
	pack_add_all_swap_button.text = "Add all to Swap"
	pack_add_all_swap_button.hint_tooltip = "Add all displayed results of the currently selected Swap List asset type."
	pack_add_all_swap_button.connect("pressed", self, "add_all_pack_results_to_swap")
	pack_swap_action_hbox.add_child(pack_add_all_swap_button)
	tool_panel.Align.add_child(pack_swap_action_hbox)

	reload_pack_id_dropdown()

	# Make the button for implementing the asset swap
	ui_config["core"]["swap_button"] = Button.new()
	ui_config["core"]["swap_button"].text = "Implement Asset Swap"
	ui_config["core"]["swap_button"].hint_tooltip = "Press to implement all the swaps contained in the currently selected group on the current level."
	ui_config["core"]["swap_button"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui_config["core"]["swap_button"].icon = safe_load_texture(Global.Root + "icons/transform-icon.png")
	ui_config["core"]["swap_button"].connect("pressed", self, "swap_all_assets")
	ui_config["core"]["swap_hbox"].add_child(ui_config["core"]["swap_button"])

	# Make the button for implementing the asset swap
	ui_config["core"]["reverse_button"] = Button.new()
	ui_config["core"]["reverse_button"].toggle_mode = true
	ui_config["core"]["reverse_button"].hint_tooltip = "Enable to reverse swap direction."
	ui_config["core"]["reverse_button"].icon = safe_load_texture(Global.Root + "icons/reverse-icon.png")
	ui_config["core"]["swap_hbox"].add_child(ui_config["core"]["reverse_button"])

	ui_config["core"]["group_name_label"] = Label.new()
	ui_config["core"]["group_name_label"].hint_tooltip = "This is the name of the group which contains all the swap instructions to be executed."
	tool_panel.Align.add_child(ui_config["core"]["group_name_label"])

	ui_config["core"]["asset_type_button"] = OptionButton.new()
	ui_config["core"]["asset_type_button"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for type in ASSET_TYPES.keys():
		ui_config["core"]["asset_type_button"].add_item(type)
		ui_config["core"]["asset_type_button"].set_item_metadata(ui_config["core"]["asset_type_button"].get_item_count()-1, ASSET_TYPES[type])
	
	ui_config["core"]["asset_type_button"].connect("item_selected",self,"on_asset_type_selected")
	ui_config["core"]["asset_type_label"] = Label.new()
	ui_config["core"]["asset_type_label"].text = "Asset Type"
	ui_config["core"]["asset_type_hbox"] = HBoxContainer.new()
	ui_config["core"]["asset_type_hbox"].add_child(ui_config["core"]["asset_type_label"])
	ui_config["core"]["asset_type_hbox"].add_child(ui_config["core"]["asset_type_button"])
	tool_panel.Align.add_child(ui_config["core"]["asset_type_hbox"])

	# Create button for moving the swap list to the right hand panel and opens the right tool
	ui_config["core"]["move_button"] = Button.new()
	ui_config["core"]["move_button"].text = "Open Tool"
	ui_config["core"]["move_button"].hint_tooltip = "Open tool to select assets and moves swap list to right hand panel"
	ui_config["core"]["move_button"].toggle_mode = true
	ui_config["core"]["move_button"].connect("toggled", self, "move_swap_list",[true])
	tool_panel.Align.add_child(ui_config["core"]["move_button"])

	# Create a button to add new swaps
	ui_config["core"]["add_button"] = Button.new()
	ui_config["core"]["add_button"].text = "Add New Swap"
	ui_config["core"]["add_button"].connect("pressed", self, "add_new_swap")
	tool_panel.Align.add_child(ui_config["core"]["add_button"])

	# Create a label for the list
	ui_config["core"]["list_label"] = Label.new()
	ui_config["core"]["list_label"].text = "Swap List"
	tool_panel.Align.add_child(ui_config["core"]["list_label"])

	# Make a scroll container and add a vbox to it
	swap_scroll = ScrollContainer.new()
	swap_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	swap_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	swap_vbox = VBoxContainer.new()
	swap_scroll.add_child(swap_vbox)
	swap_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	swap_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	swap_scroll.rect_min_size = Vector2(0,64)

	tool_panel.Align.add_child(swap_scroll)

	#swap_scroll.scroll_horizontal_enabled = true
	tool_panel.Align.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	tags_panel = tool_panel.CreateTagsPanel()

	swap_list_location = "SwapAssets"

# Sets up the UI for our tree to live in
func setup_panel():

	outputlog("setup_panel",2)
	# The PanelContainer styling is a bit of a mystery to me - the below is the result of a lot of
	# trial and error.
	panel = PanelContainer.new()

	# Hacky way of doing hidpi scaling. Can't get anchors to work with the current parent node.
	var scale_factor = OS.get_screen_dpi() / 96.0
	panel.set_custom_minimum_size(Vector2(150.0 * scale_factor, 0))

	# Overrides the theme background (which is a light grey) with translucent black.
	var sb = StyleBoxFlat.new()
	sb.set_bg_color(Color(0, 0, 0, 0.4))
	panel.add_stylebox_override("panel", sb)

	# Make a sub hbox
	var sub_hbox = HBoxContainer.new()
	panel.add_child(sub_hbox)
	sub_hbox.set_h_size_flags(3)
	sub_hbox.set_v_size_flags(3)

	# Create an area where you can drag to resize the panel
	var resize_vbox = VBoxContainer.new()
	resize_vbox.rect_min_size = Vector2(5,0)
	resize_vbox.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	resize_vbox.connect("gui_input", self, "on_panel_size_drag_management")
	sub_hbox.add_child(resize_vbox)
	Global.Editor.get_node("VPartition/Panels").add_child(panel)

	# Container that fills the panel. We will add things here.
	var box = VBoxContainer.new()
	box.set_h_size_flags(3)
	box.set_v_size_flags(3)
	sub_hbox.add_child(box)

	# Text label. Should probably make it bold or something, but I don't have the will...
	var label = Label.new()
	label.set_text("Swap Assets")
	var dynamic_font = DynamicFont.new()
	dynamic_font = load("res://ui/fonts/PanelHeadingFont.tres")
	dynamic_font.size = 48
	label.add_font_override("font", dynamic_font)
	box.add_child(label)

	rh_panel_preset_label = Label.new()
	box.add_child(rh_panel_preset_label)

	var back_button = Button.new()
	back_button.icon = load("res://ui/icons/buttons/back.png")
	back_button.hint_tooltip = "Save group and return to SwapAssets mod tool."
	back_button.connect("pressed", self, "on_back_button_pressed")
	box.add_child(back_button)
	panel.visible = false

	rh_panel_box = box

# Function to respond when panel drag is active
func on_panel_size_drag_management(event: InputEvent):

	outputlog("on_panel_size_drag_management",2)

	if Input.is_mouse_button_pressed(BUTTON_LEFT):
		var scale_factor = OS.get_screen_dpi() / 96.0
		var min_x_size = 150.0 * scale_factor
		var local_mouse_pos = panel.get_local_mouse_position()
		if Global.Editor.content.rect_size.x > 60 || local_mouse_pos.x > 0.0:
			panel.set_custom_minimum_size(Vector2(max(panel.get_custom_minimum_size().x-local_mouse_pos.x,min_x_size),0))

#########################################################################################################
##
## PURGE HISTORY FUNCTIONS
##
#########################################################################################################

# Function to purge the history records until we reach the record passed to this function
func purge_history_back_to_record(record):

	outputlog("purge_history_back_to_record: " + str(record),2)

	var count = 0
	# We need to make a reference to the History object otherwise we can't reassign values for some reason
	var history = Global.Editor.History
	# Copy the history list & the bookmark
	var copy_history = history.history.duplicate(true)
	var bookmark = history.bookmark

	# If the record is null purge the entire history
	if record == null:
		history.history = []
		history.bookmark = 0
		return

	# Whie we haven't reached the record we are looking for yet.
	while copy_history.size() > 0:
		outputlog("history: " + str(copy_history),2)
		outputlog("bookmark: " + str(bookmark),2)
		if count > 100:
			break
		# Check if the last record is not the one we are looking for and delete it
		if copy_history[-1] != record:
			outputlog("removing history record: " + str(copy_history[-1]),2)
			# Delete that record
			copy_history.pop_back()
			# Decrement the bookmark
			bookmark -= 1	
		# Otherwise we are done so break
		else:
			break
		count += 1
	# Set the new history values
	history.history = copy_history.duplicate(true)
	history.bookmark = bookmark

# Get the one of the most recent history record
func get_history_record_from_end(index_from_end: int = 0):

	outputlog("get_last_history_record",2)

	if Global.Editor.History.history.size() > index_from_end:
		return Global.Editor.History.history[Global.Editor.History.history.size()-1-index_from_end]
	else:
		return null


#########################################################################################################
##
## START FUNCTIONS
##
#########################################################################################################

func on_tool_enable(tool_id):

	outputlog("on_tool_enable",2)

	# Note that this call reloads the data so we need to save if we have moved location
	on_asset_type_selected(ui_config["core"]["asset_type_button"].selected)

func on_tool_launched(tool_type):

	var visible = false

	if tool_type == "SwapAssets":
		visible = tool_panel.visible
	else:
		visible = Global.Editor.Toolset.GetToolPanel(tool_type).visible

	outputlog("on_tool_launched: " + str(tool_type) + " open: " + str(visible),2)

	if visible:
		# If the intended location of the swap list is the tool that just opened, we are fine, otherwise move the list home
		if swap_list_location != tool_type:
			# Move the list home but don't open the swapassets tool
			move_swap_list(false, false)

	else:
		# If we are not potentially moving from a SwapAssets tool to one of the RH tools then move the swap list home
		if not (swap_list_location in RH_TOOL_TYPES && tool_type == "SwapAssets"):
			# Move the list home but don't open the swapassets tool
			move_swap_list(false, false)

# Main Script
func start() -> void:

	outputlog("SwapAssets Mod Has been loaded.")

	var category = "Effects"
	var id = "SwapAssets"
	var name = "Swap Assets"
	
	var icon = "res://ui/icons/tools/map_settings.png"
	tool_panel = Global.Editor.Toolset.CreateModTool(self, category, id, name, icon)
	tool_panel.Align.connect("visibility_changed", self, "on_tool_launched",[id])

	for tool_type in RH_TOOL_TYPES:
		Global.Editor.Toolset.GetToolPanel(tool_type).connect("visibility_changed", self, "on_tool_launched",[tool_type])

	ui_config["core"] = {}
	make_swap_assets_ui()

	# Create presets class and ui
	var PresetsDropdown = ResourceLoader.load(Global.Root + "PresetsDropdown.gd", "GDScript", true)
	presetsdropdown = PresetsDropdown.new()

	presetsdropdown.global = Global
	presetsdropdown.unique_id = "uchideshi34.SwapAssets"
	presetsdropdown.has_default_preset_mode = true
	presetsdropdown.allow_copy_group = true
	presetsdropdown.preset_config_filename = "swapassets.json"
	# Validate entries before PresetsDropdown exposes them to the Swap UI.
	# Invalid/missing assignments are archived instead of being instantiated.
	presetsdropdown.archive_is_valid_data = {"main_script": self, "is_valid_function": "validate_swap_config_data"}
	presetsdropdown.make_presets_ui(tool_panel.Align, ui_config["core"]["add_button"].get_index())
	presetsdropdown.connect("request_save_current_preset_values", self, "save_current_preset_values")
	presetsdropdown.connect("load_preset_values", self, "load_preset_values_into_ui")
	presetsdropdown.connect("group_selected", self, "on_group_selected")
	# Load the current preset data file
	presetsdropdown._load_scatter_preset_config_file()

	# Make export vbox
	export_import_vbox = VBoxContainer.new()
	tool_panel.Align.add_child(export_import_vbox)
	presetsdropdown.make_presets_import_and_export_ui(export_import_vbox, -1)
	presetsdropdown.show_preset_groups_button.connect("toggled", self, "on_presets_group_button_toggled")

	# Toggle the import view off
	on_import_menu_button_toggled(false)
	hide_asset_specific_ui()

	# Set up the right hand panel
	setup_panel()

	# Initialise the store_swap_index at this position
	store_swap_index = ui_config["core"]["add_button"].get_index()

	timer = Timer.new()
	timer.autostart = false
	timer.one_shot = true
	Global.Editor.get_node("Windows").add_child(timer)

#########################################################################################################
##
## SWAP CONTROLLER CLASS
##
#########################################################################################################

class SwapController extends HBoxContainer:

	var from_texturerect = null
	var to_texturerect = null
	#var hbox = null
	var from_setbutton = null
	var to_setbutton = null
	var spinbox = null
	var type = "objects"
	var store_index = -1
	var timer = Timer.new()

	signal set_to_new_value
	signal move_location
	signal deleted

	var THUMBNAIL_SIZE = {"objects": Vector2(64,64), "paths": Vector2(64,256)}

	const ENABLE_LOGGING = true
	const LOGGING_LEVEL = 2

	func outputlog(msg,level=0):
		if ENABLE_LOGGING:
			if level <= LOGGING_LEVEL:
				printraw("(%d) <SwapAssets-SwapController>: " % OS.get_ticks_msec())
				print(msg)
		else:
			pass

	# Function to create a hbox with entries for swapping assets over
	func _init(root_dir, vbox: VBoxContainer, position: int = -1):

		self.size_flags_horizontal = 3
		self.rect_min_size = 500

		from_texturerect = TextureRect.new()
		from_texturerect.stretch_mode = 6
		from_texturerect.texture = ResourceLoader.load(root_dir + "icons/unchecked.dds")
		from_texturerect.hint_tooltip = "null"
		from_texturerect.set_meta("store_texture_path", "")

		from_setbutton = Button.new()
		from_setbutton.icon = ResourceLoader.load("res://ui/icons/menu/new.png")
		from_setbutton.hint_tooltip = "Press to set selected asset as source asset."
		from_setbutton.connect("pressed", self, "on_setbutton_pressed", [from_texturerect])

		to_texturerect = TextureRect.new()
		to_texturerect.stretch_mode = 6
		to_texturerect.texture = ResourceLoader.load(root_dir + "icons/unchecked.dds")
		to_texturerect.hint_tooltip = "Press to set selected asset as target asset."
		to_texturerect.hint_tooltip = "null"
		to_texturerect.set_meta("store_texture_path", "")

		to_setbutton = Button.new()
		to_setbutton.icon = ResourceLoader.load("res://ui/icons/menu/new.png")
		to_setbutton.connect("pressed", self, "on_setbutton_pressed", [to_texturerect])

		var icon_texturerect = TextureRect.new()
		icon_texturerect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon_texturerect.texture = ResourceLoader.load(root_dir + "icons/arrow.dds")

		spinbox = SpinBox.new()
		spinbox.max_value = 5.0
		spinbox.min_value = 0.1
		spinbox.step = 0.01
		spinbox.value = 1.0
		spinbox.align = LineEdit.ALIGN_CENTER
		spinbox.get_line_edit().expand_to_text_length = true
		spinbox.hint_tooltip = "Set the scale multiplier here"

		var delete_button = Button.new()
		delete_button.icon = ResourceLoader.load(root_dir + "icons/trash_icon.dds")
		delete_button.hint_tooltip = "Delete this swap config item"
		delete_button.connect("pressed", self, "delete")
		
		add_child(from_texturerect)
		add_child(from_setbutton)
		add_child(icon_texturerect)
		add_child(to_texturerect)
		add_child(to_setbutton)
		add_child(spinbox)
		add_child(delete_button)
		
		vbox.add_child(self)
		if not position < 0:
			vbox.move_child(self,position)

	# Function to get the size of the hbox
	func get_width():

		var width = 0.0

		for control in self.get_children():
			if control is Control:
				if control.visible:
					width += control.rect_size.x + 8

		return width

	# Called when the set button is pressed
	func on_setbutton_pressed(target: TextureRect):

		outputlog("on_setbutton_pressed" + str(target),2)

		self.emit_signal("set_to_new_value", self, target)

	# Function to set the swap config value based on a texture path
	func set_new_texture(target_texturerect: TextureRect, texture_path: String, is_colourable: bool = false):

		var texture

		# Check if texture path is usable in the map pack
		var file = File.new()
		if file.file_exists(texture_path) || ResourceLoader.load(texture_path):
			target_texturerect.texture = return_thumbnail_texture(texture_path)
			target_texturerect.set_meta("store_texture_path", texture_path)
			target_texturerect.hint_tooltip = texture_path.split("/")[-1].split(".")[0].to_lower()
			if type == "objects":
				target_texturerect.set_meta("is_colourable", is_colourable)
			return true

		# If not flag an error and return false
		else:
			outputlog("Texture not found: " + str(texture_path))
			return false

	# Function to set values from a config definition
	func set_from_config(definition: Dictionary):

		if definition.has("from_texture_path"):
			if definition.has("from_is_colourable"):
				set_new_texture(from_texturerect, definition["from_texture_path"], definition["from_is_colourable"])
			else:
				set_new_texture(from_texturerect, definition["from_texture_path"])
		
		if definition.has("to_texture_path"):
			if definition.has("to_is_colourable"):
				set_new_texture(to_texturerect, definition["to_texture_path"], definition["to_is_colourable"])
			else:
				set_new_texture(to_texturerect, definition["to_texture_path"])

		if definition.has("scale_multiplier"):
			spinbox.value = definition["scale_multiplier"]

	# Function to return a definiion
	func get_definition():

		var definition = { "from_texture_path": "", "from_is_colourable": false, "to_texture_path": "", "to_is_colourable": false, "scale_multiplier": 1.0}

		if from_texturerect.has_meta("store_texture_path"): definition["from_texture_path"] = from_texturerect.get_meta("store_texture_path")
		if from_texturerect.has_meta("is_colourable"):
			definition["from_is_colourable"] = from_texturerect.get_meta("is_colourable")
		else:
			definition["from_is_colourable"] = false
		
		if to_texturerect.has_meta("store_texture_path"): definition["to_texture_path"] = to_texturerect.get_meta("store_texture_path")
		if to_texturerect.has_meta("is_colourable"):
			definition["to_is_colourable"] = to_texturerect.get_meta("is_colourable")
		else:
			definition["to_is_colourable"] = false
		
		definition["scale_multiplier"] = spinbox.value

		return definition
	
	# Function to delete a swap config entry
	func delete():

		self.get_parent().remove_child(self)
		self.emit_signal("deleted")
		self.queue_free()
	
	# Function to return the thumbnail url from a resource path
	func find_thumbnail_url(resource_path: String):

		var thumbnail_extension = ".png"
		var thumbnail_url

		thumbnail_url = "user://.thumbnails/" + resource_path.md5_text() + thumbnail_extension

		# Check if the thumbnail url is valid, if not create a thumbnail url for the embedded thumbnail
		if not ResourceLoader.exists(thumbnail_url):
			thumbnail_url = "res://packs/" + resource_path.split('/')[3] + "/thumbnails/" + resource_path.md5_text() + thumbnail_extension

		return thumbnail_url

	# Function to return the texture of the thumbnail based on the core texture's resource path
	func return_thumbnail_texture(resource_path: String):

		var texture
		var thumbnail_url = find_thumbnail_url(resource_path)
		if ResourceLoader.exists(thumbnail_url):
			texture = ResourceLoader.load(thumbnail_url)
		else:
			outputlog("Error in return_thumbnail_texture: no thumbnail found for this texture path - " + resource_path)
			return null

		return texture

	# Function to resize a texture to a fixed size
	func resize_texture(tex: Texture, target_size: Vector2) -> Texture:
		if tex == null:
			return null

		# Convert texture to Image
		var img := tex.get_data()

		# Resize the image
		img = img.resize(target_size.x, target_size.y, Image.INTERPOLATE_BILINEAR)

		# Create a new texture from the resized image
		var new_tex := ImageTexture.new()
		new_tex.create_from_image(img, 0)

		return new_tex

#########################################################################################################
##
## SWAP Colour CONTROLLER CLASS
##
#########################################################################################################

class SwapColourController extends HBoxContainer:

	var from_colourbutton = null
	var to_colourbutton = null
	var type = "objects"

	const LIGHT_PRESETS = ["ffeccd8b","ffeaefca","ff80beff","ffffad58","ff4dd569","ffeb8bec","ffffffff"]

	const ENABLE_LOGGING = true
	const LOGGING_LEVEL = 2

	func outputlog(msg,level=0):
		if ENABLE_LOGGING:
			if level <= LOGGING_LEVEL:
				printraw("(%d) <SwapAssets-SwapColourController>: " % OS.get_ticks_msec())
				print(msg)
		else:
			pass

	# Function to create a hbox with entries for swapping assets over
	func _init(root_dir, vbox: VBoxContainer, tool_panel, position: int = -1):

		self.size_flags_horizontal = 3
		self.rect_min_size = 500

		from_colourbutton = tool_panel.CreateColorButton(str(randi()), false, "ffffffff", LIGHT_PRESETS)
		tool_panel.Align.remove_child(from_colourbutton.get_parent())
		from_colourbutton.hint_tooltip = "Custom colour that will be used as a source."

		var icon_texturerect = TextureRect.new()
		icon_texturerect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon_texturerect.texture = ResourceLoader.load(root_dir + "icons/arrow.dds")

		to_colourbutton = tool_panel.CreateColorButton(str(randi()), false, "ffffffff", LIGHT_PRESETS)
		tool_panel.Align.remove_child(to_colourbutton.get_parent())
		to_colourbutton.hint_tooltip = "Custom colour that will be set as the target."

		var delete_button = Button.new()
		delete_button.icon = ResourceLoader.load(root_dir + "icons/trash_icon.dds")
		delete_button.hint_tooltip = "Delete this swap config item"
		delete_button.connect("pressed", self, "delete")
		
		add_child(from_colourbutton.get_parent())
		add_child(icon_texturerect)
		add_child(to_colourbutton.get_parent())
		add_child(delete_button)
		
		vbox.add_child(self)
		if not position < 0:
			vbox.move_child(self,position)

	# Function to set values from a config definition
	func set_from_config(definition: Dictionary):

		if definition.has("from_colour"):
			from_colourbutton.color = Color(definition["from_colour"])
		
		if definition.has("to_colour"):
			to_colourbutton.color = Color(definition["to_colour"])

	# Function to return a definiion
	func get_definition():

		return {"from_colour": from_colourbutton.color.to_html(), "to_colour": to_colourbutton.color.to_html() }
	
	# Function to delete a swap config entry
	func delete():

		self.get_parent().remove_child(self)
		self.queue_free()








	






	