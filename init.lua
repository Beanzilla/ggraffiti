local t = minetest.get_translator("ggraffiti")
local aabb = dofile(minetest.get_modpath("ggraffiti") .. "/aabb.lua")
dofile(minetest.get_modpath("ggraffiti") .. "/canvas.lua")
_ = modlib.minetest

local SPRAY_LENGTH = 60
local SPRAY_INTERVAL = 0.0045
local MAX_SPRAY_DISTANCE = 4

local TRANSPARENT = "#00000000"
-- The color of the pixel at (8, 9) in the dye texture.
local DYE_COLORS = {
    black = "#292929",
    blue = "#00519d",
    brown = "#6c3800",
    cyan = "#00959d",
    dark_green = "#2b7b00",
    dark_grey = "#494949",
    green = "#67eb1c",
    grey = "#9c9c9c",
    magenta = "#d80481",
    orange = "#e0601a",
    pink = "#ffa5a5",
    red = "#c91818",
    violet = "#480680",
    white = "#eeeeee",
    yellow = "#fcf611",
}

local player_lasts = {}

local function spraycast(player, pos, dir, def)
    local ray = minetest.raycast(pos, pos + dir * MAX_SPRAY_DISTANCE, true, false)
    local pthing
    for i_pthing in ray do
        if i_pthing.ref ~= player then
            pthing = i_pthing
            break
        end
    end
    if not pthing or pthing.type ~= "node" then return end

    local node_pos = pthing.under
    -- There is no such function. :(
    -- local raw_box = minetest.get_node_selection_boxes(pthing.under)[pthing.box_id]
    local raw_box = modlib.minetest.get_node_selectionboxes(pthing.under)[pthing.box_id]
    if not raw_box then return end -- Modlib failed 😱
    local box = aabb.from(raw_box)
    box:repair()
    local box_center = box:get_center()

    local canvas_rot = vector.dir_to_rotation(pthing.intersection_normal)
    local rot_box = aabb.new(
        box.pos_min:rotate(canvas_rot),
        box.pos_max:rotate(canvas_rot)
    )
    rot_box:repair()
    local rot_box_size = rot_box:get_size()

    local canvas_pos = node_pos + box_center + vector.new(0, 0, rot_box_size.z * 0.5 + 0.001):rotate(canvas_rot)
    local canvas

    local findings = minetest.get_objects_inside_radius(canvas_pos, 0.001)
    for _, fobj in ipairs(findings) do
        local fent = fobj:get_luaentity()
        if fent and fent.name == "ggraffiti:canvas" then
            canvas = fent
            break
        end
    end

    if not canvas then
        if def.anti then return end

        local obj = minetest.add_entity(canvas_pos, "ggraffiti:canvas")
        obj:set_rotation(canvas_rot)

        canvas = obj:get_luaentity()
        canvas.size = {x = rot_box_size.x, y = rot_box_size.y}
        canvas:create_bitmap()
    end

    local root_pos = node_pos + box_center + vector.new(0, 0, rot_box_size.z * 0.5):rotate(canvas_rot)
    local pointed_pos = pthing.intersection_point
    local distance = pointed_pos - root_pos

    local pos_on_face = vector.new(-distance.x, -distance.y, distance.z):rotate(canvas_rot) -- 2D (Z is always zero)
    pos_on_face = pos_on_face + vector.new(rot_box_size.x / 2, rot_box_size.y / 2, 0)

    local pos_on_bitmap = vector.new( -- 2D too, of course
        math.floor(pos_on_face.x / rot_box_size.x * canvas.bitmap_size.x),
        math.floor(pos_on_face.y / rot_box_size.y * canvas.bitmap_size.y),
        0
    )
    local index = pos_on_bitmap.y * canvas.bitmap_size.x + pos_on_bitmap.x + 1

    if def.anti then
        if canvas.bitmap[index] ~= TRANSPARENT then
            canvas.bitmap[index] = TRANSPARENT
            if canvas:is_bitmap_empty() then
                canvas.object:remove()
            else
                canvas:update()
            end
        end
    else
        if canvas.bitmap[index] ~= def.color then
            canvas.bitmap[index] = def.color
            canvas:update()
        end
    end
end

local function spray_can_on_use(item, player)
    -- Related stuff:
    -- Server::handleCommand_PlayerPos
    -- (https://github.com/minetest/minetest/blob/5.6.1/src/network/serverpackethandler.cpp#L512)
    -- Server::handleCommand_Interact
    -- (https://github.com/minetest/minetest/blob/5.6.1/src/network/serverpackethandler.cpp#L916)
    -- Server::process_PlayerPos
    -- (https://github.com/minetest/minetest/blob/5.6.1/src/network/serverpackethandler.cpp#L459)
    -- If no malicious / buggy client involved:
    -- assert(player:get_player_control().dig)

    local pos = player:get_pos()
    pos.y = pos.y + player:get_properties().eye_height
    local dir = player:get_look_dir()

    spraycast(player, pos, dir, item:get_definition()._ggraffiti_spray_can)
    player_lasts[player:get_player_name()] = { pos = pos, dir = dir }
end

minetest.register_tool("ggraffiti:spray_can_empty", {
    description = t("Empty Spray Can"),
    inventory_image = "ggraffiti_spray_can.png",

    range = MAX_SPRAY_DISTANCE,
    on_use = function() end,

    groups = {ggraffiti_spray_can = 1},
})

for _, dye in ipairs(dye.dyes) do
    local dye_name, dye_desc = unpack(dye)
    local dye_color = DYE_COLORS[dye_name]

    local item_name = "ggraffiti:spray_can_" .. dye_name

    minetest.register_tool(item_name, {
        description = t("Graffiti Spray Can (" .. dye_desc:lower() .. ")"),
        inventory_image = "ggraffiti_spray_can.png^(ggraffiti_spray_can_color.png^[multiply:" .. dye_color .. ")",

        range = MAX_SPRAY_DISTANCE,
        on_use = spray_can_on_use,
        _ggraffiti_spray_can = {
            color = dye_color,
        },

        groups = {ggraffiti_spray_can = 1},
    })

    minetest.register_craft({
        recipe = {
            {"default:steel_ingot"},
            {"dye:" .. dye_name},
            {"default:steel_ingot"},
        },
        output = item_name,
    })
end

minetest.register_tool("ggraffiti:spray_can_anti", {
    description = t("Anti-Graffiti Spray Can"),
    inventory_image = "ggraffiti_spray_can_anti.png",

    range = MAX_SPRAY_DISTANCE,
    on_use = spray_can_on_use,
    _ggraffiti_spray_can = {
        anti = true,
    },

    groups = {ggraffiti_spray_can = 1},
})

minetest.register_craft({
    recipe = {
        {"default:steel_ingot"},
        {"flowers:mushroom_red"},
        {"default:steel_ingot"},
    },
    output = "ggraffiti:spray_can_anti",
})

minetest.register_craft({
    type = "cooking",
    recipe = "group:ggraffiti_spray_can",
    output = "default:steel_ingot 2",
})

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function wear_out(item)
    item:add_wear_by_uses(SPRAY_LENGTH / SPRAY_INTERVAL)
    if item:is_empty() then
        return ItemStack("ggraffiti:spray_can_empty"), false
    end
    return item, true
end

minetest.register_globalstep(function(dtime)
    for _, player in ipairs(minetest.get_connected_players()) do
        local player_name = player:get_player_name()

        if player:get_player_control().dig then
            local item = player:get_wielded_item()
            local def = item:get_definition()

            if def._ggraffiti_spray_can then
                local last = player_lasts[player_name]

                local now_pos = player:get_pos()
                now_pos.y = now_pos.y + player:get_properties().eye_height
                local now_dir = player:get_look_dir()

                if last then
                    local n_steps = math.round(dtime / SPRAY_INTERVAL)

                    for step_n = 1, n_steps do
                        local alive
                        item, alive = wear_out(item)
                        if not alive then
                            n_steps = step_n
                            break
                        end
                    end
                    player:set_wielded_item(item)

                    if not now_pos:equals(last.pos) or not now_dir:equals(last.dir) then
                        for step_n = 1, n_steps do
                            local combine_lerp = function(a, b)
                                return lerp(a, b, step_n / n_steps)
                            end
                            local pos = vector.combine(last.pos, now_pos, combine_lerp)
                            local dir = vector.combine(last.dir, now_dir, combine_lerp):normalize()

                            spraycast(player, pos, dir, def._ggraffiti_spray_can)
                        end
                    end
                end

                player_lasts[player_name] = { pos = now_pos, dir = now_dir }
            else
                player_lasts[player_name] = nil
            end
        else
            player_lasts[player_name] = nil
        end
    end
end)
