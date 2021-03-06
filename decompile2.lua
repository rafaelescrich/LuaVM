local decompiler = require "luavm.decompiler2"
local bytecode = require "luavm.bytecode"

local lfs = require "lfs"

lfs.mkdir "decompiler2temp"

local function dumpValue(value, indent, skipTables)
	indent = indent or ""
	local typ = type(value)

	if typ == "table" and (not skipTables or not skipTables[value]) then
		if not skipTables then skipTables = {} end
		skipTables[value] = true
		local buffer = {"{"}
		local currentNumber = 1

		for i, v in pairs(value) do
			if i == currentNumber then
				currentNumber = currentNumber+1
				buffer[#buffer+1] = indent.."\t"..dumpValue(v, indent.."\t", skipTables)
			else
				buffer[#buffer+1] = indent.."\t"..dumpValue(i, indent.."\t", skipTables)..": "..dumpValue(v, indent.."\t", skipTables)
			end
		end

		return table.concat(buffer, "\n").."\n"..indent.."}"
	end

	return tostring(value)
end

--[[local function testFunc(a, b)
	return a+b+3
end]]

--[[local function testFunc(a, b)
	local c = a * b + 3
	if c < 0 then
		c = -c
	else
		c = c+c
	end
	return c
end]]

--[[local function testFunc()
	local a = 0
	for i=1, 100 do
		a = a+i
	end
	return a
end]]

--[[local function testFunc()
	for i, v in next, _G do
		print(i, v)
	end
end]]

--[[local function testFunc()
	local i = 100
	local v = 0
	while i > 0 do
		v = v+i
		i = i-1
		if v % 2 == 0 then
			break
		end
	end
	return v
end]]

--[[local function testFunc()
	while true do end
end]]

--[[local function testFunc()
	print("Hello, World!", 1, 2, 2+3)
	a,b = func()
	-- register swap
	local j,k = 1,2
	j,k=k,j
	-- global swap
	a,b,c = b,a,k
end]]

--[[local function testFunc()
	local testTable = {}
	testTable.a = 4
	return testTable.a
end]]

--[[local function testFunc()
	return {
		a = 5,
		b = 6,
		[4] = 3
	}
end]]

--[[local function testFunc()
	if (not x) and y then
		return 3
	end
end]]

local function testFunc()
	local x, y, z = 5, 6
	while x == 5 and y == 6 do
		if not z then
			z = {}
		end
		print(z)
	end
end

print(dumpValue(bc))
bytecode.dump(bc)
local decoder = decompiler.decoder.native()

local formatExpressionlets

local function formatExpressionlet(explet)
	if explet[1] == "register" then
		return "r"..explet[2]
	elseif explet[1] == "binaryop" then
		return formatExpressionlet(explet[2]).." "..explet[3].." "..formatExpressionlet(explet[4])
	elseif explet[1] == "unaryop" then
		return explet[2]..formatExpressionlet(explet[3])
	elseif explet[1] == "constant" then
		return bc.constants[explet[2]]
	elseif explet[1] == "global" then
		return bc.constants[explet[2]]
	elseif explet[1] == "value" then
		if type(explet[2]) == "table" then
			return "{}" -- TODO: Render table contents for table inlining
		end
		return tostring(explet[2])
	elseif explet[1] == "call" then
		return formatExpressionlet(explet[2]).."("..formatExpressionlets(explet[3])..")"
	elseif explet[1] == "index" then
		return formatExpressionlet(explet[2]).."["..formatExpressionlet(explet[3]).."]"
	else
		error("Unhandle explet "..tostring(explet[1]))
	end
end

function formatExpressionlets(explets)
	if #explets == 1 then
		return formatExpressionlet(explets[1])
	else
		local buffer = {}
		for i=1, #explets do
			buffer[i] = formatExpressionlet(explets[i])
		end
		return table.concat(buffer, ", ")
	end
end

--local formatBlock

local function formatDecoded(dec)
	if dec.disabled then return "" end
	if dec.op == "set" then
		if #dec.dest == 0 then
			return formatExpressionlets(dec.src)
		else
			return formatExpressionlets(dec.dest).." = "..formatExpressionlets(dec.src)
		end
	elseif dec.op == "return" then
		return "return "..formatExpressionlets(dec.src)
	elseif dec.op == "if" then
		return "if "..formatExpressionlets(dec.src).." then\n"..formatBlock(dec.block).."\nend"
	elseif dec.op == "else" then
		return "else\n"..formatBlock(dec.block)
	elseif dec.op == "for" then
		return "for "..formatExpressionlets(dec.dest).." = "..formatExpressionlets(dec.src).." do\n"..formatBlock(dec.block).."\nend"
	elseif dec.op == "gfor" then
		return "for "..formatExpressionlets(dec.dest).." in "..formatExpressionlets(dec.src).." do\n"..formatBlock(dec.block).."\nend"
	elseif dec.op == "while" then
		return "while "..formatExpressionlets(dec.src).." do\n"..formatBlock(dec.block).."\nend"
	elseif dec.op == "break" then
		return "break"
	end
	return dumpValue(dec)
end

function formatBlock(block)
	local decoded = {}
	for i=1, #block do
		decoded[i] = formatDecoded(block[i])
	end
	return table.concat(decoded, "\n")
end

-- Steps:
-- Decode
-- Analyze
-- Inline Pass
-- Analyze
-- Some other passes...
-- Output

local block = {}

local function printValue(value)
	--print(formatDecoded(value))
	block[#block+1] = value
end

decoder.decode(bc, nil, nil, {}, printValue)

for i=1, #block do
	print(formatDecoded(block[i]))
end

block.liveRanges = decompiler.analyzer.computeLiveRanges(block)

decompiler.pass[2](block)
decompiler.pass[1](block)

for i=1, #block do
	print(formatDecoded(block[i]))
end

print(decompiler.formatter.formatFunction(bc, block, "testFunc"))
