-- Renderer.lua：E.render 的 UrhoX 后端。把网页版每帧生成的绘制列表（模型 + 4x4 矩阵 + 颜色替换）转成 UrhoX 节点：
-- 同一模型 / 同一颜色的节点放进对象池复用；矩阵分解为 位置 / 旋转 / 统一缩放；相机、灯光、辉光参数取自 f.env。
local VB = require("game.VoxelBuilder")
local R = { pools = {}, protos = {}, variants = {}, lastEnvSig = nil }
local sqrt = math.sqrt
local scene_, camNode_, camera_, drawRoot_, protoRoot_, zone_, starZone_, keyNode_, keyLight_, fillNode_, fillLight_, renderPath_
-- 星空节点：每份星点数据（战斗一份、召唤页一份）各建一次并缓存；本帧不用的隐藏（网页版 f.stars 为空时不画星空）
local starNodes_, starOn_ = setmetatable({}, { __mode = "k" }), nil
R.STAR_ZONE_MASK = 2
function R.Init(o)
    scene_, camNode_, camera_ = o.scene, o.camNode, o.camera
    zone_, keyNode_, keyLight_, fillNode_, fillLight_, renderPath_ = o.zone, o.keyNode, o.keyLight, o.fillNode, o.fillLight, o.renderPath
    starZone_ = o.starZone
    drawRoot_ = scene_:CreateChild("Draws"); protoRoot_ = scene_:CreateChild("DrawProtos")
end
local function quant(v) return math.floor(v * 8 + 0.5) end
local MAX_VARIANTS = 160
-- 颜色替换的量化：特效模型（fx_）亮度超过 1 的部分在 LDR 下只会被截掉，先按最大通道归一（保留色相），能少很多变体
local function tintQ(id, tint)
    local r, g, b = math.max(0, tint[0]), math.max(0, tint[1]), math.max(0, tint[2])
    if id:sub(1, 3) == "fx_" then local m = math.max(r, g, b); if m > 1 then r, g, b = r / m, g / m, b / m end end
    return quant(r), quant(g), quant(b)
end
local function keyOf(id, tint)
    if not tint then return id, 0, 0, 0 end
    local qr, qg, qb = tintQ(id, tint); return id .. "|" .. qr .. "," .. qg .. "," .. qb, qr, qg, qb
end
local function proto(id, tint)
    local key, qr, qg, qb = keyOf(id, tint)
    local p = R.protos[key]; if p ~= nil then return p or nil, key end
    if tint then
        local list = R.variants[id]; if not list then list = {}; R.variants[id] = list end
        if #list >= MAX_VARIANTS then
            -- v1.4.3：颜色变体太多时借用最接近的已有颜色（原来退回无色模型，玩几分钟后攻击特效全变成白色）
            local best, bd = nil, math.huge
            for _, v in ipairs(list) do local d = (v[1] - qr) ^ 2 + (v[2] - qg) ^ 2 + (v[3] - qb) ^ 2; if d < bd then bd, best = d, v end end
            p = R.protos[best[4]]; R.protos[key] = p; return p, key
        end
        local c = { (qr / 8) ^ (1 / 2.2), (qg / 8) ^ (1 / 2.2), (qb / 8) ^ (1 / 2.2) }   -- 网页版 tint 是线性值，转成与模型颜色相同的空间
        p = VB.Build(protoRoot_, id, "proto_" .. key, c); list[#list + 1] = { qr, qg, qb, key }
    else p = VB.Build(protoRoot_, id, "proto_" .. key) end
    p:SetDeepEnabled(false); R.protos[key] = p; return p, key
end
-- v1.4.4 特效光晕：发光特效外面再画一层放大的叠加混合模型（每帧最多 HALO_MAX 个；引擎没有叠加技术时自动关闭）
-- v1.4.7：光晕只给“方块状”的小特效（白芯、火花）。激光、弹道、射线是细长模型，整体放大 2.2 倍再斜转 45 度后
-- 会变成交叉的“十”字和一条粗粉色斜纹带（v1.4.6 的问题）；经验宝石也不再加光晕，避免和特效混在一起。
local HALO_IDS = { fx_white = 1.0, fx_spark = 0.8 }
local HALO_MAX, HALO_SCALE, HALO_K = 90, 1.8, 0.18
-- v1.4.6 柔和特效：发光特效本体也改为叠加混合（像光一样叠加、不再是实心方块），光晕绕 (1,1,1) 轴转 45 度，叠在本体上轮廓更圆
local ADD_IDS = { fx_white = true, fx_white_bolt = true, fx_spark = true, fx_laser_player = true, fx_laser_enemy = true }
local QW, QX = 0.92388, 0.22095
local function haloProto(id, tint, key)
    local hk = "halo|" .. key
    local p = R.protos[hk]; if p ~= nil then return p or nil, hk end
    if not VB.AddTechnique() then R.protos[hk] = false; return nil, hk end
    local c = nil
    if tint then local qr, qg, qb = key:match("|(%d+),(%d+),(%d+)$"); if qr then c = { (tonumber(qr) / 8) ^ (1 / 2.2), (tonumber(qg) / 8) ^ (1 / 2.2), (tonumber(qb) / 8) ^ (1 / 2.2) } end end
    p = VB.Build(protoRoot_, id, "proto_" .. hk, c, { halo = HALO_K * (HALO_IDS[id] or 1) }); p:SetDeepEnabled(false); R.protos[hk] = p; return p, hk
end
local function addProto(id, tint)
    local _, key = proto(id, tint); local ak = "add|" .. key                       -- 颜色键先经过 proto()：变体数受 MAX_VARIANTS 限制，超出时借用最接近的颜色
    local p = R.protos[ak]; if p ~= nil then return p or nil, ak end
    if not VB.AddTechnique() then R.protos[ak] = false; return nil, ak end
    local c = nil
    if tint then local qr, qg, qb = key:match("|(%d+),(%d+),(%d+)$"); if qr then c = { (tonumber(qr) / 8) ^ (1 / 2.2), (tonumber(qg) / 8) ^ (1 / 2.2), (tonumber(qb) / 8) ^ (1 / 2.2) } end end
    p = VB.Build(protoRoot_, id, "proto_" .. ak, c, { halo = 0.95 }); p:SetDeepEnabled(false); R.protos[ak] = p; return p, ak
end
local function acquireKey(p, key)
    local pool = R.pools[key]; if not pool then pool = { list = {}, n = 0, on = 0 }; R.pools[key] = pool end
    pool.n = pool.n + 1
    local node = pool.list[pool.n]
    if not node then node = p:Clone(); node:SetParent(drawRoot_); pool.list[pool.n] = node end
    node:SetDeepEnabled(true)
    return node
end
local function acquire(id, tint)
    local p, key = proto(id, tint)
    if not p then if tint then return acquire(id, nil) end return nil end
    local pool = R.pools[key]; if not pool then pool = { list = {}, n = 0, on = 0 }; R.pools[key] = pool end
    pool.n = pool.n + 1
    local node = pool.list[pool.n]
    if not node then node = p:Clone(); node:SetParent(drawRoot_); pool.list[pool.n] = node end
    node:SetDeepEnabled(true)
    return node
end
local function quat(m, sx)
    local r00, r10, r20, r01, r11, r21, r02, r12, r22 = m[0] / sx, m[1] / sx, m[2] / sx, m[4] / sx, m[5] / sx, m[6] / sx, m[8] / sx, m[9] / sx, m[10] / sx
    local tr = r00 + r11 + r22; local w, x, y, z
    if tr > 0 then local s = sqrt(tr + 1) * 2; w = 0.25 * s; x = (r21 - r12) / s; y = (r02 - r20) / s; z = (r10 - r01) / s
    elseif r00 > r11 and r00 > r22 then local s = sqrt(1 + r00 - r11 - r22) * 2; w = (r21 - r12) / s; x = 0.25 * s; y = (r01 + r10) / s; z = (r02 + r20) / s
    elseif r11 > r22 then local s = sqrt(1 + r11 - r00 - r22) * 2; w = (r02 - r20) / s; x = (r01 + r10) / s; y = 0.25 * s; z = (r12 + r21) / s
    else local s = sqrt(1 + r22 - r00 - r11) * 2; w = (r10 - r01) / s; x = (r02 + r20) / s; y = (r12 + r21) / s; z = 0.25 * s end
    return w, x, y, z
end
function R.Env(env)
    local sig = tostring(env.bg[0]) .. tostring(env.ambient[0]) .. tostring(env.key.brightness) .. tostring(env.bloom and env.bloom.mix) .. tostring(R.glow) .. tostring(env.fog[0])
    if sig == R.lastEnvSig then return end
    R.lastEnvSig = sig
    -- v1.4.4 颜色校正：环境光 x0.85、主光 x1.15，拉开明暗层次（原来整体偏灰、发平）
    zone_.ambientColor = Color(env.ambient[0] * 0.85, env.ambient[1] * 0.85, env.ambient[2] * 0.85); zone_.fogColor = Color(env.bg[0], env.bg[1], env.bg[2])
    if starZone_ then starZone_.ambientColor = zone_.ambientColor; starZone_.fogColor = Color(env.bg[0], env.bg[1], env.bg[2]) end
    keyNode_.direction = Vector3(env.key.dir[0], env.key.dir[1], env.key.dir[2]):Normalized(); keyLight_.color = Color(env.key.color[0], env.key.color[1], env.key.color[2]); keyLight_.brightness = env.key.brightness * 1.15
    fillNode_.direction = Vector3(env.fill.dir[0], env.fill.dir[1], env.fill.dir[2]):Normalized(); fillLight_.color = Color(env.fill.color[0], env.fill.color[1], env.fill.color[2]); fillLight_.brightness = env.fill.brightness
    -- 雾：网页版是 mix(col, bg, f*f)，f 从 fog[0] 到 fog[1] 线性增长；UrhoX 雾是线性混合，起点后移 25% 来近似二次曲线
    zone_.fogStart = env.fog[0] + (env.fog[1] - env.fog[0]) * 0.25; zone_.fogEnd = env.fog[1]
    -- 辉光：网页版在线性空间用 smoothstep(thr, thr + 1.2, 最大通道) 取亮部；UrhoX 的 Bloom 在 gamma 空间硬阈值，所以把阈值换算到 gamma 空间（thr^(1/2.2)）
    local thr = math.min(0.9, env.bloom.threshold ^ (1 / 2.2) * 0.94); local mix = env.bloom.mix * (R.glow or 1) * 0.82   -- v1.4.6：辉光再柔一点
    renderPath_:SetShaderParameter("BloomThreshold", Variant(thr)); renderPath_:SetShaderParameter("BloomMix", Variant(Vector2(1.0, mix)))
end
-- E.backend：f = { env, eye, target, fov, aspect, near, far, draws, stars }
function R.Stats() local n, d = 0, 0; for _, p in pairs(R.pools) do n = n + #p.list; d = d + p.n end return n, d end
function R.Frame(f, VP)
    R.Env(f.env)
    camNode_.position = Vector3(f.eye[0], f.eye[1], f.eye[2]); camNode_:LookAt(Vector3(f.target[0], f.target[1], f.target[2])); camera_.fov = f.fov
    -- 星空：以相机为中心（网页版：星点不受雾影响，见 VoxelBuilder.BuildStars 与 GameApp 的无雾星空区域）
    local sn = nil
    if f.stars then
        sn = starNodes_[f.stars]
        if not sn then
            local st = f.stars.stars; local d = {}; for i = 0, st.data.length - 1 do d[#d + 1] = st.data[i] end
            local cols = {}; for i = 0, st.colors.length - 1 do local c = st.colors[i]; cols[#cols + 1] = { c[0], c[1], c[2] } end
            sn = VB.BuildStars(scene_, { data = d, colors = cols, zoneMask = starZone_ and R.STAR_ZONE_MASK or nil }); starNodes_[f.stars] = sn
            sn:SetEnabled(false)
        end
        sn.position = Vector3(f.eye[0], f.eye[1], f.eye[2])
    end
    if starOn_ ~= sn then
        if starOn_ then starOn_:SetEnabled(false) end
        if sn then sn:SetEnabled(true) end
        starOn_ = sn
    end
    for _, p in pairs(R.pools) do p.n = 0 end
    local halos, haloOn, addOn = 0, (R.glow or 1) >= 0.8 and R.halo ~= false, R.softFx ~= false
    local draws = f.draws
    for i = 0, draws.length - 1 do
        local d = draws[i]; local m = d.m.d or d.m
        local sx = sqrt(m[0] * m[0] + m[1] * m[1] + m[2] * m[2])
        if sx > 1e-6 and d.mesh then
            local id = d.mesh.id; local node = nil
            if addOn and ADD_IDS[id] then local ap, ak = addProto(id, d.tint); if ap then node = acquireKey(ap, ak) end end
            if not node then node = acquire(id, d.tint) end
            if node then
                local px, py, pz = m[12], m[13], m[14]; local w, x, y, z = quat(m, sx)
                node.position = Vector3(px, py, pz); node.rotation = Quaternion(w, x, y, z); node:SetScale(sx)
                if haloOn and HALO_IDS[id] and halos < HALO_MAX then
                    local _, rk = proto(id, d.tint); local hp, hk = haloProto(id, d.tint, rk)
                    if hp then
                        halos = halos + 1; local hn = acquireKey(hp, hk); hn.position = Vector3(px, py, pz)
                        hn.rotation = Quaternion(w * QW - (x + y + z) * QX, w * QX + x * QW + (y - z) * QX, w * QX + y * QW + (z - x) * QX, w * QX + z * QW + (x - y) * QX)
                        hn:SetScale(sx * HALO_SCALE)
                    end
                end
            end
        end
    end
    for _, p in pairs(R.pools) do
        for i = p.n + 1, p.on do p.list[i]:SetEnabled(false) end
        p.on = p.n
    end
end
return R
