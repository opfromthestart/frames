local S = function(s) return s end

local infinite_stacks = minetest.settings:get_bool("creative_mode")
	and minetest.get_modpath("unified_inventory") == nil

local max_frame_push = 20
if minetest.settings:get("max_frame_push") then
	local mfp = tonumber(minetest.settings:get("max_frame_push"))
	if mfp then
		max_frame_push = mfp
	end
end

local frames_pos = {}

-- Helpers

local function get_face(pos, ppos, pvect)
	-- Raytracer to get which face has been clicked
	ppos = { x = ppos.x - pos.x, y = ppos.y - pos.y + 1.5, z = ppos.z - pos.z }

	if pvect.x > 0 then
		local t = (-0.5 - ppos.x) / pvect.x
		local y_int = ppos.y + t * pvect.y
		local z_int = ppos.z + t * pvect.z
		if y_int > -0.45 and y_int < 0.45 and z_int > -0.45 and z_int < 0.45 then
			return 1
		end
	elseif pvect.x < 0 then
		local t = (0.5 - ppos.x) / pvect.x
		local y_int = ppos.y + t * pvect.y
		local z_int = ppos.z + t * pvect.z
		if y_int > -0.45 and y_int < 0.45 and z_int > -0.45 and z_int < 0.45 then
			return 2
		end
	end

	if pvect.y > 0 then
		local t = (-0.5 - ppos.y) / pvect.y
		local x_int = ppos.x + t * pvect.x
		local z_int = ppos.z + t * pvect.z
		if x_int > -0.45 and x_int < 0.45 and z_int > -0.45 and z_int < 0.45 then
			return 3
		end
	elseif pvect.y < 0 then
		local t = (0.5 - ppos.y) / pvect.y
		local x_int = ppos.x + t * pvect.x
		local z_int = ppos.z + t * pvect.z
		if x_int > -0.45 and x_int < 0.45 and z_int > -0.45 and z_int < 0.45 then
			return 4
		end
	end

	if pvect.z > 0 then
		local t = (-0.5 - ppos.z) / pvect.z
		local x_int = ppos.x + t * pvect.x
		local y_int = ppos.y + t * pvect.y
		if x_int > -0.45 and x_int < 0.45 and y_int > -0.45 and y_int < 0.45 then
			return 5
		end
	elseif pvect.z < 0 then
		local t = (0.5 - ppos.z) / pvect.z
		local x_int = ppos.x + t * pvect.x
		local y_int = ppos.y + t * pvect.y
		if x_int > -0.45 and x_int < 0.45 and y_int > -0.45 and y_int < 0.45 then
			return 6
		end
	end
end

local function lines(str)
	local t = {}
	local function helper(line)
		table.insert(t, line)
		return ""
	end
	helper(str:gsub("(.-)\r?\n", helper))
	return t
end

local function pos_to_string(pos)
	if pos.x == 0 then pos.x = 0 end -- Fix for signed 0
	if pos.y == 0 then pos.y = 0 end -- Fix for signed 0
	if pos.z == 0 then pos.z = 0 end -- Fix for signed 0
	return tostring(pos.x) .. "\n" .. tostring(pos.y) .. "\n" .. tostring(pos.z)
end

local function pos_from_string(str)
	local l = lines(str)
	return { x = tonumber(l[1]), y = tonumber(l[2]), z = tonumber(l[3]) }
end

local function pos_in_list(l, pos)
	for _, p in ipairs(l) do
		if p.x == pos.x and p.y == pos.y and p.z == pos.z then
			return true
		end
	end
	return false
end

local function add_table(table, toadd)
	local i = 1
	while true do
		local o = table[i]
		if o == toadd then return end
		if o == nil then break end
		i = i + 1
	end
	table[i] = toadd
end

local function move_nodes_vect(poslist, vect, must_not_move, owner)
	if minetest.is_protected then
		for _, pos in ipairs(poslist) do
			local npos = vector.add(pos, vect)
			if minetest.is_protected(pos, owner) or minetest.is_protected(npos, owner) then
				return
			end
		end
	end

	for _, pos in ipairs(poslist) do
		local npos = vector.add(pos, vect)
		local name = minetest.get_node(npos).name
		if (name ~= "air" and minetest.registered_nodes[name].liquidtype == "none" or
				frames_pos[pos_to_string(npos)]) and not pos_in_list(poslist, npos) then
			poslist[#poslist + 1] = npos
		end
		if #poslist > max_frame_push then
			return
		end
	end

	local nodelist = {}
	for _, pos in ipairs(poslist) do
		local node = minetest.get_node(pos)
		local meta = minetest.get_meta(pos):to_table()
		local timer = minetest.get_node_timer(pos)
		nodelist[#nodelist + 1] = {
			oldpos = pos,
			pos = vector.add(pos, vect),
			node = node,
			meta = meta,
			timer = {
				timeout = timer:get_timeout(),
				elapsed = timer:get_elapsed()
			}
		}
	end

	local objects = {}
	for _, pos in ipairs(poslist) do
		for _, object in ipairs(minetest.get_objects_inside_radius(pos, 1)) do
			local entity = object:get_luaentity()
			if not entity or not mesecon.is_mvps_unmov(entity.name) then
				add_table(objects, object)
			end
		end
	end

	for _, obj in ipairs(objects) do
		obj:set_pos(vector.add(obj:get_pos(), vect))
	end

	for _, n in ipairs(nodelist) do
		local npos = n.pos
		minetest.set_node(npos, n.node)
		local meta = minetest.get_meta(npos)
		meta:from_table(n.meta)
		local timer = minetest.get_node_timer(npos)
		if n.timer.timeout ~= 0 or n.timer.elapsed ~= 0 then
			timer:set(n.timer.timeout, n.timer.elapsed)
		end
		for __, pos in ipairs(poslist) do
			if npos.x == pos.x and npos.y == pos.y and npos.z == pos.z then
				table.remove(poslist, __)
				break
			end
		end
	end

	for __, pos in ipairs(poslist) do
		minetest.remove_node(pos)
	end

	for _, callback in ipairs(mesecon.on_mvps_move) do
		callback(nodelist)
	end
end

local function is_supported_node(name)
	return string.find(name, "tube") and string.find(name, "pipeworks")
end

-- Frames
for xm = 0, 1 do
	for xp = 0, 1 do
		for ym = 0, 1 do
			for yp = 0, 1 do
				for zm = 0, 1 do
					for zp = 0, 1 do
						local a = 8 / 16
						local b = 7 / 16
						local nodeboxes = {
							{ -a, -a, -a, -b, a,  -b },
							{ -a, -a, b,  -b, a,  a },

							{ b,  -a, b,  a,  a,  a },
							{ b,  -a, -a, a,  a,  -b },

							{ -b, b,  -a, b,  a,  -b },
							{ -b, -a, -a, b,  -b, -b },

							{ -b, b,  b,  b,  a,  a },
							{ -b, -a, b,  b,  -b, a },

							{ b,  b,  -b, a,  a,  b },
							{ b,  -a, -b, a,  -b, b },

							{ -a, b,  -b, -b, a,  b },
							{ -a, -a, -b, -b, -b, b },
						}

						if yp == 0 then
							table.insert(nodeboxes, { -b, b, -b, b, a, b })
						end
						if ym == 0 then
							table.insert(nodeboxes, { -b, -a, -b, b, -b, b })
						end
						if xp == 0 then
							table.insert(nodeboxes, { b, b, b, a, -b, -b })
						end
						if xm == 0 then
							table.insert(nodeboxes, { -a, -b, -b, -b, b, b })
						end
						if zp == 0 then
							table.insert(nodeboxes, { -b, -b, b, b, b, a })
						end
						if zm == 0 then
							table.insert(nodeboxes, { -b, -b, -a, b, b, -b })
						end

						local nameext = string.format("%d%d%d%d%d%d", xm, xp, ym, yp, zm, zp)
						local groups = { snappy = 2, choppy = 2, oddly_breakable_by_hand = 2 }
						if nameext ~= "111111" then groups.not_in_creative_inventory = 1 end


						minetest.register_node("frames:frame_" .. nameext, {
							description = S("Frame"),
							tiles = { "technic_frame.png" },
							groups = groups,
							drawtype = "nodebox",
							node_box = {
								type = "fixed",
								fixed = nodeboxes,
							},
							selection_box = {
								type = "fixed",
								fixed = { -0.5, -0.5, -0.5, 0.5, 0.5, 0.5 }
							},
							paramtype = "light",
							frame = 1,
							drop = "frames:frame_111111",
							sunlight_propagates = true,

							frame_connect_all = function(nodename)
								local l2 = {}
								local l1 = {
									{ x = -1, y = 0,  z = 0 }, { x = 1, y = 0, z = 0 },
									{ x = 0,  y = -1, z = 0 }, { x = 0, y = 1, z = 0 },
									{ x = 0, y = 0, z = -1 }, { x = 0, y = 0, z = 1 }
								}
								for i, dir in ipairs(l1) do
									if string.sub(nodename, -7 + i, -7 + i) == "1" then
										l2[#l2 + 1] = dir
									end
								end
								return l2
							end,

							on_punch = function(pos, node, puncher)
								local ppos = puncher:get_pos()
								local pvect = puncher:get_look_dir()
								local pface = get_face(pos, ppos, pvect)

								if pface == nil then return end

								local nodename = node.name
								local newstate = tostring(1 - tonumber(string.sub(nodename, pface - 7, pface - 7)))
								if pface <= 5 then
									nodename = string.sub(nodename, 1, pface - 7 - 1) ..
										newstate .. string.sub(nodename, pface - 7 + 1)
								else
									nodename = string.sub(nodename, 1, -2) .. newstate
								end

								node.name = nodename
								minetest.set_node(pos, node)
							end,

							on_place = function(itemstack, placer, pointed_thing)
								local pos = pointed_thing.above

								if minetest.is_protected(pos, placer:get_player_name()) then
									minetest.log("action", placer:get_player_name()
										.. " tried to place " .. itemstack:get_name()
										.. " at protected position "
										.. minetest.pos_to_string(pos))
									minetest.record_protection_violation(pos, placer:get_player_name())
									return itemstack
								end

								if pos == nil then return end

								local node = minetest.get_node(pos)
								if node.name ~= "air" then
									if is_supported_node(node.name) then
										local obj = minetest.add_entity(pos, "frames:frame_entity")
										obj:get_luaentity():set_node({ name = itemstack:get_name() })
									end
								else
									minetest.set_node(pos, { name = itemstack:get_name() })
								end

								if not infinite_stacks then
									itemstack:take_item()
								end
								return itemstack
							end,

							on_rightclick = function(pos, node, placer, itemstack, pointed_thing)
								if is_supported_node(itemstack:get_name()) then
									if minetest.is_protected(pos, placer:get_player_name()) then
										minetest.log("action", placer:get_player_name()
											.. " tried to place " .. itemstack:get_name()
											.. " at protected position "
											.. minetest.pos_to_string(pos))
										minetest.record_protection_violation(pos, placer:get_player_name())
										return itemstack
									end

									minetest.set_node(pos, { name = itemstack:get_name() })

									local take_item = true
									local def = minetest.registered_items[itemstack:get_name()]
									-- Run callback
									if def.after_place_node then
										-- Copy place_to because callback can modify it
										local pos_copy = vector.new(pos)
										if def.after_place_node(pos_copy, placer, itemstack) then
											take_item = false
										end
									end

									-- Run script hook
									local callback = nil
									for _, _ in ipairs(minetest.registered_on_placenodes) do
										-- Copy pos and node because callback can modify them
										local pos_copy = { x = pos.x, y = pos.y, z = pos.z }
										local newnode_copy = { name = def.name, param1 = 0, param2 = 0 }
										local oldnode_copy = { name = "air", param1 = 0, param2 = 0 }
										if callback(pos_copy, newnode_copy, placer, oldnode_copy, itemstack) then
											take_item = false
										end
									end

									if take_item then
										itemstack:take_item()
									end

									local obj = minetest.add_entity(pos, "frames:frame_entity")
									obj:get_luaentity():set_node({ name = node.name })

									return itemstack
								else
									--local pointed_thing = { type = "node", under = pos }
									if pointed_thing then
										return minetest.item_place_node(itemstack, placer, pointed_thing)
									end
								end
							end,
						})
					end
				end
			end
		end
	end
end

minetest.register_entity("frames:frame_entity", {
	initial_properties = {
		physical = true,
		collisionbox = { -0.5, -0.5, -0.5, 0.5, 0.5, 0.5 },
		visual = "wielditem",
		textures = {},
		visual_size = { x = 0.667, y = 0.667 },
	},

	node = {},

	set_node = function(self, node)
		self.node = node
		local pos = vector.round(self.object:getpos())
		frames_pos[pos_to_string(pos)] = node.name

		-- This code does nothing currently, so it is disabled to stop luacheck warnings
		--[[
		local stack = ItemStack(node.name)
		local itemtable = stack:to_table()
		local itemname = nil

		if itemtable then
			itemname = stack:to_table().name
		end

		local item_texture = nil
		local item_type = ""
		if minetest.registered_items[itemname] then
			item_texture = minetest.registered_items[itemname].inventory_image
			item_type = minetest.registered_items[itemname].type
		end
--]]
		local prop = {
			is_visible = true,
			textures = { node.name },
		}
		self.object:set_properties(prop)
	end,

	get_staticdata = function(self)
		return self.node.name
	end,

	on_activate = function(self, staticdata)
		self.object:set_armor_groups({ immortal = 1 })
		self:set_node({ name = staticdata })
	end,

	dig = function(self)
		minetest.handle_node_drops(self.object:get_pos(), { ItemStack("frames:frame_111111") }, self.last_puncher)
		local pos = vector.round(self.object:get_pos())
		frames_pos[pos_to_string(pos)] = nil
		self.object:remove()
	end,

	on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir)
		local pos = self.object:get_pos()
		if self.damage_object == nil then
			self.damage_object = minetest.add_entity(pos, "frames:damage_entity")
			self.damage_object:get_luaentity().remaining_time = 0.25
			self.damage_object:get_luaentity().frame_object = self
			self.damage_object:get_luaentity().texture_index = 0
			self.damage_object:get_luaentity().texture_change_time = 0.15
		else
			self.damage_object:get_luaentity().remaining_time = 0.25
		end

		self.last_puncher = puncher
		local ppos = puncher:get_pos()
		local pvect = puncher:get_look_dir()
		local pface = get_face(pos, ppos, pvect)
		if pface == nil then return end
		local nodename = self.node.name
		local newstate = tostring(1 - tonumber(string.sub(nodename, pface - 7, pface - 7)))

		if pface <= 5 then
			nodename = string.sub(nodename, 1, pface - 7 - 1) .. newstate .. string.sub(nodename, pface - 7 + 1)
		else
			nodename = string.sub(nodename, 1, -2) .. newstate
		end

		self.node.name = nodename
		self:set_node(self.node)
	end,

	on_rightclick = function(self, clicker)
		local pos = self.object:get_pos()
		local ppos = clicker:get_pos()
		local pvect = clicker:get_look_dir()
		local pface = get_face(pos, ppos, pvect)

		if pface == nil then
			return
		end

		local pos_under = vector.round(pos)
		local pos_above = { x = pos_under.x, y = pos_under.y, z = pos_under.z }
		local index = ({ "x", "y", "z" })[math.floor((pface + 1) / 2)]
		pos_above[index] = pos_above[index] + 2 * ((pface + 1) % 2) - 1
		local pointed_thing = { type = "node", under = pos_under, above = pos_above }
		local itemstack = clicker:get_wielded_item()
		local itemdef = minetest.registered_items[itemstack:get_name()]

		if itemdef ~= nil then
			itemdef.on_place(itemstack, clicker, pointed_thing)
		end
	end,
})

local crack = "crack_anylength.png^[verticalframe:5:0"
minetest.register_entity("frames:damage_entity", {
	initial_properties = {
		visual = "cube",
		visual_size = { x = 1.01, y = 1.01 },
		textures = { crack, crack, crack, crack, crack, crack },
		collisionbox = { 0, 0, 0, 0, 0, 0 },
		physical = false,
	},
	on_step = function(self, dtime)
		if self.remaining_time == nil then
			self.object:remove()
			self.frame_object.damage_object = nil
		end
		self.remaining_time = self.remaining_time - dtime
		if self.remaining_time < 0 then
			self.object:remove()
			self.frame_object.damage_object = nil
		end
		self.texture_change_time = self.texture_change_time - dtime
		if self.texture_change_time < 0 then
			self.texture_change_time = self.texture_change_time + 0.15
			self.texture_index = self.texture_index + 1
			if self.texture_index == 5 then
				self.object:remove()
				self.frame_object.damage_object = nil
				self.frame_object:dig()
			end
			local ct = "crack_anylength.png^[verticalframe:5:" .. self.texture_index
			self.object:set_properties({ textures = { ct, ct, ct, ct, ct, ct } })
		end
	end,
})

mesecon.register_mvps_unmov("frames:frame_entity")
mesecon.register_mvps_unmov("frames:damage_entity")
mesecon.register_on_mvps_move(function(moved_nodes)
	local to_move = {}
	for _, n in ipairs(moved_nodes) do
		if frames_pos[pos_to_string(n.oldpos)] ~= nil then
			to_move[#to_move + 1] = {
				pos = n.pos,
				oldpos = n.oldpos,
				name = frames_pos[pos_to_string(n.oldpos)]
			}
			frames_pos[pos_to_string(n.oldpos)] = nil
		end
	end
	if #to_move > 0 then
		for _, t in ipairs(to_move) do
			frames_pos[pos_to_string(t.pos)] = t.name
			local objects = minetest.get_objects_inside_radius(t.oldpos, 0.1)
			for _, obj in ipairs(objects) do
				local entity = obj:get_luaentity()
				if entity and (entity.name == "frames:frame_entity" or
						entity.name == "frames:damage_entity") then
					obj:set_pos(t.pos)
				end
			end
		end
	end
end)

minetest.register_on_dignode(function(pos, node)
	if frames_pos[pos_to_string(pos)] ~= nil then
		minetest.set_node(pos, { name = frames_pos[pos_to_string(pos)] })
		frames_pos[pos_to_string(pos)] = nil
		local objects = minetest.get_objects_inside_radius(pos, 0.1)
		for _, obj in ipairs(objects) do
			local entity = obj:get_luaentity()
			if entity and (entity.name == "frames:frame_entity" or entity.name == "frames:damage_entity") then
				obj:remove()
			end
		end
	end
end)

-- Frame motor
local function connected(pos, c, adj)
	for _, vect in ipairs(adj) do
		local pos1 = vector.add(pos, vect)
		local nodename = minetest.get_node(pos1).name
		if frames_pos[pos_to_string(pos1)] then
			nodename = frames_pos[pos_to_string(pos1)]
		end
		if not pos_in_list(c, pos1) and nodename ~= "air" and
			(minetest.registered_nodes[nodename].frames_can_connect == nil or
				minetest.registered_nodes[nodename].frames_can_connect(pos1, vect)) then
			c[#c + 1] = pos1
			if minetest.registered_nodes[nodename].frame == 1 then
				local adj2 = minetest.registered_nodes[nodename].frame_connect_all(nodename)
				connected(pos1, c, adj2)
			end
		end
	end
end

local function get_connected_nodes(pos)
	local c = { pos }
	local nodename = minetest.get_node(pos).name
	if frames_pos[pos_to_string(pos)] then
		nodename = frames_pos[pos_to_string(pos)]
	end
	connected(pos, c, minetest.registered_nodes[nodename].frame_connect_all(nodename))
	return c
end

local function frame_motor_on(pos, node)
	local dirs = {
		{ x = 0, y = 1, z = 0 }, { x = 0, y = 0, z = 1 },
		{ x = 0, y = 0, z = -1 }, { x = 1, y = 0, z = 0 },
		{ x = -1, y = 0, z = 0 }, { x = 0, y = -1, z = 0 }
	}
	local nnodepos = vector.add(pos, dirs[math.floor(node.param2 / 4) + 1])
	local dir = minetest.facedir_to_dir(node.param2)
	local nnode = minetest.get_node(nnodepos)

	if frames_pos[pos_to_string(nnodepos)] then
		nnode.name = frames_pos[pos_to_string(nnodepos)]
	end

	local meta = minetest.get_meta(pos)
	if meta:get_int("last_moved") == minetest.get_gametime() then
		return
	end

	local owner = meta:get_string("owner")
	if minetest.registered_nodes[nnode.name].frame == 1 then
		local connected_nodes = get_connected_nodes(nnodepos)
		move_nodes_vect(connected_nodes, dir, pos, owner)
	end

	minetest.get_meta(vector.add(pos, dir)):set_int("last_moved", minetest.get_gametime())
end

minetest.register_node("frames:frame_motor", {
	description = S("Frame Motor"),
	tiles = {
		"pipeworks_filter_top.png^[transformR90", "technic_lv_cable.png", "technic_lv_cable.png",
		"technic_lv_cable.png", "technic_lv_cable.png", "technic_lv_cable.png"
	},
	groups = { snappy = 2, choppy = 2, oddly_breakable_by_hand = 2, mesecon = 2 },
	paramtype2 = "facedir",
	mesecons = { effector = { action_on = frame_motor_on } },

	after_place_node = function(pos, placer, itemstack)
		local meta = minetest.get_meta(pos)
		meta:set_string("owner", placer:get_player_name())
	end,

	frames_can_connect = function(pos, dir)
		local node = minetest.get_node(pos)
		local dir2 = ({
			{ x = 0, y = 1, z = 0 }, { x = 0, y = 0, z = 1 },
			{ x = 0, y = 0, z = -1 }, { x = 1, y = 0, z = 0 },
			{ x = -1, y = 0, z = 0 }, { x = 0, y = -1, z = 0 }
		})[math.floor(node.param2 / 4) + 1]
		return dir2.x ~= -dir.x or dir2.y ~= -dir.y or dir2.z ~= -dir.z
	end
})

-- Crafts
minetest.register_craft({
	output = 'frames:frame_111111',
	recipe = {
		{ '',              'default:stick',               '' },
		{ 'default:stick', 'basic_materials:brass_ingot', 'default:stick' },
		{ '',              'default:stick',               '' },
	}
})

minetest.register_craft({
	output = 'frames:frame_motor',
	recipe = {
		{ '',                                  'frames:frame_111111',   '' },
		{ 'group:mesecon_conductor_craftable', 'basic_materials:motor', 'group:mesecon_conductor_craftable' },
		{ '',                                  'frames:frame_111111',   '' },
	}
})
