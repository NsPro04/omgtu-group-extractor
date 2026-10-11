local json = require "json"
local fs_read = require "lua_fs".read
local postgres = require "postgres"
dump = require "dump".dump

local postgres_driver = require "luasql.postgres"
local postgres_env    = postgres_driver.postgres()
local connection      = postgres_env:connect(table.concat({
	"dbname=",   os.getenv("POSTGRES_DBNAME"),   " ",
	"user=",     os.getenv("POSTGRES_USER"),     " ",
	"password=", os.getenv("POSTGRES_PASSWORD"), " ",
	"host=",     os.getenv("POSTGRES_HOST"),     " ",
	"port=",     os.getenv("POSTGRES_PORT"),     " ",
	"sslmode=",  os.getenv("POSTGRES_SSLMODE")
}, ""))

connection:setautocommit(true)

local function execute(statement)
	local cursor, err = connection:execute(statement)

	if cursor then
		local res = cursor:fetch({}, "a")
		if res then
			return res, nil
		end
		return nil, nil
	else
		return nil, tostring(err)
	end
end

--[[
do
	local data, err = json.decode(fs_read("./file0.json"))
	dump("err: ", {err})

	for _, row in ipairs(data) do
		dump(row)

		if next(row.subgroups) then
			for _, subgroup_data in ipairs(row.subgroups) do
				local subgroup_id, some_data = next(subgroup_data)

				local subgroup = some_data.name:sub(-1)
				local row_, err = execute("\
					WITH row AS (INSERT INTO subgroups SELECT\
						"..(subgroup_id)..",\
						"..(some_data.group_id)..",\
						"..(subgroup)..",\
						'"..(some_data.name).."'\
					FROM (VALUES(0)) RETURNING *)\
					SELECT * FROM row;\
				")

				if err then
					dump(err)
				end
			end
		end
	end
end
]]

do
	local data, err = json.decode(fs_read("./file0.json"))
	dump("err: ", {err})

	for _, row in ipairs(data) do
		dump(row)

		if next(row.groups) then
			for _, group_data in ipairs(row.groups) do
				local group_id, some_data = next(group_data)

				local row_, err = execute("\
					WITH row AS (INSERT INTO groups SELECT\
						"..(group_id)..",\
						'"..(some_data.name).."'\
					FROM (VALUES(0)) RETURNING *)\
					SELECT * FROM row;\
				")

				if err then
					dump(err)
				end
			end
		elseif next(row.subgroups) then
			for _, subgroup_data in ipairs(row.subgroups) do
				local subgroup_id, some_data = next(subgroup_data)

				local group_name = some_data.name:sub(0, -3)

				local row_, err = execute("\
					WITH row AS (INSERT INTO groups SELECT\
						"..(some_data.group_id)..",\
						'"..(group_name).."'\
					FROM (VALUES(0)) RETURNING *)\
					SELECT * FROM row;\
				")

				if err then
					dump(err)
				end
			end
		end
	end
end

--[=[
require "utils"

local socket = require "socket"

local getCurrentTime = require "getCurrentTime"
local http_request   = require "http.request"
local json           = require "json"


local file, err = io.open("/f1.json", "wb")
if file == nil then
	print("io.open err: " .. tostring(err))
	return nil
end

local file2, err = io.open("/f2.txt", "wb")
if file2 == nil then
	print("io.open err: " .. tostring(err))
	return nil
end

local function dump(...) ----
	file2:write(dumps(...))
	file2:write(",\n")
	file2:flush()
end

do
	local t = getCurrentTime()
	for group_id=1, 1000 do
		local data = { -------
			groups = {},
			subgroups = {},
		} ------

		dump(group_id .. " " .. (getCurrentTime() - t))
		for _, month in ipairs({
			"?start=2024.09.1&finish=2024.09.30",
			"?start=2024.10.1&finish=2024.10.31",
			"?start=2024.11.1&finish=2024.11.30",
			"?start=2024.12.1&finish=2024.12.31",

			"?start=2025.1.1&finish=2025.1.31",
			"?start=2025.2.1&finish=2025.2.28",
			"?start=2025.3.1&finish=2025.3.31",
			"?start=2025.4.1&finish=2025.4.30",
			"?start=2025.5.1&finish=2025.5.31",
			"?start=2025.6.1&finish=2025.6.30"
		}) do
			local headers, stream, body_str, body, err
			headers, stream = http_request.new_from_uri("https://rasp.omgtu.ru/api/schedule/group/"..group_id..month):go(10)
			if not headers then dump("not headers", group_id, month) goto CONTINUE end

			body_str = stream:get_body_as_string(10)

			body, err = json.decode(body_str)
			if err or type(body) ~= "table" or #body == 0 then --[[dump("err or type(body) ~= \"table\" or #body == 0")]] goto CONTINUE end

			for _, schedule in ipairs(body) do
				if type(schedule.listSubGroups) == "table" and #schedule.listSubGroups > 0 then
					for _, subgroup in ipairs(schedule.listSubGroups) do
						if subgroup.subgroup_groupOid == group_id then
							local key = tostring(subgroup.subgroupOid)
							if data.subgroups[key] then
								--[[dump("ERR data.subgroups[key] already exists!", group_id, month)]]
							else
								data.subgroups[key] = {
									name = subgroup.subgroup,
									group_id = group_id
								}
							end
						end
					end
				elseif type(schedule.listGroups) == "table" and #schedule.listGroups > 0 then
					for _, group in ipairs(schedule.listGroups) do
						if group.groupOid == group_id then
							local key = tostring(group.groupOid)
							if data.groups[key] then
								--[[dump("ERR data.groups[key] already exists!", group_id, month)]]
							else
								data.groups[key] = {
									name = group.group
								}
							end
						end
					end
				end
			end

			::CONTINUE::
			socket.sleep(0.5)

			local row_count = 0

			for subgroup_id, data in pairs(data.subgroups) do
				if data.group_id == group_id then
					row_count = row_count + 1
				end
			end

			if row_count > 1 then break end
		end

		local content, err = json.encode(data, false) -----

		if err then
			dump("jsonWriteFile json.encode err: " .. tostring(err))
		else
			file:write(content)
			file:write(",\n")
			file:flush()
		end ---------
	end

	dump("DONE! " .. (getCurrentTime() - t))
end

file:close()
file2:close()

-- jsonWriteFile("/data.json", data, false)
]=]