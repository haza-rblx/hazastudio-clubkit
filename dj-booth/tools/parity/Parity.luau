--!nocheck
-- Parity check, run on the client in Studio: dumps what the new panel draws (the same display-list
-- format as the prototype's goldens), drops what is covered by an opaque rect drawn later, and
-- matches every golden primitive against the new ones. Returns a short text report.
local Parity = {}

local function r1(n)
	return math.floor(n * 2 + 0.5) / 2
end

local function fontOf(o)
	local f = o.FontFace
	return string.match(f.Family, "([^/]+)%.json$") or f.Family, f.Weight.Name
end

-- the display list of a gui, normalised to `root` (design pixels)
function Parity.dump(gui, root, designWidth)
	local s = root.AbsoluteSize.X / (designWidth or 1250)
	local ox, oy = root.AbsolutePosition.X, root.AbsolutePosition.Y
	local out, order = {}, 0
	local function norm(x, y, w, h)
		return { r1((x - ox) / s), r1((y - oy) / s), r1(w / s), r1(h / s) }
	end
	local function visit(inst, clip)
		local myClip = clip
		if inst:IsA("GuiObject") then
			if not inst.Visible then
				return
			end
			local ap, as = inst.AbsolutePosition, inst.AbsoluteSize
			local x0, y0, x1, y1 = ap.X, ap.Y, ap.X + as.X, ap.Y + as.Y
			local cx0, cy0, cx1, cy1 =
				math.max(x0, clip[1]), math.max(y0, clip[2]), math.min(x1, clip[3]), math.min(y1, clip[4])
			local shown = cx1 > cx0 and cy1 > cy0
			if shown then
				order += 1
				local e = {
					o = order,
					k = inst.ClassName,
					n = inst.Name,
					r = norm(x0, y0, as.X, as.Y),
					path = inst:GetFullName(),
				}
				if cx0 ~= x0 or cy0 ~= y0 or cx1 ~= x1 or cy1 ~= y1 then
					e.c = norm(cx0, cy0, cx1 - cx0, cy1 - cy0)
				end
				if inst.Rotation ~= 0 then
					e.rot = inst.Rotation
				end
				if inst.BackgroundTransparency < 1 then
					e.bg = inst.BackgroundColor3:ToHex()
					if inst.BackgroundTransparency > 0 then
						e.bt = r1(inst.BackgroundTransparency * 100) / 100
					end
				end
				for _, m in inst:GetChildren() do
					if m:IsA("UICorner") then
						local cr = m.CornerRadius
						e.cr = r1((cr.Scale * math.min(as.X, as.Y) + cr.Offset * s) / s)
					elseif m:IsA("UIStroke") and m.Enabled and m.Transparency < 1 and m.Thickness > 0 then
						e.st = { m.Color:ToHex(), m.Thickness, r1(m.Transparency * 100) / 100 }
					elseif m:IsA("UIGradient") and m.Enabled then
						local ck = {}
						for _, kp in m.Color.Keypoints do
							table.insert(ck, { r1(kp.Time * 100) / 100, kp.Value:ToHex() })
						end
						e.gr = { ck, {}, m.Rotation }
					end
				end
				if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
					local text, ph = inst.Text, false
					if text == "" and inst:IsA("TextBox") then
						text, ph = inst.PlaceholderText, true
					end
					if text ~= "" and inst.TextTransparency < 1 then
						local fam, wt = fontOf(inst)
						local tb = inst.TextBounds
						e.t = {
							text,
							fam,
							wt,
							"Normal",
							r1(inst.TextSize),
							(ph and inst.PlaceholderColor3 or inst.TextColor3):ToHex(),
							r1(inst.TextTransparency * 100) / 100,
							inst.TextXAlignment.Name,
							inst.TextYAlignment.Name,
							r1(tb.X / s),
							r1(tb.Y / s),
						}
					end
				end
				if
					(inst:IsA("ImageLabel") or inst:IsA("ImageButton"))
					and inst.Image ~= ""
					and inst.ImageTransparency < 1
				then
					e.im = { inst.Image, inst.ImageColor3:ToHex() }
				end
				table.insert(out, e)
			end
			if inst.ClipsDescendants or inst:IsA("ScrollingFrame") then
				myClip = { cx0, cy0, cx1, cy1 }
				if not shown then
					return
				end
			end
		end
		local kids = {}
		for i, c in inst:GetChildren() do
			if c:IsA("GuiObject") then
				table.insert(kids, { c, c.ZIndex, i })
			end
		end
		table.sort(kids, function(a, b)
			if a[2] ~= b[2] then
				return a[2] < b[2]
			end
			return a[3] < b[3]
		end)
		for _, k in kids do
			visit(k[1], myClip)
		end
	end
	-- the whole gui (the modal sits beside the panel), panel first
	visit(root, { -1e6, -1e6, 1e6, 1e6 })
	for _, c in gui:GetChildren() do
		if c ~= root and c:IsA("GuiObject") and true then
			visit(c, { -1e6, -1e6, 1e6, 1e6 })
		end
	end
	return out
end

local function vis(e)
	return e.c or e.r
end

-- drop rects / texts fully covered by a later opaque, square-cornered rect
local function unoccluded(items)
	local covers = {}
	for _, e in items do
		if e.bg and not e.bt and not e.rot and (e.cr or 0) == 0 then
			table.insert(covers, e)
		end
	end
	local out = {}
	for _, e in items do
		local r = vis(e)
		local hidden = false
		for _, c in covers do
			if c.o > e.o then
				local q = vis(c)
				if
					q[1] <= r[1] + 0.5
					and q[2] <= r[2] + 0.5
					and q[1] + q[3] >= r[1] + r[3] - 0.5
					and q[2] + q[4] >= r[2] + r[4] - 0.5
				then
					hidden = true
					break
				end
			end
		end
		if not hidden then
			table.insert(out, e)
		end
	end
	return out
end

-- where the glyphs actually sit: the text box inside the element, by alignment
local function textBox(e)
	local r, t = e.r, e.t
	local tw, th = t[10], t[11]
	local x = if t[8] == "Left" then r[1] elseif t[8] == "Right" then r[1] + r[3] - tw else r[1] + (r[3] - tw) / 2
	local y = if t[9] == "Top" then r[2] elseif t[9] == "Bottom" then r[2] + r[4] - th else r[2] + (r[4] - th) / 2
	return x, y, tw, th
end

local function near(a, b, tol)
	return math.abs(a - b) <= tol
end

local function rectEq(a, b, tol)
	return near(a[1], b[1], tol) and near(a[2], b[2], tol) and near(a[3], b[3], tol) and near(a[4], b[4], tol)
end

-- primitives a display-list item contributes
local function prims(items)
	local out = {}
	for _, e in items do
		if e.bg then
			table.insert(out, { kind = "rect", e = e, key = e.bg .. "/" .. tostring(e.bt or 0) })
		end
		if e.t then
			table.insert(out, {
				kind = "text",
				e = e,
				key = e.t[1] .. "|" .. e.t[3] .. "|" .. e.t[5] .. "|" .. e.t[6] .. "|" .. tostring(e.t[7]),
			})
		end
		if e.im then
			table.insert(out, { kind = "image", e = e, key = e.im[1] .. "/" .. e.im[2] })
		end
		if e.st then
			table.insert(out, { kind = "stroke", e = e, key = e.st[1] .. "/" .. e.st[2] })
		end
	end
	return out
end

local function matches(g, n, tol)
	if g.kind ~= n.kind or g.key ~= n.key then
		return false
	end
	if g.kind == "text" then
		local gx, gy, gw, gh = textBox(g.e)
		local nx, ny, nw, nh = textBox(n.e)
		return near(gx, nx, tol) and near(gy, ny, tol) and near(gw, nw, tol + 1) and near(gh, nh, tol)
	end
	local ok = rectEq(vis(g.e), vis(n.e), tol)
	if ok and g.kind == "rect" then
		ok = near(g.e.cr or 0, n.e.cr or 0, 1) and (g.e.rot or 0) == (n.e.rot or 0)
	end
	return ok
end

local function describe(p)
	local e = p.e
	local r = vis(e)
	local s = string.format("%s %g,%g %gx%g", p.kind, r[1], r[2], r[3], r[4])
	if p.kind == "text" then
		s ..= " '" .. e.t[1] .. "' " .. e.t[3] .. " " .. e.t[5] .. " #" .. e.t[6]
	else
		s ..= " " .. p.key
	end
	if e.cr then
		s ..= " r" .. e.cr
	end
	return s
end

-- compare golden items with the new ones. `ignore` = list of {x0,y0,x1,y1} regions to skip
-- (live readouts that can't match a frozen mock).
function Parity.compare(golden, items, ignore, tol, maxList)
	tol = tol or 1
	maxList = maxList or 30
	local function skipped(p)
		local r = vis(p.e)
		for _, z in ignore or {} do
			if r[1] >= z[1] and r[2] >= z[2] and r[1] + r[3] <= z[3] and r[2] + r[4] <= z[4] then
				return true
			end
		end
		return false
	end
	local gp, np = {}, {}
	for _, p in prims(unoccluded(golden)) do
		if not skipped(p) then
			table.insert(gp, p)
		end
	end
	for _, p in prims(unoccluded(items)) do
		if not skipped(p) then
			table.insert(np, p)
		end
	end
	local used = {}
	local missing = {}
	local matched = 0
	for _, g in gp do
		local found = false
		for j, n in np do
			if not used[j] and matches(g, n, tol) then
				used[j] = true
				found = true
				break
			end
		end
		if found then
			matched += 1
		else
			table.insert(missing, g)
		end
	end
	local extra = {}
	for j, n in np do
		if not used[j] then
			table.insert(extra, n)
		end
	end
	local lines = {
		string.format(
			"matched %d / %d golden primitives (%.1f%%); %d new extra",
			matched,
			#gp,
			matched / math.max(#gp, 1) * 100,
			#extra
		),
	}
	table.sort(missing, function(a, b)
		local ra, rb = vis(a.e), vis(b.e)
		return ra[2] < rb[2] or (ra[2] == rb[2] and ra[1] < rb[1])
	end)
	table.sort(extra, function(a, b)
		local ra, rb = vis(a.e), vis(b.e)
		return ra[2] < rb[2] or (ra[2] == rb[2] and ra[1] < rb[1])
	end)
	table.insert(lines, "-- missing (golden not found):")
	for i = 1, math.min(#missing, maxList) do
		table.insert(lines, "  " .. describe(missing[i]))
	end
	table.insert(lines, "-- extra (new not in golden):")
	for i = 1, math.min(#extra, maxList) do
		table.insert(lines, "  " .. describe(extra[i]) .. "  <" .. string.sub(extra[i].e.path, -50) .. ">")
	end
	return table.concat(lines, "\n"), matched, #gp
end

return Parity
