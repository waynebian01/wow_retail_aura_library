local addon, ns = ...

local MAJOR, MINOR = "LibRetailAuras-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
    return
end

local assert = assert
local pairs = pairs
local type = type
local math_abs = math.abs
local math_huge = math.huge
local math_max = math.max
local math_min = math.min
local table_remove = table.remove

local CreateFrame = CreateFrame
local GetTime = GetTime
local GetOverrideSpell = C_Spell.GetOverrideSpell
local IsSpellOverlayed = C_SpellActivationOverlay.IsSpellOverlayed

local addAuras, updateAuras, removeAuras = {}, {}, {} -- 添加、更新、移除光环
local events = {
    ["法术冷却"] = "SPELL_UPDATE_COOLDOWN", -- 冷却事件，玩家自身添加光环，玩家在目标施放光环，释放技能，都会触发此事件
    ["施法成功"] = "UNIT_SPELLCAST_SUCCEEDED", -- 成功事件
    ["图标改变"] = "SPELL_UPDATE_ICON", -- ICON事件
    ["法术覆盖"] = "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED", -- 法术临时覆盖事件
    ["图标发光显示"] = "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", -- 图标发光显示
    ["图标发光隐藏"] = "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", -- 图标发光隐藏
    ["屏幕提示显示"] = "SPELL_ACTIVATION_OVERLAY_SHOW", -- 屏幕提示显示
    ["屏幕提示隐藏"] = "SPELL_ACTIVATION_OVERLAY_HIDE", -- 屏幕提示隐藏
}
-- auras.lua 逻辑光环状态机
-- Aura table structure:
-- local auraSample = {
--     ["spellId_number"] = {
--         applications = "number" or nil,
--         applicationsMin = "number" or nil,
--         applicationsMax = "number" or nil,
--         dispelName = "string" or nil,
--         duration = "number",
--         expirationTime = "number" or nil,
--         icon = "number" or nil,
--         isHarmful = "boolean" or nil,
--         isHelpful = "boolean" or nil,
--         spellId = "boolean",
--         condition = {
--             onAdd = { -- 添加时条件, 可以填写多项条件，满足其中一项即可，会刷新 expirationTime
--                 ["spellId_number"] = {
--                     event = events["法术冷却"], -- 事件类型
--                     step = 2, -- 步长，用于计算层数
--                     spellId = 123456, -- 法术 ID
--                     duration = "number", -- 持续时间,会替换原有的 duration，用于特殊情况
--                 },
--                 ["spellId_number2"] = {
--                     event = "SPELL_UPDATE_COOLDOWN", -- 事件类型
--                     step = -1,                       -- 步长，用于计算层数
--                     spellId = 123456,                -- 法术 ID
--                 },
--             },
--             onUpdate = {}, -- 更新时条件, 可以填写多项条件，满足其中一项即可，不会刷新 expirationTime
--             onRemove = {}, -- 移除时条件，可以填写多项条件，满足其中一项即可，会刷新 expirationTime
--         },

--     }
-- }
-- 光环列表
local auras = {
    -- 战士
    ["盾牌格挡"] = {
        remaining = 0,
        duration = 8,
        extendDuration = true,
        maxDuration = 16,
        expirationTime = nil,
        addAuras = {
            [132404] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    ["斩杀高亮"] = {
        remaining = 0,
        duration = 15, -- 持续时间给长一点，触发后只要系统没发取消发光的事件，这15秒内终端都会读取到高亮状态
        expirationTime = nil,
        addAuras = nil,
        updateAuras = nil,
        removeAuras = {
            [5308]   = { event = events["图标发光隐藏"] }, -- 斩杀（基础/防战）
            [163201] = { event = events["图标发光隐藏"] }, -- 斩杀（武器）
            [281000] = { event = events["图标发光隐藏"] }, -- 斩杀（狂暴）
            [280735] = { event = events["图标发光隐藏"] }, -- 斩杀（屠杀天赋）
        },
    },
    ["英勇打击高亮"] = {
        remaining = 0,
        duration = 15,
        expirationTime = nil,
        addAuras = nil,
        updateAuras = nil,
        removeAuras = {
            [1269383] = { event = events["图标发光隐藏"] }, -- 英勇打击
        },
    },
    ["顺劈斩高亮"] = {
        remaining = 0,
        duration = 15,
        expirationTime = nil,
        addAuras = nil,
        updateAuras = nil,
        removeAuras = {
            [845] = { event = events["图标发光隐藏"] }, -- 顺劈斩(845)发光结束时取消
        },
    },
    ["致死高亮"] = {
        remaining = 0,
        duration = 15,
        expirationTime = nil,
        addAuras = nil,
        updateAuras = nil,
        removeAuras = {
            [12294] = { event = events["图标发光隐藏"] }, -- 致死打击发光结束时取消
        },
    },
    -- 圣骑士
    ["神圣意志"] = {
        remaining = 0,
        duration = 12,
        expirationTime = nil,
        addAuras = {
            [223819] = { event = events["法术冷却"] },
            [408458] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [223819] = { event = events["屏幕提示隐藏"] },
            [408458] = { event = events["屏幕提示隐藏"] },
        },
    },
    ["圣光灌注"] = {
        remaining = 0,
        duration = 15,
        applications = 0,
        applicationsMin = 0,
        applicationsMax = 2,
        expirationTime = nil,
        addAuras = {
            [54149] = { event = events["法术冷却"], step = 2 },
        },
        updateAuras = {
            [19750] = { event = events["施法成功"], step = -1 }, -- 圣光闪现
            [275773] = { event = events["施法成功"], step = -1 }, -- 审判
        },
        removeAuras = {
            [54149] = { event = events["屏幕提示隐藏"] },
        },
    },
    ["神性之手"] = {
        remaining = 0,
        duration = 15,
        applications = 0,
        applicationsMin = 0,
        applicationsMax = 2,
        expirationTime = nil,
        addAuras = {
            [414273] = { event = events["法术冷却"], step = 2 },
        },
        updateAuras = {
            [82326] = { event = events["施法成功"], step = -1 }, -- 圣光术
        },
        removeAuras = nil,
    },
    ["神圣壁垒"] = {
        remaining = 0,
        duration = 20,
        expirationTime = nil,
        addAuras = {
            [432496] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    ["圣洁武器"] = {
        remaining = 0,
        duration = 20,
        expirationTime = nil,
        addAuras = {
            [432502] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    ["闪耀之光"] = {
        remaining = 0,
        duration = 30,
        applications = 0,
        applicationsMin = 0,
        applicationsMax = 2,
        expirationTime = nil,
        addAuras = {
            [327510] = { event = events["法术冷却"], step = 1 },
        },
        updateAuras = {
            [85673] = { event = events["施法成功"], step = -1 }, -- 荣耀圣令
        },
        removeAuras = nil,
    },
    ["奉献"] = {
        remaining = 0,
        duration = 12,
        expirationTime = nil,
        addAuras = {
            [188370] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    ["复仇之怒"] = {
        remaining = 0,
        duration = 24,
        expirationTime = nil,
        addAuras = {
            [31884] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    ["处决宣判"] = {
        remaining = 0,
        duration = 10,
        expirationTime = nil,
        addAuras = {
            [343527] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    ["圣光之锤"] = {
        remaining = 0,
        duration = 20,
        expirationTime = nil,
        addAuras = {
            [1246643] = { event = events["法术冷却"] },
            [427441] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [427453] = { event = events["施法成功"] }, -- 施放圣光之锤后清除buff
        },
    },
    ["神圣军备"] = {
        remaining = 0,
        duration = 0,
        expirationTime = nil,
        isIcon = 0,
        addAuras = {
            [432459] = {
                event = events["图标改变"],
                overrideSpellID = 432472,
            },
        },
        updateAuras = nil,
        removeAuras = {
            [432459] = {
                event = events["图标改变"],
                overrideSpellID = 432472,
            },
        },
    },
    ["美德道标"] = {
        remaining = 0,
        duration = 9,
        expirationTime = nil,
        addAuras = {
            [200025] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    -- 猎人
    ["自然之友"] = {
        remaining = 0,
        duration = 8,
        expirationTime = nil,
        addAuras = {
            [1276720] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [34026] = { event = events["施法成功"] }
        },
    },
    ["狂野怒火"] = {
        remaining = 0,
        duration = 15,
        expirationTime = nil,
        addAuras = {
            [19574] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
        },
    },
    ["猎人印记"] = {
        remaining = 0,
        duration = 255,
        expirationTime = nil,
        addAuras = {
            [257284] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    -- 盗贼

    -- 牧师
    ["虚空之盾"] = {
        remaining = 0,
        duration = 60,
        expirationTime = nil,
        addAuras = {
            [1253591] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [1253593] = { event = events["施法成功"] }
        },
    },
    ["圣光涌动"] = {
        remaining = 0,
        duration = 20,
        applications = 0,
        applicationsMin = 0,
        applicationsMax = 2,
        expirationTime = nil,
        addAuras = {
            [114255] = { event = events["法术冷却"], step = 1 },
        },
        updateAuras = {
            [2061] = { event = events["施法成功"], step = -1 }, -- 快速治疗
            [596] = { event = events["施法成功"], step = -1 }, -- 治疗祷言
            [186263] = { event = events["施法成功"], step = -1 }, -- 暗影愈合
        },
        removeAuras = nil,
    },
    ["熵能裂隙"] = {
        remaining = 0,
        duration = 12,
        expirationTime = nil,
        addAuras = {
            [585] = {
                event = events["图标改变"],
                overrideSpellID = 450215
            },
        },
        updateAuras = nil,
        removeAuras = {
            [585] = {
                event = events["图标改变"],
                overrideSpellID = 450215
            },
        },
    },
    ["暗影愈合"] = {
        remaining = 0,
        duration = 15,
        applications = 0,
        applicationsMin = 0,
        applicationsMax = 2,
        expirationTime = nil,
        addAuras = {
            [1252217] = { event = events["法术冷却"], step = 1 },
        },
        updateAuras = {
            [186263] = { event = events["施法成功"], step = -1 },
        },
        removeAuras = nil,
    },
    ["福音"] = {
        remaining = 0,
        duration = 120,
        applications = 0,
        applicationsMin = 0,
        applicationsMax = 2,
        expirationTime = nil,
        addAuras = {
            [472433] = { event = events["法术冷却"], step = 2 },
        },
        updateAuras = {
            [194509] = { event = events["施法成功"], step = -1 }, -- 真言术：耀
        },
        removeAuras = nil,
    },
    ["织光者"] = {
        remaining = 0,
        duration = 20,
        applications = 0,
        applicationsMin = 0,
        applicationsMax = 4,
        expirationTime = nil,
        addAuras = {
            [390993] = { event = events["法术冷却"], step = 1 },
        },
        updateAuras = {
            [596] = { event = events["施法成功"], step = -1 }
        },
        removeAuras = nil,
    },
    ["祈福"] = {
        remaining = 0,
        duration = 32,
        expirationTime = nil,
        addAuras = {
            [1262766] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [2061] = {
                event = events["图标改变"],
                overrideSpellID = 1262763
            },
        },
    },
    ["祸福相依"] = {
        remaining = 0,
        duration = 20,
        applications = 0,
        applicationsMin = 0,
        applicationsMax = 10,
        expirationTime = nil,
        addAuras = {
            [390787] = { event = events["法术冷却"], step = 1 },
        },
        updateAuras = nil,
        removeAuras = {
            [17] = { event = events["施法成功"] },
            [1253593] = { event = events["施法成功"] }
        },
    },
    -- 死亡骑士
    ["脓疮毒镰"] = {
        name = "脓疮毒镰",
        spellId = 458123,
        remaining = 0,
        duration = 15,
        expirationTime = nil,
        addAuras = {
            [458123] = { event = events["法术冷却"] }
        },
        updateAuras = nil,
        removeAuras = {
            [458128] = { event = events["施法成功"] },
        },
    },
    ["脓疮毒镰2"] = {
        name = "脓疮毒镰",
        spellId = 1241077,
        remaining = 0,
        duration = 25,
        expirationTime = nil,
        addAuras = {
            [1241077] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    ["割魂索命"] = {
        name = "割魂索命",
        spellId = 1242654,
        remaining = 0,
        duration = 30,
        expirationTime = nil,
        addAuras = {
            [1242654] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [343294] = { event = events["施法成功"] },
        },
    },
    ["次级食尸鬼"] = {
        remaining = 0,
        duration = 30,
        expirationTime = nil,
        addAuras = {
            [1254252] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    ["末日突降"] = {
        remaining = 0,
        duration = 10,
        applications = 0,
        applicationsMin = 0,
        applicationsMax = 2,
        expirationTime = nil,
        addAuras = {
            [81340] = { event = events["法术冷却"], step = 1 },
        },
        updateAuras = {
            [47541] = { event = events["施法成功"], step = -1 }, -- 凋零缠绕
            [207317] = { event = events["施法成功"], step = -1 }, -- 扩散

            [1242174] = { event = events["施法成功"], step = -1 }, -- 凋零缠绕
            [383269] = { event = events["施法成功"], step = -1 }, -- 扩散
        },
        removeAuras = nil,
    },
    ["黑暗援助"] = {
        remaining = 0,
        duration = 20,
        expirationTime = nil,
        addAuras = {
            [101568] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [49998] = { event = events["施法成功"] }, -- 灵界打击
        },
    },
    ["禁断知识"] = {
        remaining = 0,
        duration = 30,
        expirationTime = nil,
        addAuras = {
            [1242223] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    ["枯萎凋零"] = {
        remaining = 0,
        duration = 10,
        expirationTime = nil,
        addAuras = {
            [43265] = { event = events["施法成功"] },
            [444505] = { event = events["法术冷却"], duration = 14 }, -- 莫格莱尼的力量
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    ["亡者指挥官"] = {
        remaining = 0,
        duration = 30,
        expirationTime = nil,
        addAuras = {
            [390260] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    ["寒冰锁链"] = {
        remaining = 0,
        duration = 8,
        expirationTime = nil,
        addAuras = {
            [444826] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [55090] = { event = events["施法成功"] },
        },
    },
    ["暗影之爪"] = {
        remaining = 0,
        duration = 12,
        applications = 0,
        applicationsMin = 0,
        applicationsMax = 4,
        expirationTime = nil,
        addAuras = {
            [1241569] = { event = events["法术冷却"], step = 1 },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    ["凋萎"] = {
        remaining = 0,
        duration = 15,
        expirationTime = nil,
        addAuras = {
            [1271199] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [55090] = { event = events["施法成功"] },
        },
    },
    ["杀戮机器"] = {
        remaining = 0,
        duration = 10,
        applications = 0,
        applicationsMin = 0,
        applicationsMax = 2,
        expirationTime = nil,
        addAuras = {
            [51124] = { event = events["法术冷却"], step = 1 },
        },
        updateAuras = nil,
        removeAuras = {
            [207230] = { event = events["施法成功"] }, -- 冰霜之镰
            [49020] = { event = events["施法成功"] }, -- 湮灭
        },
    },
    ["白霜"] = {
        remaining = 0,
        duration = 15,
        expirationTime = nil,
        addAuras = {
            [59052] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [49184] = { event = events["施法成功"] }, -- 凛风冲击
        },
    },
    ["冰霜灾祸"] = {
        remaining = 0,
        duration = 15,
        expirationTime = nil,
        addAuras = {
            [1229310] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [1228433] = { event = events["施法成功"] }, -- 冰霜灾祸
        },
    },
    ["锋锐之霜"] = {
        remaining = 0,
        duration = 30,
        applications = 0,
        applicationsMin = 0,
        applicationsMax = 5,
        expirationTime = nil,
        addAuras = {
            [50401] = { event = events["法术冷却"], step = 1 },
            [49143] = { event = events["施法成功"], step = 1 }, -- 冰霜打击
        },
        updateAuras = nil,
        removeAuras = {
            [49143] = { event = events["施法成功"], step = -1 }, -- 冰霜打击
        },
    },
    ["冰霜之柱"] = {
        remaining = 0,
        duration = 12,
        expirationTime = nil,
        addAuras = {
            [51271] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    ["霜巢之眷-冰霜巨龙之怒"] = {
        remaining = 0,
        duration = 45,
        expirationTime = nil,
        addAuras = {
            [1265639] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [1265384] = { event = events["施法成功"] },
        },
    },
    ["霜巢之眷"] = {
        remaining = 0,
        duration = 12,
        expirationTime = nil,
        addAuras = {
            [1265630] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    -- 萨满祭司
    ["飞旋之土"] = {
        name = "飞旋之土",
        spellId = 453406,
        remaining = 0,
        duration = 25,
        expirationTime = nil,
        addAuras = {
            [453406] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [1064] = { event = events["施法成功"] },
        },
    },
    ["飞旋之水"] = {
        name = "飞旋之水",
        spellId = 453407,
        remaining = 0,
        duration = 25,
        expirationTime = nil,
        addAuras = {
            [453407] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [77472] = { event = events["施法成功"] },
        },
    },
    ["治疗之雨"] = {
        name = "治疗之雨",
        spellId = 73920,
        remaining = 0,
        duration = 18,
        expirationTime = nil,
        addAuras = {
            [73920] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    ["治疗之雨-涌动"] = {
        name = "治疗之雨-涌动",
        spellId = 456366,
        remaining = 0,
        duration = 18,
        expirationTime = nil,
        addAuras = {
            [456366] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    ["潮汐奔涌"] = {
        remaining = 0,
        duration = 15,
        applications = 0,
        applicationsMin = 0,
        applicationsMax = 2,
        expirationTime = nil,
        addAuras = {
            [53390] = { event = events["法术冷却"], step = 1 },
        },
        updateAuras = nil,
        removeAuras = {
            [77472] = { event = events["施法成功"], step = -1, castBar = true },
        },
    },
    ["风暴涌流图腾"] = {
        remaining = 0,
        duration = 60,
        applications = 0,
        applicationsMin = 0,
        applicationsMax = 2,
        expirationTime = nil,
        addAuras = {
            [1267089] = { event = events["法术冷却"], step = 1 },
        },
        updateAuras = {
            [1267068] = { event = events["施法成功"], step = -1 },
        },
        removeAuras = {
            [5394] = {
                event = events["图标改变"],
                overrideSpellID = 1267068
            },
        },
    },
    ["风暴涌流图腾-持续时间"] = {
        remaining = 0,
        duration = 18,
        expirationTime = nil,
        addAuras = {
            [1267068] = { event = events["施法成功"] },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    ["治疗之泉图腾-持续时间"] = {
        remaining = 0,
        duration = 18,
        expirationTime = nil,
        addAuras = {
            [5394] = { event = events["施法成功"] },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    ["生命释放"] = {
        name = "生命释放",
        spellId = 73685,
        remaining = 0,
        duration = 10,
        applications = 0,
        applicationsMin = 0,
        applicationsMax = 2,
        expirationTime = nil,
        addAuras = {
            [73685] = { event = events["法术冷却"], step = 2 },
        },
        updateAuras = {
            [61295] = { event = events["施法成功"], step = -1 }, -- 激流
            [77472] = { event = events["施法成功"], step = -1 }, -- 治疗波
            [1064] = { event = events["施法成功"], step = -1 }, -- 治疗链
        },
        removeAuras = nil,
    },
    ["升腾"] = {
        name = "升腾",
        spellId = 114052,
        remaining = 0,
        duration = 6,
        expirationTime = nil,
        addAuras = {
            [114052] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    ["升腾 - 增强"] = {
        name = "升腾",
        spellId = 114051,
        remaining = 0,
        duration = 6,
        expirationTime = nil,
        addAuras = {
            [114052] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    ["倾盆大雨"] = {
        name = "倾盆大雨",
        spellId = 462488,
        remaining = 0,
        duration = 24,
        applications = 0,
        applicationsMin = 0,
        applicationsMax = 2,
        expirationTime = nil,
        addAuras = {
            [462488] = { event = events["法术冷却"], step = 2 },
        },
        updateAuras = {
            [462603] = { event = events["施法成功"], step = -1 }, -- 激流
        },
        removeAuras = nil,
    },
    ["毁灭闪电"] = {
        remaining = 0,
        duration = 10,
        expirationTime = nil,
        addAuras = {
            [1252415] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    -- 法师
    ["热能真空"] = {
        remaining = 0,
        duration = 12,
        expirationTime = nil,
        addAuras = {
            [1247730] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [30455] = { event = events["施法成功"] },
        },
    },
    ["冰冷智慧"] = {
        remaining = 0,
        duration = 20,
        expirationTime = nil,
        addAuras = {
            [190446] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [44614] = { event = events["施法成功"] }, -- 冰风暴
        },
    },
    ["冰冻之雨"] = {
        remaining = 0,
        duration = 12,
        expirationTime = nil,
        addAuras = {
            [270232] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    ["寒冰指"] = {
        remaining = 0,
        duration = 30,
        applications = 0,
        applicationsMin = 0,
        applicationsMax = 2,
        expirationTime = nil,
        addAuras = {
            [44544] = { event = events["法术冷却"], step = 1 },
        },
        updateAuras = {
            [30455] = { event = events["施法成功"], step = -1 }, -- 冰枪术
        },
        removeAuras = nil,
    },
    ["冰川尖刺！"] = {
        remaining = 0,
        duration = 60,
        expirationTime = nil,
        addAuras = {
            [199786] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [199786] = { event = events["施法成功"] }, -- 冰枪术
        },
    },
    -- 术士
    ["魔典：邪能破坏者"] = {
        remaining = 0,
        duration = 0,
        expirationTime = nil,
        isIcon = 1,
        addAuras = {
            [1276467] = {
                event = events["图标改变"],
                overrideSpellID = 388215,
            },
        },
        updateAuras = nil,
        removeAuras = {
            [1276467] = {
                event = events["图标改变"],
                overrideSpellID = 388215,
            },
        },
    },
    -- 武僧
    ["疗伤珠"] = {
        remaining = 0,
        duration = 30,
        expirationTime = nil,
        addAuras = {
            [224863] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [322101] = { event = events["施法成功"] },
        },
    },
    ["活力苏醒"] = {
        remaining = 0,
        duration = 20,
        expirationTime = nil,
        addAuras = {
            [392883] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [399491] = { event = events["施法成功"] }, -- 神龙之赐
            [116670] = { event = events["施法成功"] }, -- 活血术
        },
    },
    ["清空地窖"] = {
        remaining = 0,
        duration = 20,
        expirationTime = nil,
        addAuras = {
            [1262768] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [1263438] = { event = events["施法成功"] },
        },
    },
    ["生生不息1"] = {
        remaining = 0,
        duration = 15,
        expirationTime = nil,
        addAuras = {
            [197919] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [124682] = { event = events["施法成功"] }, -- 氤氲之雾
            [107428] = { event = events["施法成功"] }, -- 旭日东升踢
        },
    },
    ["生生不息2"] = {
        name = "生生不息",
        spellId = 197916,
        remaining = 0,
        duration = 15,
        expirationTime = nil,
        addAuras = {
            [197916] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [399491] = { event = events["施法成功"] }, -- 神龙之赐
            [116670] = { event = events["施法成功"] }, -- 活血术
        },
    },
    ["神龙之赐"] = {
        remaining = 0,
        duration = 60,
        applications = 0,
        applicationsMin = 0,
        applicationsMax = 10,
        expirationTime = nil,
        addAuras = {
            [399496] = { event = events["法术冷却"], step = 1 },
        },
        updateAuras = nil,
        removeAuras = {
            [399491] = { event = events["施法成功"], },
        },
    },
    ["灵泉"] = {
        remaining = 0,
        duration = 30,
        expirationTime = nil,
        addAuras = {
            [1260565] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    ["玄牛之力"] = {
        remaining = 0,
        duration = 30,
        expirationTime = nil,
        addAuras = {
            [443112] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [124682] = { event = events["施法成功"] }, -- 氤氲之雾
        },
    },
    ["青龙之心"] = {
        remaining = 0,
        duration = 4,
        expirationTime = nil,
        addAuras = {
            [443421] = { event = events["法术冷却"], duration = 4, },
            [116680] = { event = events["施法成功"], duration = 8 }, -- 氤氲之雾
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    -- 德鲁伊
    ["星河守护者"] = {
        remaining = 0,
        duration = 15,
        expirationTime = nil,
        addAuras = {
            [213708] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [8921] = { event = events["施法成功"] },
        },
    },
    ["淤血"] = {
        remaining = 0,
        duration = 10,
        expirationTime = nil,
        addAuras = {
            [93622] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [33917] = { event = events["施法成功"] },
        },
    },
    ["塞纳留斯的梦境"] = {
        remaining = 0,
        duration = 10,
        applications = 0,
        applicationsMin = 0,
        applicationsMax = 4,
        expirationTime = nil,
        addAuras = {
            [372152] = { event = events["法术冷却"], step = 1 },
        },
        updateAuras = {
            [8936] = { event = events["施法成功"], step = -1 }, -- 愈合
            [22842] = { event = events["施法成功"], step = -1 }, -- 狂暴回复
        },
        removeAuras = {
            [8936] = { event = events["图标发光隐藏"] }, -- 愈合
        },
    },
    ["铁鬃"] = {
        remaining = 0,
        duration = 7,
        applications = 0,
        applicationsMin = 0,
        independentStacks = true,
        stackExpirationTimes = {},
        expirationTime = nil,
        addAuras = {
            [192081] = { event = events["法术冷却"], step = 1 },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    ["狂暴回复"] = {
        remaining = 0,
        duration = 4,
        expirationTime = nil,
        addAuras = {
            [22842] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    ["节能施法"] = {
        remaining = 0,
        duration = 15,
        expirationTime = nil,
        addAuras = {
            [16870] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [8936] = { event = events["施法成功"] }, -- 愈合
        },
    },
    ["丛林之魂"] = {
        remaining = 0,
        duration = 15,
        expirationTime = nil,
        addAuras = {
            [114108] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = {
            [8936] = { event = events["施法成功"] }, -- 愈合
            [774] = { event = events["施法成功"] }, -- 回春术
        },
    },
    -- 恶魔猎手
    ["烈火烙印"] = {
        remaining = 0,
        duration = 12,
        expirationTime = nil,
        addAuras = {
            [207771] = { event = events["法术冷却"] },
        },
        updateAuras = nil,
        removeAuras = nil,
    },
    ["无羁邪怒"] = {
        remaining = 0,
        duration = 12,
        expirationTime = nil,
        addAuras = {
            [187827] = { event = events["图标发光显示"] },
        },
        updateAuras = nil,
        removeAuras = {
            [187827] = { event = events["图标发光隐藏"] },
        },
    },
    -- 唤魔师

}

local Auras = auras
local activeAuras = {}
do
    local function validateAuraEventMap(auraName, mapName, auraMap)
        if auraMap == nil then
            return
        end
        assert(type(auraMap) == "table", auraName .. "." .. mapName .. " must be a table or nil")
        for spellId, info in pairs(auraMap) do
            assert(type(spellId) == "number", auraName .. "." .. mapName .. " spellId must be a number")
            assert(type(info) == "table", auraName .. "." .. mapName .. "[" .. spellId .. "] must be a table")
            assert(type(info.event) == "string",
                auraName .. "." .. mapName .. "[" .. spellId .. "].event must be a string")
            if info.step ~= nil then
                assert(type(info.step) == "number",
                    auraName .. "." .. mapName .. "[" .. spellId .. "].step must be a number")
            end
            if info.duration ~= nil then
                assert(type(info.duration) == "number",
                    auraName .. "." .. mapName .. "[" .. spellId .. "].duration must be a number")
            end
        end
    end

    local function validateAura(auraName, aura)
        assert(type(aura) == "table", auraName .. " must be a table")
        assert(type(aura.remaining) == "number", auraName .. ".remaining must be a number")
        assert(type(aura.duration) == "number", auraName .. ".duration must be a number")
        if aura.applications ~= nil then
            assert(type(aura.applications) == "number", auraName .. ".applications must be a number")
            assert(type(aura.applicationsMin) == "number", auraName .. ".applicationsMin must be a number")
            if aura.applicationsMax ~= nil then
                assert(type(aura.applicationsMax) == "number", auraName .. ".applicationsMax must be a number")
                assert(aura.applicationsMin <= aura.applicationsMax,
                    auraName .. ".applicationsMin must be <= applicationsMax")
            else
                assert(aura.independentStacks,
                    auraName .. ".applicationsMax must be a number unless independentStacks is true")
            end
        end
        if aura.independentStacks then
            assert(type(aura.stackExpirationTimes) == "table", auraName .. ".stackExpirationTimes must be a table")
        end
        if aura.maxDuration ~= nil then
            assert(type(aura.maxDuration) == "number", auraName .. ".maxDuration must be a number")
        end
        validateAuraEventMap(auraName, "addAuras", aura.addAuras)
        validateAuraEventMap(auraName, "updateAuras", aura.updateAuras)
        validateAuraEventMap(auraName, "removeAuras", aura.removeAuras)
    end

    local function indexAura(target, auraName, auraData)
        for spellId, info in pairs(auraData) do
            local ev = info.event
            local byEvent = target[ev]
            if not byEvent then
                byEvent = {}
                target[ev] = byEvent
            end
            local bySpell = byEvent[spellId]
            if not bySpell then
                bySpell = {}
                byEvent[spellId] = bySpell
            end
            bySpell[auraName] = info
        end
    end

    for name, data in pairs(Auras) do
        validateAura(name, data)
        if data.addAuras then
            indexAura(addAuras, name, data.addAuras)
        end
        if data.updateAuras then
            indexAura(updateAuras, name, data.updateAuras)
        end
        if data.removeAuras then
            indexAura(removeAuras, name, data.removeAuras)
        end
    end
end

local function getAuraDuration(aura, info)
    return (info and info.duration) or aura.duration
end

local function activateAura(auraName, aura)
    if auraName and aura then
        activeAuras[auraName] = aura
    end
end

local function deactivateAura(auraName, aura, resetApplications)
    if aura then
        aura.expirationTime = nil
        aura.remaining = 0
        if resetApplications and aura.applications then
            aura.applications = aura.applicationsMin or 0
        end
    end
    if auraName then
        activeAuras[auraName] = nil
    end
end

local function applyAuraDuration(aura, info, now)
    local duration = getAuraDuration(aura, info)
    if not duration then
        return false
    end

    if aura.extendDuration and aura.expirationTime and aura.expirationTime > now then
        aura.expirationTime = aura.expirationTime + duration
    else
        aura.expirationTime = now + duration
    end
    if aura.maxDuration and aura.expirationTime > now + aura.maxDuration then
        aura.expirationTime = now + aura.maxDuration
    end
    return aura.expirationTime ~= nil
end

local function updateIndependentStacks(aura, now)
    local stacks = aura.stackExpirationTimes
    if not stacks then
        stacks = {}
        aura.stackExpirationTimes = stacks
    end

    local oldCount = #stacks
    local count = 0
    local latestExpirationTime = nil
    for i = 1, oldCount do
        local expirationTime = stacks[i]
        if expirationTime and expirationTime > now then
            count = count + 1
            stacks[count] = expirationTime
            if not latestExpirationTime or expirationTime > latestExpirationTime then
                latestExpirationTime = expirationTime
            end
        end
    end
    for i = count + 1, oldCount do
        stacks[i] = nil
    end

    aura.applications = count
    if latestExpirationTime then
        aura.expirationTime = latestExpirationTime
        aura.remaining = latestExpirationTime - now
    else
        aura.expirationTime = nil
        aura.remaining = 0
        aura.applications = aura.applicationsMin or 0
    end
end

local function addIndependentStack(aura, info, now)
    local duration = getAuraDuration(aura, info)
    if not duration then
        return
    end

    updateIndependentStacks(aura, now)

    local stacks = aura.stackExpirationTimes
    local expirationTime = now + duration
    local maxApplications = aura.applicationsMax or math_huge
    if #stacks < maxApplications then
        stacks[#stacks + 1] = expirationTime
    else
        local earliestIndex = 1
        for i = 2, #stacks do
            if stacks[i] < stacks[earliestIndex] then
                earliestIndex = i
            end
        end
        stacks[earliestIndex] = expirationTime
    end

    updateIndependentStacks(aura, now)
end

local function removeIndependentStack(aura, count, now)
    updateIndependentStacks(aura, now)

    local stacks = aura.stackExpirationTimes
    for _ = 1, count do
        local earliestIndex = nil
        for i = 1, #stacks do
            if not earliestIndex or stacks[i] < stacks[earliestIndex] then
                earliestIndex = i
            end
        end
        if not earliestIndex then
            break
        end
        table_remove(stacks, earliestIndex)
    end

    updateIndependentStacks(aura, now)
end

local function applyIndependentStackStep(aura, info, now, defaultStep)
    if not aura.independentStacks then
        return false
    end

    local step = info.step or defaultStep
    if not step then
        return true
    end

    if step > 0 then
        for _ = 1, step do
            addIndependentStack(aura, info, now)
        end
    elseif step < 0 then
        removeIndependentStack(aura, math_abs(step), now)
    end

    return true
end

---@param auraMap table<string, table>|nil 光环名 -> info
---@param castGUID any|nil 施法成功时传入施法 GUID；冷却类调用传 nil，不按施法过滤
local function applyAuraMapForSpellEvent(auraMap, castGUID)
    if not auraMap then
        return
    end
    local now = GetTime()
    for auraName, info in pairs(auraMap) do
        local aura = Auras[auraName]
        if aura and ((not info.castBar) or castGUID) then
            local didApplyDuration = false
            if applyIndependentStackStep(aura, info, now, 1) then
                -- 独立层数的时间由 stackExpirationTimes 维护。
                if aura.expirationTime then
                    activateAura(auraName, aura)
                else
                    deactivateAura(auraName, aura)
                end
            else
                if applyAuraDuration(aura, info, now) then
                    activateAura(auraName, aura)
                end
                didApplyDuration = true
            end
            if not aura.independentStacks and aura.applications and info.step then
                if info.step > 0 then
                    if not didApplyDuration then
                        if applyAuraDuration(aura, info, now) then
                            activateAura(auraName, aura)
                        end
                    end
                    aura.applications = math_min(aura.applicationsMax, aura.applications + info.step)
                else
                    aura.applications = math_max(aura.applicationsMin, aura.applications + info.step)
                    if aura.applications <= aura.applicationsMin then
                        deactivateAura(auraName, aura)
                    end
                end
            end
        end
    end
end

---@param auraMap table<string, table>|nil 光环名 -> info
---@param castGUID any|nil 施法成功时传入施法 GUID；冷却类调用传 nil，不按施法过滤
local function updateAuraMapForSpellEvent(auraMap, castGUID)
    if not auraMap then
        return
    end
    local now = GetTime()
    for auraName, info in pairs(auraMap) do
        local aura = Auras[auraName]
        if aura and ((not info.castBar) or castGUID) then
            if applyIndependentStackStep(aura, info, now, nil) then
                -- 独立层数的时间由 stackExpirationTimes 维护。
                if aura.expirationTime then
                    activateAura(auraName, aura)
                else
                    deactivateAura(auraName, aura)
                end
            elseif aura.applications and info.step then
                if info.step > 0 then
                    if applyAuraDuration(aura, info, now) then
                        activateAura(auraName, aura)
                    end
                    aura.applications = math_min(aura.applicationsMax, aura.applications + info.step)
                else
                    aura.applications = math_max(aura.applicationsMin, aura.applications + info.step)
                    if aura.applications <= aura.applicationsMin then
                        deactivateAura(auraName, aura)
                    end
                end
            elseif aura.duration then
                if applyAuraDuration(aura, info, now) then
                    activateAura(auraName, aura)
                end
            end
        end
    end
end

---@param removeMap table<string, table>|nil 光环名 -> info
---@param resetapplications boolean|nil 为 true 时重置层数（冷却/施法成功移除）；屏幕提示类仅清时间传 false
local function clearAurasFromRemoveMap(removeMap, resetapplications)
    if not removeMap then
        return
    end
    for auraName in pairs(removeMap) do
        local aura = Auras[auraName]
        if aura then
            if aura.independentStacks and aura.stackExpirationTimes then
                for i = #aura.stackExpirationTimes, 1, -1 do
                    aura.stackExpirationTimes[i] = nil
                end
            end
            deactivateAura(auraName, aura, resetapplications)
        end
    end
end

---@param spellID number 法术 ID（冷却事件键）
-- 通过 SPELL_UPDATE_COOLDOWN 同步光环结束时间与层数
local function updateAuraBySpellCooldown(spellID)
    local ev = events["法术冷却"]
    local addBySpell = addAuras[ev]
    local updateBySpell = updateAuras[ev]
    local removeBySpell = removeAuras[ev]
    applyAuraMapForSpellEvent(addBySpell and addBySpell[spellID], nil)
    updateAuraMapForSpellEvent(updateBySpell and updateBySpell[spellID], nil)
    clearAurasFromRemoveMap(removeBySpell and removeBySpell[spellID], true)
end

---@param spellID number 法术ID
---@param castGUID string 施法 GUID
-- 通过事件"UNIT_SPELLCAST_SUCCEEDED"更新光环, 并更新光环的层数
local function updateAuraBySuccess(spellID, castGUID)
    local ev = events["施法成功"]
    local addBySpell = addAuras[ev]
    local updateBySpell = updateAuras[ev]
    local removeBySpell = removeAuras[ev]
    applyAuraMapForSpellEvent(addBySpell and addBySpell[spellID], castGUID)
    updateAuraMapForSpellEvent(updateBySpell and updateBySpell[spellID], castGUID)
    clearAurasFromRemoveMap(removeBySpell and removeBySpell[spellID], true)
end

local function updateAuraByIconMap(map, spellID)
    if not map then
        return
    end
    local overrideSpellID = GetOverrideSpell(spellID)
    for auraName, info in pairs(map) do
        local aura = Auras[auraName]
        if aura then
            local hasOverride = overrideSpellID and info.overrideSpellID and overrideSpellID == info.overrideSpellID
            if aura.isIcon then
                if hasOverride then
                    aura.isIcon = 2
                else
                    aura.isIcon = 1
                end
            end
            if hasOverride and aura.duration then
                aura.expirationTime = GetTime() + aura.duration
                activateAura(auraName, aura)
            else
                deactivateAura(auraName, aura)
            end
        end
    end
end

---@param spellID number 法术ID
-- 通过事件"SPELL_UPDATE_ICON"更新光环, 并更新光环的层数
local function updateAuraByIcon(spellID)
    local ev = events["图标改变"]
    local addBySpell = addAuras[ev]
    local updateBySpell = updateAuras[ev]
    local removeBySpell = removeAuras[ev]
    if addBySpell and addBySpell[spellID] then
        updateAuraByIconMap(addBySpell[spellID], spellID)
    end
    if updateBySpell and updateBySpell[spellID] then
        updateAuraByIconMap(updateBySpell[spellID], spellID)
    end
    if removeBySpell and removeBySpell[spellID] then
        updateAuraByIconMap(removeBySpell[spellID], spellID)
    end
end

-- 首次登录遍历所有Icon光环
local function updateAuraIconByEnteringWorld()
    local ev = events["图标改变"]
    local addBySpell = addAuras[ev]
    local updateBySpell = updateAuras[ev]
    local removeBySpell = removeAuras[ev]
    if addBySpell then
        for spellId, info in pairs(addBySpell) do
            updateAuraByIconMap(addBySpell[spellId], spellId)
        end
    end
    if updateBySpell then
        for spellId, info in pairs(updateBySpell) do
            updateAuraByIconMap(updateBySpell[spellId], spellId)
        end
    end
    if removeBySpell then
        for spellId, info in pairs(removeBySpell) do
            updateAuraByIconMap(removeBySpell[spellId], spellId)
        end
    end
end

local function updateAuraByOverrideMap(map, overrideSpellID)
    if not map then
        return
    end

    for auraName, info in pairs(map) do
        local aura = Auras[auraName]
        if aura then
            if overrideSpellID and aura.duration and overrideSpellID == info.overrideSpellID then
                if aura.duration then
                    aura.expirationTime = GetTime() + aura.duration
                    activateAura(auraName, aura)
                end
            else
                deactivateAura(auraName, aura)
            end
        end
    end
end

---@param baseSpellID number 基本法术ID
---@param overrideSpellID number 覆盖法术ID
-- 通过事件"COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED"更新光环, 并更新光环的结束时间
local function updateAuraBySpellOverride(baseSpellID, overrideSpellID)
    local ev = events["法术覆盖"]
    local addBySpell = addAuras[ev]
    local updateBySpell = updateAuras[ev]
    local removeBySpell = removeAuras[ev]
    if addBySpell and addBySpell[baseSpellID] then
        updateAuraByOverrideMap(addBySpell[baseSpellID], overrideSpellID)
    end
    if updateBySpell and updateBySpell[baseSpellID] then
        updateAuraByOverrideMap(updateBySpell[baseSpellID], overrideSpellID)
    end
    if removeBySpell and removeBySpell[baseSpellID] then
        updateAuraByOverrideMap(removeBySpell[baseSpellID], overrideSpellID)
    end
end

---@param spellId number 光环ID, 屏幕提示
-- 通过事件"SPELL_ACTIVATION_OVERLAY_HIDE"更新光环, 并更新光环的结束时间
local function updateAuraByActivationOverlayShow(spellId)
    local addBySpell = addAuras[events["屏幕提示显示"]]
    local updateBySpell = updateAuras[events["屏幕提示显示"]]
    applyAuraMapForSpellEvent(addBySpell and addBySpell[spellId], nil)
    updateAuraMapForSpellEvent(updateBySpell and updateBySpell[spellId], nil)
end

---@param spellId number 光环ID, 屏幕提示
-- 通过事件"SPELL_ACTIVATION_OVERLAY_HIDE"更新光环, 并更新光环的结束时间
local function updateAuraByActivationOverlayHide(spellId)
    local removeBySpell = removeAuras[events["屏幕提示隐藏"]]
    clearAurasFromRemoveMap(removeBySpell and removeBySpell[spellId], false)
end

local function updateAuraByOverlayGlowShow(spellID)
    local addBySpell = addAuras[events["图标发光显示"]]
    local updateBySpell = updateAuras[events["图标发光显示"]]
    applyAuraMapForSpellEvent(addBySpell and addBySpell[spellID], nil)
    updateAuraMapForSpellEvent(updateBySpell and updateBySpell[spellID], nil)
end

local function updateAuraByOverlayGlowHide(spellID)
    local removeBySpell = removeAuras[events["图标发光隐藏"]]
    clearAurasFromRemoveMap(removeBySpell and removeBySpell[spellID], false)
end

-- SPELL_ACTIVATION_OVERLAY_GLOW_SHOW / HIDE：与 main.lua 一致，按是否仍发光刷新或清除时间
local function updateAuraByOverlayGlow(spellID)
    local ev = events["图标发光隐藏"]
    local removeBySpell = removeAuras[ev]
    local map = removeBySpell and removeBySpell[spellID]
    if not map then
        return
    end
    local now = GetTime()
    local isSpellOverlayed = IsSpellOverlayed(spellID)
    for auraName in pairs(map) do
        local aura = Auras[auraName]
        if aura then
            if isSpellOverlayed and aura.duration then
                aura.expirationTime = now + aura.duration
                activateAura(auraName, aura)
            else
                deactivateAura(auraName, aura)
            end
        end
    end
end

-- 通过每帧更新光环
local function updateAura()
    local currentTime = GetTime()
    for name, info in pairs(activeAuras) do
        if info.independentStacks then
            updateIndependentStacks(info, currentTime)
            if not info.expirationTime then
                activeAuras[name] = nil
            end
        else
            local expTime = info.expirationTime
            if expTime then
                if info.applications and info.applications <= 0 then
                    expTime = nil
                end
                if expTime then
                    local remaining = expTime - currentTime
                    if remaining > 0 then
                        info.remaining = remaining
                    else
                        deactivateAura(name, info, true)
                    end
                else
                    deactivateAura(name, info, true)
                end
            else
                deactivateAura(name, info, true)
            end
        end
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
for _, eventName in pairs(events) do
    eventFrame:RegisterEvent(eventName)
end

local eventHandlers = {
    PLAYER_ENTERING_WORLD = function()
        updateAuraIconByEnteringWorld()
    end,
    [events["法术冷却"]] = function(spellID)
        if spellID then
            updateAuraBySpellCooldown(spellID)
        end
    end,
    [events["施法成功"]] = function(unit, castGUID, spellID)
        if unit == "player" and spellID then
            updateAuraBySuccess(spellID, castGUID)
        end
    end,
    [events["图标改变"]] = function(spellID)
        if spellID then
            updateAuraByIcon(spellID)
        end
    end,
    [events["法术覆盖"]] = function(baseSpellID, overrideSpellID)
        if baseSpellID then
            updateAuraBySpellOverride(baseSpellID, overrideSpellID)
        end
    end,
    [events["图标发光显示"]] = function(spellID)
        if spellID then
            updateAuraByOverlayGlowShow(spellID)
            updateAuraByOverlayGlow(spellID)
        end
    end,
    [events["图标发光隐藏"]] = function(spellID)
        if spellID then
            updateAuraByOverlayGlowHide(spellID)
            updateAuraByOverlayGlow(spellID)
        end
    end,
    [events["屏幕提示显示"]] = function(spellID)
        if spellID then
            updateAuraByActivationOverlayShow(spellID)
        end
    end,
    [events["屏幕提示隐藏"]] = function(spellID)
        if spellID then
            updateAuraByActivationOverlayHide(spellID)
        end
    end,
}

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local handler = eventHandlers[event]
    if handler then
        handler(...)
    end
end)

eventFrame:SetScript("OnUpdate", updateAura)

function GetRetailAura(auraName)
    return Auras[auraName]
end

lib.Auras = Auras
lib.AuraEvents = events

function lib:GetAura(auraName)
    return GetRetailAura(auraName)
end

if ns then
    ns.Auras = Auras
    ns.AuraEvents = events
    ns.GetAura = GetRetailAura
end
