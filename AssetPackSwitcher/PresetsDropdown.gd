# PresetsDropdown v1.0.0
class_name PresetsDropdown

var editname_window = null
var dropdown = null
var group_dropdown = null
var confirm_dialog = null
# confirm_dialog_type can be "save" or "delete"
var confirm_dialog_type = "save" 
var create_new_dialog = null
var ui_hbox = null
var preset_config_filename = "gradientmap_presets.json"
var unique_id = "uchideshi34.SwapAssets"
var preset_config_name = "Scatter Preset Configs"
var global = null
var save_button = null
var show_preset_groups_button = null
var store_data = {}
var export_groups_menu_button = null
var has_default_preset_mode = false
var edit_name_button = null
var delete_button = null
var clear_button = null

# Functions to support if this duplicating groups is permitted
var allow_copy_group = false
var duplicate_group_button = null

signal load_preset_values
signal request_save_current_preset_values
signal group_selected

# archive_list is an array of data that is not valid for some reason but should be maintained and saved into the save file
var archive_is_valid_data = {"main_script": null, "is_valid_function": "no_function"}

# Logging Functions
const ENABLE_LOGGING = true
const LOGGING_LEVEL = 0

const DEFAULT_STORE_DATA = {
	"config_name": "Scatter Preset Configs",
	"group_data": {
		"group-id-0": {
			"group_name": "Default",
			"valid_list": [],
			"archive_list": []
		}
	}
}

func outputlog(msg,level=0):
	if ENABLE_LOGGING:
		if level <= LOGGING_LEVEL:
			printraw("(%d) <SwapAssets-PresetsDropdown>: " % OS.get_ticks_msec())
			print(msg)
	else:
		pass

func _init():
	pass

#########################################################################################################
##
## UTILITY FUNCTIONS
##
#########################################################################################################

# Custom sorter for group_data
class DataSorter:
	static func sort_ascending_by_group_name(a, b):
		if a["group_name"] < b["group_name"]:
			return true
		return false

	static func sort_ascending_by_name(a, b):
		if a["name"] < b["name"]:
			return true
		return false

# Function to look at resource string and return the texture
func load_image_texture(texture_path: String):

	var image = Image.new()
	var texture = ImageTexture.new()

	# If it isn't an internal resource
	if not "res://" in texture_path:
		image.load(global.Root + texture_path)
		texture.create_from_image(image)
	# If it is an internal resource then just use the ResourceLoader
	else:
		texture = ResourceLoader.load(texture_path)
	
	return texture

# Function to see if a structure that looks like a copied dd data entry is the same
func is_the_same(a, b) -> bool:

	if a is Dictionary:
		for key in a.keys():
			if not b.has(key):
				return false
			if not is_the_same(a[key], b[key]):
				return false
	elif a is Array:
		if not b is Array:
			return false
		if a.size() != b.size():
			return false
		for _i in a.size():
			if not is_the_same(a[_i], b[_i]):
				return false
	elif a != b:
		return false

	return true

#########################################################################################################
##
## UI CREATION FUNCTIONS
##
#########################################################################################################

# Function to make and return a menu button based on a dictionary of values: "title", "icon_path", "items", "id_pressed_func", "default_index"
func make_menu_button(container, values: Dictionary):

	# Make menu selection for export types
	var menu_button = MenuButton.new()
	var popup = menu_button.get_popup()
	menu_button.size_flags_horizontal = 3
	if values["icon_path"] != null:
		menu_button.icon = load_image_texture(values["icon_path"])
	menu_button.text = values["title"]
	popup.hide_on_checkable_item_selection = false
	for entry in values["items"]:
		popup.add_check_item(entry)
	if popup.get_item_count() > 0:
		popup.set_item_checked(values["default_index"],true)
	if values["id_pressed_func"] != null:
		popup.connect("id_pressed",self,values["id_pressed_func"],[popup])

	container.add_child(menu_button)

	return menu_button

# Function to build the UI to add and modify scatter tool presets
func make_presets_ui(parent_node, index: int):

	ui_hbox = HBoxContainer.new()
	if parent_node != null:
		parent_node.add_child(ui_hbox)
		if index >= 0:
			parent_node.move_child(ui_hbox,index)

	# Make a dropdown ui for making and deleting preset lists
	# Make a edit name button
	show_preset_groups_button = Button.new()
	show_preset_groups_button.toggle_mode = true
	show_preset_groups_button.hint_tooltip = "Show & Edit Preset Groups"
	show_preset_groups_button.icon = load_image_texture("icons/settings-icon.png")
	show_preset_groups_button.connect("toggled", self, "show_or_hide_preset_groups")
	ui_hbox.add_child(show_preset_groups_button)
	
	# Make the group dropdown
	group_dropdown = OptionButton.new()
	ui_hbox.add_child(group_dropdown)
	group_dropdown.connect("item_selected", self, "on_preset_group_selected")
	group_dropdown.size_flags_horizontal = 3
	group_dropdown.add_item("Add New Group")
	group_dropdown.visible = false

	# Make the UI, need an Dropdown list, a save button and a delete button
	dropdown = OptionButton.new()
	ui_hbox.add_child(dropdown)
	dropdown.connect("item_selected", self, "on_preset_selected")
	
	dropdown.size_flags_horizontal = 3
	if has_default_preset_mode:
		dropdown.add_item("Default")
	else:
		dropdown.add_item("None")
	dropdown.add_item("Add New Preset")

	# Make a edit name button
	edit_name_button = Button.new()
	edit_name_button.hint_tooltip = "Edit name of preset or preset group."
	edit_name_button.icon = load_image_texture("res://ui/icons/tools/path_tool.png")
	edit_name_button.connect("pressed", self, "edit_current_preset_name")
	ui_hbox.add_child(edit_name_button)

	# Make a save button
	save_button = Button.new()
	save_button.hint_tooltip = "Save current selected values."
	save_button.icon = load_image_texture("res://ui/icons/menu/save.png")
	save_button.connect("pressed", self, "on_request_confirm_action",["save"])
	ui_hbox.add_child(save_button)

	# Make a edit name button
	if allow_copy_group:
		duplicate_group_button = Button.new()
		duplicate_group_button.hint_tooltip = "Duplicate this group."
		duplicate_group_button.icon = load_image_texture("res://ui/icons/misc/copy.png")
		duplicate_group_button.connect("pressed", self, "edit_current_preset_name",["copy"])
		ui_hbox.add_child(duplicate_group_button)

	# Make a delete button
	delete_button = Button.new()
	delete_button.hint_tooltip = "Delete this preset or group."
	delete_button.icon = load_image_texture("icons/trash_icon.png")
	delete_button.connect("pressed", self, "on_request_confirm_action",["delete"])
	ui_hbox.add_child(delete_button)

	# Clear the currently selected preset and persist an empty preset.
	# This is deliberately separate from Delete so the JSON file remains
	# present and valid, but the selected preset contains no assignments.
	clear_button = Button.new()
	clear_button.text = "Clear Swap List"
	clear_button.hint_tooltip = "Clear all assignments in the currently selected preset and write the empty list to the JSON file."
	clear_button.connect("pressed", self, "clear_current_preset")
	ui_hbox.add_child(clear_button)
	
	# Confirm delete/save action dialog box
	var action_dialog_template = ResourceLoader.load(global.Root + "ui/confirm_preset_action_dialog.tscn", "", true)
	confirm_dialog = action_dialog_template.instance()
	global.Editor.get_child("Windows").add_child(confirm_dialog)
	confirm_dialog.get_ok().connect("pressed", self, "on_confirm_action_ok_pressed")

	# Edit name dialog box
	var template = ResourceLoader.load(global.Root + "ui/create_preset_dialog.tscn", "", true)
	editname_window = template.instance()
	global.Editor.get_child("Windows").add_child(editname_window)
	editname_window.get_ok().connect("pressed", self, "on_preset_dialogbox_ok_pressed")
	editname_window.connect("popup_hide", self, "on_preset_dialogbox_closed")

# Function to create the ui to import and export presets and place them into a vbox
func make_presets_import_and_export_ui(vbox: VBoxContainer, index: int):

	global.Editor.Toolset.GetToolPanel("PathTool").CreateNote("Use these buttons to import and export preset groups for use in the Gradient option of the tint colour feature.")
	var note = global.Editor.Toolset.GetToolPanel("PathTool").Align.get_child(global.Editor.Toolset.GetToolPanel("PathTool").Align.get_child_count()-1)
	global.Editor.Toolset.GetToolPanel("PathTool").Align.remove_child(note)

	vbox.add_child(note)
	if index >= 0:
		vbox.move_child(note, index)

	var import_button = Button.new()
	import_button.text = "Import Presets"
	import_button.hint_tooltip = "Open a file dialogue box to find and import a json file of presets and merge them into the current set."
	import_button.connect("pressed", self, "on_import_button_pressed")

	vbox.add_child(import_button)
	if index >= 0:
		vbox.move_child(import_button, index)
	
	var export_button = Button.new()
	export_button.text = "Export Presets"
	export_button.hint_tooltip = "Open a file dialogue box to exporta json file of presets."
	export_button.connect("pressed", self, "on_export_button_pressed")

	vbox.add_child(export_button)
	if index >= 0:
		vbox.move_child(export_button, index)

	# Function to make and return a menu button based on a dictionary of values: "title", "icon_path", "items", "id_pressed_func", "default_index"
	export_groups_menu_button = make_menu_button(vbox, {"title": "Select Groups To Export", "icon_path": "res://ui/icons/menu/new.png", "id_pressed_func": "on_select_check_menu_item", "default_index": 0, "items": ["Test","Test2","Test3"]})
	export_groups_menu_button.connect("pressed", self, "refresh_export_groups_menu_button")

# Function to manage selection of the export menu button
func on_select_check_menu_item(id,popupmenu):

	if popupmenu.is_item_checked(id):
		popupmenu.set_item_checked(id,false)
	else:
		popupmenu.set_item_checked(id,true)


#########################################################################################################
##
## UI CONTROL FUNCTIONS
##
#########################################################################################################

# Function to refresh the export groups menu button with the latest group list
func refresh_export_groups_menu_button():

	var popup = export_groups_menu_button.get_popup()

	# Clear the current list
	popup.clear()
	# For each value in the group data, add an item
	for group_data_key in store_data["group_data"].keys():
		# Create a checkable item with the group name
		popup.add_check_item(store_data["group_data"][group_data_key]["group_name"])
		# Add metadata for its group id using the idx as the last one
		popup.set_item_metadata(popup.get_item_count()-1, group_data_key)

# Function to show of hide the group values
func show_or_hide_preset_groups(button_pressed):

	group_dropdown.visible = button_pressed
	dropdown.visible = not button_pressed
	save_button.visible = not button_pressed
	if allow_copy_group:
		duplicate_group_button.visible = button_pressed
	if clear_button != null:
		clear_button.visible = not button_pressed

	# If group is visible then update the tooltip and display the right data in the UI
	if button_pressed:	
		show_preset_groups_button.hint_tooltip = "Show Presets in this Group."
		on_preset_group_selected(group_dropdown.selected)
	else:
		show_preset_groups_button.hint_tooltip = "Show & Edit Preset Groups. Current Group: " + str(group_dropdown.get_item_text(group_dropdown.selected))
		_load_preset_group_into_ui(store_data["group_data"][group_dropdown.get_item_metadata(group_dropdown.selected)])

# Function to hide the whole shebang
func show_or_hide(make_visible: bool):

	if not make_visible:
		group_dropdown.visible = false
		dropdown.visible = false
		save_button.visible = false
		ui_hbox.visible = false
	else:
		ui_hbox.visible = true
		show_or_hide_preset_groups(show_preset_groups_button.pressed)

# On a request for action confirmation set up and launch the confirm dialog box
func on_request_confirm_action(type: String):

	# If this is none record of a preset or the add new preset value
	if (dropdown.selected == 0 && not has_default_preset_mode && dropdown.visible) || dropdown.selected == dropdown.get_item_count()-1:
		return

	# Set the type value so the OK button takes the right action
	confirm_dialog_type = type
	
	match type:
		# If this is a delete confirmation
		"delete":
			if dropdown.visible:
				confirm_dialog.window_title = "Confirm Delete Preset"
				confirm_dialog.find_node("Label").text = "Click OK to confirm that you want to delete this preset."
			else:
				confirm_dialog.window_title = "Confirm Delete Preset Group"
				confirm_dialog.find_node("Label").text = "Click OK to confirm that you want to delete this preset group. It will delete all presets defined within it."
		# If this is a save confirmation
		"save":
			confirm_dialog.window_title = "Confirm Overwrite Preset"
			confirm_dialog.find_node("Label").text = "Click OK to confirm that you want to overwrite the current values in this preset with the ones in the current UI."
		
	
	# Pop up the dialog box noting we are listening for the OK signal to complete the action
	confirm_dialog.popup_centered_minsize()

# When the OK is pressed on the action confirm dialog box then take the appropriate actions
func on_confirm_action_ok_pressed():

	match confirm_dialog_type:
		"delete":
			# If this is a preset then delete it
			if dropdown.visible:
				delete_current_preset()
			# If this is a group then delete it
			else:
				delete_current_preset_group()

		"save":
			# Emit signal to ask main script to save the current values
			self.emit_signal("request_save_current_preset_values")


# Function to create a copy of the current group of presets
func duplicate_current_group():

	outputlog("duplicate_current_group",2)

	var index = group_dropdown.selected
	var group_id = add_new_group()

	outputlog("source_group_id: " + str(group_dropdown.get_item_metadata(index)),2)

	# Check that the current data can be found, which should not fail
	if store_data["group_data"].has(group_dropdown.get_item_metadata(index)):

		var current_data = store_data["group_data"][group_dropdown.get_item_metadata(index)].duplicate(true)
		outputlog("current_data: " + str(current_data))
		if current_data.has("valid_list"):
			store_data["group_data"][group_id]["valid_list"] = current_data["valid_list"].duplicate(true)
		if current_data.has("archive_list"):
			store_data["group_data"][group_id]["archive_list"] = current_data["archive_list"].duplicate(true)

	_save_preset_config_file()


# Clear the current preset without deleting the preset itself.
# The JSON file is immediately rewritten with an empty assignment list.
func clear_current_preset():
	if not dropdown.visible:
		return
	var index = dropdown.selected
	if index < 0 or index >= dropdown.get_item_count()-1:
		return
	if index == 0 and not has_default_preset_mode:
		return

	var empty_data = {
		"objects": [],
		"paths": [],
		"lights": [],
		"pattern_shapes": [],
		"terrain": [],
		"object_colours": [],
		"walls": [],
		"portals": [],
		"environment_light": [],
		"name": dropdown.get_item_text(index)
	}
	dropdown.set_item_metadata(index, empty_data.duplicate(true))
	_save_current_presets_into_store()
	_save_preset_config_file()
	emit_signal("load_preset_values", empty_data)

# Function to delete the current scatter preset
func delete_current_preset():

	var index = dropdown.selected

	# Don't do anything if we are on None on the add preset choice (noting that we shouldn't be calling this if so)
	if index == 0 || index ==  dropdown.get_item_count()-1:
		return
	
	# Return to the none entry
	dropdown.select(0)
	on_preset_selected(0)
	#Remove from the UI
	dropdown.remove_item(index)

	_save_preset_config_file()

# Function to delete the current scatter preset
func delete_current_preset_group():

	outputlog("delete_current_preset_group",2)

	var index = group_dropdown.selected

	# Don't do anything if we are on None on the add preset choice (noting that we shouldn't be calling this if so)
	if group_dropdown.get_item_count() == 2 || index == group_dropdown.get_item_count()-1:
		return
	
	# Return to the none entry
	group_dropdown.select(0)
	on_preset_group_selected(0)

	outputlog("store_data: " + str(store_data),2)

	# Remove the data from the store data
	store_data["group_data"].erase(group_dropdown.get_item_metadata(index))

	outputlog("store_data: " + str(store_data),2)

	# Remove from the UI
	group_dropdown.remove_item(index)

	# Need to remove the group from the data record
	_save_preset_config_file()

# When the OK button is pressed on the preset name dialog then either create a new preset or rename the existing one
func on_preset_dialogbox_ok_pressed():

	outputlog("on_preset_dialogbox_ok_pressed",2)

	# If we are editing a preset name then
	if dropdown.visible:
		# If we are making a new preset then
		if dropdown.selected == dropdown.get_item_count()-1:
			outputlog("is add new preset",2)
			# Set the current item to have the text of the windows lineedit value
			dropdown.set_item_text(dropdown.selected,editname_window.find_node("PresetNameEdit").text)
			# Add a new entry for Add New Preset - noting we simply check for the last one when adding a new entry so this is fine
			dropdown.add_item("Add New Preset")
			# Save it to populate all the values
			self.emit_signal("request_save_current_preset_values")

		# If we are editing an existing preset
		elif dropdown.selected != 0:
			# Set the current item to have the text of the windows lineedit value
			dropdown.set_item_text(dropdown.selected,editname_window.find_node("PresetNameEdit").text)
	# If this is a preset group 
	else:
		outputlog("edit_type: " + str(editname_window.get_meta("edit_type")),2)
		match editname_window.get_meta("edit_type"):
			"default":
				# If we are making a new group then
				if group_dropdown.selected == group_dropdown.get_item_count()-1:
					# Reset the dropdown so we don't save those values into the new group
					reset_dropdown()
					# Add a new group to the end of the list
					add_new_group()

				# If we are editing an existing preset
				else:
					# Set the current item to have the text of the windows lineedit value
					group_dropdown.set_item_text(group_dropdown.selected,editname_window.find_node("PresetNameEdit").text)
					store_data["group_data"][group_dropdown.get_item_metadata(group_dropdown.selected)]["group_name"] = editname_window.find_node("PresetNameEdit").text
			"copy":
				duplicate_current_group()
				# Select the newly created group whic is the penultimate one
				group_dropdown.selected = group_dropdown.get_item_count()-2
				store_data["group_data"][group_dropdown.get_item_metadata(group_dropdown.selected)]["group_name"] = editname_window.find_node("PresetNameEdit").text
				on_preset_group_selected(group_dropdown.get_item_count()-2)	

		_save_preset_config_file()

# Function to add a new empty group with the name from the edit window
func add_new_group() -> String:

	# Set the index to the last value in the group
	var index = group_dropdown.get_item_count()-1

	outputlog("add_new_group: " + str(index),2)

	# Set the current item to have the text of the windows lineedit value
	group_dropdown.set_item_text(index,editname_window.find_node("PresetNameEdit").text)
	# Add a new entry for Add New Preset - noting we simply check for the last one when adding a new entry so this is fine
	group_dropdown.add_item("Add New Group")
	# Create a new group id
	var group_id = get_new_group_id()
	# Set it as the dropdown metadata
	group_dropdown.set_item_metadata(index,group_id)
	# Add a group id record to the store data
	store_data["group_data"][group_id] = {}
	store_data["group_data"][group_id]["valid_list"] = []
	store_data["group_data"][group_id]["archive_list"] = []
	store_data["group_data"][group_id]["group_name"] = editname_window.find_node("PresetNameEdit").text

	return group_id

# Since we are using the global.Editor.SearchHasFocus to stop custom shortcut signals (for some reason the UI does this for other shortcuts), we need to set it to false when we exit the dialog
func on_preset_dialogbox_closed():

	global.Editor.SearchHasFocus = false
	# If this is the preset view
	if dropdown.visible:
		# If we are selected adding a new preset but bugged out then revert to default view
		if dropdown.selected == dropdown.get_item_count()-1:
			dropdown.select(0)
	else:
		if group_dropdown.selected == group_dropdown.get_item_count()-1:
			group_dropdown.select(0)

# Function to edit the current save config's name
func edit_current_preset_name(edit_type: String = "default"):

	# If we are editing the dropdown
	if dropdown.visible:
		# If we are editing the preset which means this isn't a new one and isn't the first entry then...
		if dropdown.selected != dropdown.get_item_count()-1 && dropdown.selected != 0:
			popup_editname_window(edit_type, "Edit Preset Template Name",dropdown.get_item_text(dropdown.selected))
	# If this is the group preset
	else:
		match edit_type:
			"default":
				# If we are editing the preset which means this isn't a new one and isn't the first entry then...
				if group_dropdown.selected != group_dropdown.get_item_count()-1:
					popup_editname_window(edit_type, "Edit Preset Group Name",group_dropdown.get_item_text(group_dropdown.selected))
					
			"copy":
				# If this is a save confirmation
				popup_editname_window(edit_type, "New Copied Preset Group Name","")
	
	_save_preset_config_file()
				

# Pop up the edit name window with various titles and text defaults
func popup_editname_window(edit_type: String, title: String, text: String):

	outputlog("popup_editname_window",2)

	global.Editor.SearchHasFocus = true
	editname_window.window_title = title
	# Set the default value to the current value
	editname_window.find_node("PresetNameEdit").text = text
	editname_window.set_meta("edit_type", edit_type)
	outputlog("edit_type: " + str(editname_window.get_meta("edit_type")))
	# Pop up the window
	editname_window.popup_centered_minsize()
	# Grab focus
	editname_window.find_node("PresetNameEdit").grab_focus()

# Function called when a new preset value is selected, used to load presets or to add a new preset template
func on_preset_selected(index):

	outputlog("on_preset_selected: " + str(index),1)

	# If the "None" value is selected then do nothing
	if index == 0 && not show_preset_groups_button.pressed:
		edit_name_button.disabled = true
		delete_button.disabled = true
		if not has_default_preset_mode:
			return
	else:
		edit_name_button.disabled = false
		delete_button.disabled = false
	
	# If the "Add New Preset Button" value is selected then launch a window to enter a new name. This is better than always checking if the control has focus in the UI
	if index == dropdown.get_item_count()-1:
		# Pop up the edit name window
		popup_editname_window("default", "Create New Preset Template","")
	else:
		self.emit_signal("load_preset_values",dropdown.get_item_metadata(index))

# Function called when a new preset value is selected, used to load presets or to add a new preset template
func on_preset_group_selected(index):

	outputlog("on_preset_group_selected: " + str(index),1)

	edit_name_button.disabled = false
	delete_button.disabled = false

	if index == 0:
		edit_name_button.disabled = true
		delete_button.disabled = true
	
	# If the "Add New Group" item is selected then launch a window to enter a new name. This is better than always checking if the control has focus in the UI
	if index == group_dropdown.get_item_count()-1:
		popup_editname_window("default", "Create New Preset Template","")
	else:
		_load_preset_group_into_ui(store_data["group_data"][group_dropdown.get_item_metadata(index)])


# Function to reset the dropdown without saving
func reset_dropdown():

	# Reset the dropdown to default values
	dropdown.clear()
	if has_default_preset_mode:
		dropdown.add_item("Default")
	else:
		dropdown.add_item("None")
	dropdown.add_item("Add New Preset")
	dropdown.select(0)

# Function to look at the preset group data and add it to the preset dropdown
func _load_preset_group_into_ui(group_data: Dictionary):

	outputlog("_load_preset_group_into_ui",1)

	# Reset the dropdown to default values
	reset_dropdown()

	# Make an empty sorted list
	var sorted_list = []
	var have_popped_default = false
	var store_default
	# Add all the entries into that list
	for config in group_data["valid_list"]:
		if has_default_preset_mode && config["name"] == "Default" && not have_popped_default:
			have_popped_default = true
			store_default = config.duplicate(true)
			dropdown.remove_item(0)
		else:
			sorted_list.append(config)
		
	# Sort the list by name of preset leaving aside the default
	sorted_list.sort_custom(DataSorter,"sort_ascending_by_name")
	if has_default_preset_mode && have_popped_default:
		sorted_list.push_front(store_default)
	
	# For each entry in the sorted list add them to ui
	for config in sorted_list:
		# Check if the assets in the preset can be placed on this map, if not archive it
		# Set the last item name to the config name
		dropdown.set_item_text(dropdown.get_item_count()-1,config["name"])
		dropdown.set_item_metadata(dropdown.get_item_count()-1,config)
		outputlog("_load_scatter_preset_config_file: config: " + str(config),1)
		# Add a new entry for Add New Preset - noting we simply check for the last one when adding a new entry so this is fine
		dropdown.add_item("Add New Preset")
	
	# Select the none value of the dropdown
	dropdown.select(0)
	on_preset_selected(0)
	self.emit_signal("request_save_current_preset_values")
	self.emit_signal("group_selected",group_data["group_name"])


#########################################################################################################
##
## DATA STORAGE FUNCTIONS
##
#########################################################################################################

# Function to return the currently active preset data
func get_current_preset_data():

	return dropdown.get_item_metadata(dropdown.selected)

func get_current_group_data():

	return store_data["group_data"][group_dropdown.get_item_metadata(group_dropdown.selected)]

# Save the value in the existing UI into the scatter preset selected in the dropdown
func save_current_preset_values(data: Dictionary):

	outputlog("save_current_preset_values: data: " + str(data), 2)

	var preset_config: Dictionary
	var index = dropdown.selected
	# If we have selected no scatter preset or this it the "add button" (noting this should not be possible) then don't save
	if (index == 0 && not has_default_preset_mode) || index == dropdown.get_item_count()-1:
		return
	
	preset_config = data.duplicate(true)
	# Set the name of the config to the name of the preset text
	preset_config["name"] = dropdown.get_item_text(index)
	# Attach the preset config as a metadata entry to the index of the preset
	dropdown.set_item_metadata(index,preset_config.duplicate(true))

	_save_preset_config_file()


# Function to look through all the existing group ids and create a new one
func get_new_group_id():

	var characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
	var id_length = 10

	var new_group_id = "group-id-"

	# Make new group id
	for _i in id_length:
		new_group_id = new_group_id + characters[randi() % characters.length()]

	if not new_group_id in store_data["group_data"].keys():
		return new_group_id
	else:
		return get_new_group_id()

# Function to take the current store_data dictionary and load it into the UI. 
func _load_store_data_into_ui():

	if not store_data.has("group_data"):
		return

	# Parse the store_data into valid_list and archive_list and remove the original list
	# If there is no archive validation then duplicate the valid list into list
	if archive_is_valid_data["main_script"] == null:
		for group_data_key in store_data["group_data"].keys():
			if store_data["group_data"][group_data_key].has("list"):
				store_data["group_data"][group_data_key]["valid_list"] = store_data["group_data"][group_data_key]["list"].duplicate(true)
				store_data["group_data"][group_data_key].erase("list")
	else:
		# For each group data key
		for group_data_key in store_data["group_data"].keys():
			# If that data key has a list which they all should
			if store_data["group_data"][group_data_key].has("list"):
				store_data["group_data"][group_data_key]["valid_list"] = []
				store_data["group_data"][group_data_key]["archive_list"] = []
				# Look at each entry in that list
				for entry in store_data["group_data"][group_data_key]["list"]:
					# call the function referenced in the main script with the entry as the function, which returns true or false
					if archive_is_valid_data["main_script"].call(archive_is_valid_data['is_valid_function'], entry):
						# If true, then add it to the valid list
						store_data["group_data"][group_data_key]["valid_list"].append(entry)
					else:
						# If not then add it to the archive list for future use on a different map (probably)
						store_data["group_data"][group_data_key]["archive_list"].append(entry)
			
			# Erase the list data item so we have it clean for saving
			store_data["group_data"][group_data_key].erase("list")

	# Clear the existing dropdown
	group_dropdown.clear()
	var temp_list = []
	# Get the list of groups into a temp array for sorting
	for group_data_key in store_data["group_data"].keys():
		# If this is the default key then don't add but add back later
		if group_data_key == "group-id-0":
			continue
		temp_list.append({"group_name": store_data["group_data"][group_data_key]["group_name"], "group_data_key": group_data_key})
			
	# Sort them into alphabetical order based on group name
	temp_list.sort_custom(DataSorter, "sort_ascending_by_group_name")
	temp_list.push_front({"group_name": store_data["group_data"]["group-id-0"]["group_name"], "group_data_key": "group-id-0"})

	# Populate the UI based on the sorted group data
	for entry in temp_list:
		group_dropdown.add_item(store_data["group_data"][entry["group_data_key"]]["group_name"])
		group_dropdown.set_item_metadata(group_dropdown.get_item_count()-1,entry["group_data_key"])
	group_dropdown.add_item("Add New Group")

	# Select the first group on the list
	group_dropdown.select(0)
	_load_preset_group_into_ui(store_data["group_data"][group_dropdown.get_item_metadata(0)])

# Function to take a new set of store data items and merge it into the existing store data item
func merge_into_store_data(new_data: Dictionary):

	outputlog("merge_into_store_data",2)

	# Take the existing store data and convert it back into a raw list
	convert_store_data_to_long_list()

	if not new_data.has("group_data"):
		outputlog("group_data value not found",2)
		return
	
	# Look at each entry in the list
	for group_data_key in new_data["group_data"].keys():
		if group_data_key in store_data["group_data"].keys():
			store_data["group_data"][group_data_key]["list"].append_array(new_data["group_data"][group_data_key]["list"])
		else:
			store_data["group_data"][group_data_key] = new_data["group_data"][group_data_key].duplicate(true)

# Function to take the store data with a valid_list and archive_list and add back the list value
func convert_store_data_to_long_list():

	outputlog("convert_store_data_to_long_list",2)

	if not store_data.has("group_data"):
		return

	# For each group_data_key
	for group_data_key in store_data["group_data"].keys():

		store_data["group_data"][group_data_key]["list"] = []

		# Take the valid_list data and add it
		if store_data["group_data"][group_data_key].has("valid_list"):
			for item in store_data["group_data"][group_data_key]["valid_list"]:
				store_data["group_data"][group_data_key]["list"].append(item.duplicate(true))

		# Take the archive_list data and add it
		if store_data["group_data"][group_data_key].has("archive_list"):
			for item in store_data["group_data"][group_data_key]["archive_list"]:
				store_data["group_data"][group_data_key]["list"].append(item.duplicate(true)) 


#########################################################################################################
##
## READ & WRITE To FILE FUNCTIONS
##
#########################################################################################################

# Function to get the url for the file path
func get_config_path_dir() -> String:

	var config_path_dir = "user://mod_config/" + unique_id.to_lower().replace(" ", "").replace(".", "_")

	var dir: Directory = Directory.new()
	if not dir.dir_exists(config_path_dir):
		dir.make_dir_recursive(config_path_dir)

	return config_path_dir

# Function to save scatter presets settings into a JSON config file
func _save_preset_config_file():

	var data = {}

	outputlog("_save_preset_config_file",2)

	# Save the current values recorded in the dropdown metadata into the data store
	_save_current_presets_into_store()

	var file = File.new()
	var err = file.open(get_config_path_dir() + "/" + preset_config_filename, File.WRITE)

	data["config_name"] = preset_config_name
	data["group_data"] = {}

	outputlog("store_data: " + str(store_data),2)
	outputlog("store_data[group_data].keys(): " + str(store_data["group_data"].keys()),2)

	# For each group in the store data record
	for group_data_key in store_data["group_data"].keys():

		outputlog("group_data_key: ", str(group_data_key),2)

		data["group_data"][group_data_key] = {}
		data["group_data"][group_data_key]["list"] = []
		data["group_data"][group_data_key]["group_name"] = store_data["group_data"][group_data_key]["group_name"]

		# Take the valid_list data and add it
		for item in store_data["group_data"][group_data_key]["valid_list"]:
			data["group_data"][group_data_key]["list"].append(item.duplicate(true))

		# Take the archive_list data and add it
		for item in store_data["group_data"][group_data_key]["archive_list"]:
			data["group_data"][group_data_key]["list"].append(item.duplicate(true))

	# Print the data object to file
	file.store_string(JSON.print(data, "\t"))
	file.close()

# Function to current preset data into the data store in preparation for saving to file. Only if we are looking at the dropdown menu otherwise ignore.
func _save_current_presets_into_store():

	outputlog("_save_current_presets_into_store",2)
	var start_index = 1

	# If we are in the group editing version, then ignore this call
	if not dropdown.visible:
		return

	var data = {}
	var group_id = group_dropdown.get_item_metadata(group_dropdown.selected)

	data["group_name"] = group_dropdown.get_item_text(group_dropdown.selected)
	data["valid_list"] = []

	# For each config in the ui config file, ignoring the first one (which is "none") unless the defaul mode is being used and the last (which is "Add New Preset")
	if has_default_preset_mode:
		start_index = 0

	for _i in range(start_index,dropdown.get_item_count()-1,1):
		# Add the metadata from the preset list
		data["valid_list"].append(JSON.parse(JSON.print(dropdown.get_item_metadata(_i), "\t")).result)
	
	# Set the store data value to the recorded data
	store_data["group_data"][group_id] = data.duplicate(true)


# Read the stored configuration file from last time
func _load_scatter_preset_config_file():

	outputlog("_load_scatter_preset_config_file()",1)

	var file = File.new()
	var err = file.open(get_config_path_dir() + "/" + preset_config_filename, File.READ)
	if err != OK:
		outputlog("_load_scatter_preset_config_file: file not found: " + str(global.Root + preset_config_filename),2)
		outputlog("_load_scatter_preset_config_file: using default values.",2)
		store_data = DEFAULT_STORE_DATA.duplicate(true)

		_load_store_data_into_ui()

	else:
		var content = file.get_as_text()
		file.close()
		
		var json_result = JSON.parse(content)
		if json_result.error == OK:
			# Set the store data object as the data in the JSON
			store_data = json_result.result
			_load_store_data_into_ui()
				
		else:
			outputlog("JSON Parse Error: ", json_result.error_string(), " in ", content, " at line ", json_result.error_line())

# When the export button is pressed, open a file dialog and select a json file to open and import
func on_export_button_pressed():

	var file_dialog = FileDialog.new()

	global.Editor.SearchHasFocus = true

	file_dialog.mode = 4
	file_dialog.access = 2
	file_dialog.current_dir = global.Root
	file_dialog.set_filters(PoolStringArray(["*.json ;JSON files"]))
	file_dialog.connect("file_selected",self, "on_preset_file_to_export_selected")
	global.Editor.get_node("Windows").add_child(file_dialog)
	file_dialog.connect("popup_hide",self,"set_searchhasfocus_to_false")
	file_dialog.popup_centered_ratio(0.75)


# When an import button is pressed, open a file dialog and select a json file to open and import
func on_import_button_pressed():

	var file_dialog = FileDialog.new()

	global.Editor.SearchHasFocus = true

	file_dialog.mode = 0
	file_dialog.access = 2
	file_dialog.current_dir = global.Root
	file_dialog.set_filters(PoolStringArray(["*.json ;JSON files"]))
	file_dialog.connect("file_selected",self, "on_preset_file_to_import_selected")
	global.Editor.get_node("Windows").add_child(file_dialog)
	file_dialog.connect("popup_hide",self,"set_searchhasfocus_to_false")
	file_dialog.popup_centered_ratio(0.75)

# Function to restore default setting of search has focus
func set_searchhasfocus_to_false():

	global.Editor.SearchHasFocus = false

# Function to process a selected file to import
func on_preset_file_to_import_selected(file_path: String):

	outputlog("on_preset_file_to_import_selected(): " + str(file_path),1)

	var file = File.new()
	var err = file.open(file_path, File.READ)
	if err != OK:
		outputlog("on_preset_file_to_import_selected: file not found: " + str(file_path),1)

		return
	else:
		var content = file.get_as_text()
		file.close()
		
		var json_result = JSON.parse(content)
		if json_result.error == OK:
			# Convert the current store data into a long list
			convert_store_data_to_long_list()
			# Merge the new data into the store data object
			merge_into_store_data(json_result.result)
			# Load the result into the ui
			_load_store_data_into_ui()
				
		else:
			outputlog("JSON Parse Error: ", json_result.error_string(), " in ", content, " at line ", json_result.error_line())

# Function to export some of the preset groups to a user defined json file
func on_preset_file_to_export_selected(file_path: String):

	var data = {}

	outputlog("on_preset_file_to_export_selected",1)

	# Save the current values recorded in the dropdown metadata into the data store
	_save_current_presets_into_store()

	var file = File.new()
	var err = file.open(file_path, File.WRITE)

	data["config_name"] = preset_config_name
	data["group_data"] = {}

	var list_to_export = []
	outputlog("export_groups_menu_button: " + str(export_groups_menu_button),2)
	outputlog("export_groups_menu_button.get_item_count(): " + str(export_groups_menu_button.get_item_count()),2)
	
	# If there is an export group button which there should be
	if export_groups_menu_button != null:
		# Go through each entry
		for idx in export_groups_menu_button.get_popup().get_item_count():
			outputlog("idx: " + str(idx) + " checked: " + str(export_groups_menu_button.is_item_checked(idx)),2)
			# If the group is checked then add it to the export list
			if export_groups_menu_button.get_popup().is_item_checked(idx):
				list_to_export.append(export_groups_menu_button.get_popup().get_item_metadata(idx))

	outputlog("group export list: " + str(list_to_export), 2)
	# For each group in the store data record
	for group_data_key in store_data["group_data"].keys():

		# If the group data key is the list to export then add it to the data structure to export
		if group_data_key in list_to_export:

			outputlog("group_data_key: ", str(group_data_key),2)

			data["group_data"][group_data_key] = {}
			data["group_data"][group_data_key]["list"] = []
			data["group_data"][group_data_key]["group_name"] = store_data["group_data"][group_data_key]["group_name"]

			# Take the valid_list data and add it
			for item in store_data["group_data"][group_data_key]["valid_list"]:
				data["group_data"][group_data_key]["list"].append(item.duplicate(true))

			# Take the archive_list data and add it
			for item in store_data["group_data"][group_data_key]["archive_list"]:
				data["group_data"][group_data_key]["list"].append(item.duplicate(true))

	# Print the data object to file
	file.store_string(JSON.print(data, "\t"))
	file.close()
