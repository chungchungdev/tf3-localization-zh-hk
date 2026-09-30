local tf3_install_folder = "/home/Chung/.local/share/Steam/steamapps/common/Transport Fever 3/"

return {
	include_dir = {
		-- ensure to set proper paths for the definitions for the base game
		tf3_install_folder .. "api/tealdef",
		tf3_install_folder .. "base/tealdef",

		-- list your mods here, if you provide your own d.tl definitions
		-- "example_mod_1",
	},
	global_env_def = "all_def"
}
