// lib/lab/demos/coup_lua/coup_script.dart
//
// 政变（Coup）Lua 状态机脚本 — 完整规则（kaya3/coup + coup-rl-agent 综合）
//
// ## 角色卡（5 种 × 3 张 = 15 张总池）
//
//   - duke       公爵：TAX(+3) / 阻断 FOREIGN_AID
//   - assassin   刺客：ASSASSINATE(-3,目标失 1 卡) / 被 Contessa 阻断
//   - captain    队长：STEAL(偷 1~2) / 阻断 STEAL
//   - ambassador 大使：EXCHANGE(换 2 张) / 阻断 STEAL
//   - contessa   伯爵夫人：阻断 ASSASSINATE
//
// ## 主动作 7 种（c.cur_action.type）
//
//   INCOME / FOREIGN_AID / TAX / EXCHANGE / STEAL / ASSASSINATE / COUP
//
// ## 响应 3 种（c.cur_phase 决定何时显示）
//
//   PASS / CHALLENGE / BLOCK（BLOCK 仅限可阻断动作）
//
// ## 状态机
//
//   CreateRoom → state="lobby"
//   ACK × N   → state="ready"
//   START     → state="playing"（房主点开始，服务端洗牌 + 发 2 张 + 给每人 2 金币）
//   游戏中循环：
//     cur_phase = "action"
//       ↓ 当前玩家发主动作
//     cur_phase = "challenge"
//       ↓ 其他玩家依次选择 PASS / CHALLENGE
//       ↓ 若有人 challenge：被质疑方必须 REVEAL（有 → 翻牌放回牌库抽新，质疑者失 1 卡；无 → 失 1 卡，动作无效）
//       ↓ 若无人 challenge：
//     cur_phase = "block"（仅可阻断动作）
//       ↓ 被影响方选择 PASS / BLOCK（声明持有某卡）
//       ↓ 若 BLOCK：进入 "blockChallenge" 阶段，原动作发起人可 PASS / CHALLENGE
//       ↓ 无人阻断：
//     执行动作效果（INCOME/TAX/STEAL/ASSASSINATE/COUP/EXCHANGE/FOREIGN_AID）
//     ↓
//     cur_phase = "lose_card"（若有玩家需要失去卡）
//       ↓ 该玩家发 LOSE_CARD 选择
//     ↓
//     cur_phase = "exchange"（EXCHANGE 后）
//       ↓ 当前玩家发 EXCHANGE_KEEP 选择保留的 2 张
//     ↓
//     cur_player_idx 轮转 → 回到 "action"
//   任意玩家失 2 张卡 → state="ended"
//
// ## context 字段
//
//   host_id          : string 房主
//   players          : {device_id → {alias, alive, coins, card1, card2,
//                                     card1_alive, card2_alive, hand_count}}
//   player_order     : [device_id, ...]   回合顺序（淘汰者从中移除）
//   cur_player_idx   : int               当前回合玩家在 player_order 中的索引
//   cur_phase        : string            当前阶段
//   cur_action       : {type, source, target, claimer_card}
//                                       当前进行中的动作
//   cur_target       : device_id?        被影响者
//   challenger       : device_id?        质疑发起人
//   blocker          : device_id?        阻断发起人
//   loser            : device_id?        需要失卡者
//   ex_player        : device_id?        EXCHANGE 中需要保留 2 张者
//   exchange_cards   : [role, ...]       EXCHANGE 候选 4 张
//   deck             : [role, ...]       牌库（动态调整）
//   winner           : device_id?
//   action_permissions : {action_key → role_rule}

const String kCoupScript = r'''
-- 角色权限检查（沿用 reversi_lua 范式）
function role_check(c, p, action)
  local rule = c.action_permissions[action]
  if rule == nil or rule == "any" then return true end
  if not c.players[p.device_id] then return false end
  if rule == "host" then return p.device_id == c.host_id end
  if rule == "current_player" then
    local order = c.player_order or {}
    local cur = order[(c.cur_player_idx or 0) + 1]
    return cur ~= nil and p.device_id == cur
  end
  if rule == "alive" then
    local pl = c.players[p.device_id]
    return pl ~= nil and pl.alive
  end
  if rule == "loser" then
    return c.loser ~= nil and p.device_id == c.loser
  end
  if rule == "ex_player" then
    return c.ex_player ~= nil and p.device_id == c.ex_player
  end
  return false
end

-- 玩家是否还活着
function is_alive(c, did)
  local pl = c.players[did]
  return pl ~= nil and pl.alive
end

-- 活的玩家数（用来判定胜利）
function alive_count(c)
  local n = 0
  for _, pl in pairs(c.players) do
    if pl.alive then n = n + 1 end
  end
  return n
end

-- 初始化牌库（5 种角色 × 3 张 = 15 张），并打乱（gopher-lua math.random 可用）
function build_deck()
  local d = {}
  for i = 1, 3 do
    table.insert(d, "duke")
    table.insert(d, "assassin")
    table.insert(d, "captain")
    table.insert(d, "ambassador")
    table.insert(d, "contessa")
  end
  -- Fisher-Yates
  for i = #d, 2, -1 do
    local j = math.random(i)
    d[i], d[j] = d[j], d[i]
  end
  return d
end

-- 从牌库顶抽 1 张
function draw_card(c)
  if #(c.deck or {}) == 0 then c.deck = build_deck() end
  return table.remove(c.deck)
end

-- 把某张卡放回牌库底
function return_card(c, role)
  if role == nil then return end
  c.deck = c.deck or {}
  table.insert(c.deck, role)
end

-- 给玩家发 1 张卡（返回抽到的 role）
function give_card(c, did)
  local role = draw_card(c)
  local pl = c.players[did]
  if pl.card1 == nil then
    pl.card1 = role
    pl.card1_alive = true
  elseif pl.card2 == nil then
    pl.card2 = role
    pl.card2_alive = true
  end
  pl.hand_count = (pl.hand_count or 0) + 1
  return role
end

-- 给玩家发 2 张起始手牌
function deal_starting(c, did)
  local pl = c.players[did]
  pl.card1 = nil; pl.card1_alive = false
  pl.card2 = nil; pl.card2_alive = false
  pl.hand_count = 0
  pl.coins = pl.coins or 2
  give_card(c, did)
  give_card(c, did)
end

-- 玩家失去指定槽位的卡（置为死卡、放回牌库）
function player_lose_slot(c, did, slot)
  local pl = c.players[did]
  if pl == nil then return end
  if slot == 1 and pl.card1_alive then
    return_card(c, pl.card1)
    pl.card1_alive = false
    pl.hand_count = (pl.hand_count or 0) - 1
  elseif slot == 2 and pl.card2_alive then
    return_card(c, pl.card2)
    pl.card2_alive = false
    pl.hand_count = (pl.hand_count or 0) - 1
  end
  if (pl.hand_count or 0) <= 0 then
    pl.alive = false
    -- 从 player_order 中移除
    local new_order = {}
    for _, x in ipairs(c.player_order or {}) do
      if x ~= did then table.insert(new_order, x) end
    end
    c.player_order = new_order
    if c.cur_player_idx ~= nil and c.cur_player_idx >= #new_order then
      c.cur_player_idx = 0
    end
  end
end

-- 玩家是否拥有声称的角色卡（任一未死的卡匹配）
function player_has_card(c, did, role)
  local pl = c.players[did]
  if pl == nil then return false, nil end
  if pl.card1_alive and pl.card1 == role then return true, 1 end
  if pl.card2_alive and pl.card2 == role then return true, 2 end
  return false, nil
end

-- 玩家声称自己拥有某角色（用于 REVEAL 翻牌后回收 + 抽新）
function reveal_card(c, did, role)
  local pl = c.players[did]
  local has, slot = player_has_card(c, did, role)
  if not has then return false end
  return_card(c, role)
  if slot == 1 then
    pl.card1 = draw_card(c)
    pl.card1_alive = true
  else
    pl.card2 = draw_card(c)
    pl.card2_alive = true
  end
  return true
end

-- ============== on_* ==============

on_init = function(c, p)
  c.host_id = p.device_id
  c.players = {}
  c.players[p.device_id] = {
    alias = p.alias, alive = true, coins = 2,
    card1 = nil, card1_alive = false,
    card2 = nil, card2_alive = false,
    hand_count = 0,
  }
  c.player_order = { p.device_id }
  c.cur_player_idx = 0
  c.cur_phase = "action"
  c.cur_action = nil
  c.cur_target = nil
  c.challenger = nil
  c.blocker = nil
  c.loser = nil
  c.lose_reason = nil
  c.ex_player = nil
  c.exchange_cards = nil
  c.exchange_keep = nil
  c.deck = build_deck()
  c.winner = nil
  c.action_permissions = {
    ACK          = "any",
    START        = "host",
    RESET        = "host",
    ACT          = "current_player",
    CHALLENGE    = "alive",
    BLOCK        = "alive",
    REVEAL       = "alive",
    PASS_RESP    = "alive",
    LOSE_CARD    = "alive", -- 任何活的玩家都能发；服务端 on_action_LOSE_CARD 内部校验身份（loser 预设或被质疑方主动认输）
    EXCHANGE_KEEP = "ex_player",
  }
  state = "lobby"
  return c
end

on_join = function(c, p)
  if c.players[p.device_id] ~= nil then return c end
  local n = 0
  for _, _ in pairs(c.players) do n = n + 1 end
  if n >= 6 then
    c.rejected_join = c.rejected_join or {}
    c.rejected_join[p.device_id] = true
    return c
  end
  c.players[p.device_id] = {
    alias = p.alias, alive = true, coins = 2,
    card1 = nil, card1_alive = false,
    card2 = nil, card2_alive = false,
    hand_count = 0,
  }
  if state == "lobby" then
    table.insert(c.player_order, p.device_id)
  else
    -- 游戏中后加入者：保留为观众（不加入 player_order，仅能在 lobby 后等待下一局）
    c.players[p.device_id].spectator = true
  end
  return c
end

on_leave = function(c, p)
  c.players[p.device_id] = nil
  local new_order = {}
  for _, x in ipairs(c.player_order or {}) do
    if x ~= p.device_id then table.insert(new_order, x) end
  end
  c.player_order = new_order
  if c.cur_player_idx ~= nil and c.cur_player_idx >= #new_order then
    c.cur_player_idx = 0
  end
  return c
end

on_action_ACK = function(c, p)
  if not role_check(c, p, "ACK") then return c end
  if state ~= "lobby" then return c end
  -- 简化：lobby 即视为已 ready（不维护单独 ready 集合）
  state = "ready"
  return c
end

on_action_START = function(c, p)
  if not role_check(c, p, "START") then return c end
  if state ~= "ready" then return c end
  local n = 0
  for _, _ in pairs(c.players) do n = n + 1 end
  if n < 2 then return c end
  -- 洗牌 + 给每人发 2 张
  c.deck = build_deck()
  for did, _ in pairs(c.players) do
    deal_starting(c, did)
  end
  -- ★ player_order 在 on_join 时已按加入顺序追加，START 直接复用
  -- （不要用 pairs 重新生成，否则顺序不确定导致两端 player_order 不一致）
  c.cur_player_idx = 0
  c.cur_phase = "action"
  c.cur_action = nil
  c.challenger = nil
  c.blocker = nil
  state = "playing"
  return c
end

on_action_RESET = function(c, p)
  if not role_check(c, p, "RESET") then return c end
  c.cur_action = nil
  c.cur_target = nil
  c.challenger = nil
  c.blocker = nil
  c.loser = nil
  c.lose_reason = nil
  c.ex_player = nil
  c.exchange_cards = nil
  c.exchange_keep = nil
  c.winner = nil
  for did, pl in pairs(c.players) do
    pl.card1 = nil; pl.card1_alive = false
    pl.card2 = nil; pl.card2_alive = false
    pl.hand_count = 0
    pl.coins = 2
    pl.alive = true
  end
  c.deck = build_deck()
  c.player_order = {}
  for did, _ in pairs(c.players) do
    table.insert(c.player_order, did)
  end
  c.cur_player_idx = 0
  c.cur_phase = "action"
  state = "lobby"
  return c
end

-- 主动作入口（p.action_type = INCOME/FOREIGN_AID/TAX/EXCHANGE/STEAL/ASSASSINATE/COUP）
on_action_ACT = function(c, p)
  if not role_check(c, p, "ACT") then return c end
  if state ~= "playing" then return c end
  if c.cur_phase ~= "action" then return c end

  -- 动作类型白名单
  local valid_actions = {
    INCOME = true, FOREIGN_AID = true, TAX = true,
    EXCHANGE = true, STEAL = true, ASSASSINATE = true, COUP = true
  }
  if not valid_actions[p.action_type] then return c end

  local at = p.action_type
  local pl = c.players[p.device_id]
  if pl == nil or not pl.alive then return c end

  -- COUP ≥10 金币时强制必须 COUP（标准规则）
  if pl.coins >= 10 and at ~= "COUP" then return c end

  -- 费用余额检查（只检查是否够，先不扣）
  if at == "ASSASSINATE" and pl.coins < 3 then return c end
  if at == "COUP" and pl.coins < 7 then return c end

  -- 目标校验
  if at == "STEAL" or at == "ASSASSINATE" or at == "COUP" then
    if p.target == nil or p.target == p.device_id then return c end
    local t = c.players[p.target]
    if t == nil or not t.alive then return c end
  end
  if at == "STEAL" then
    local t = c.players[p.target]
    if (t.coins or 0) < 1 then return c end
  end

  -- ★ 全部校验通过后再扣费（声明即付，被挡不退）
  if at == "ASSASSINATE" then
    pl.coins = pl.coins - 3
  elseif at == "COUP" then
    pl.coins = pl.coins - 7
  end

  -- 写 cur_action（target / claimer_card 由动作决定）
  local claimer_card = nil
  if at == "TAX" then claimer_card = "duke"
  elseif at == "EXCHANGE" then claimer_card = "ambassador"
  elseif at == "STEAL" then claimer_card = "captain"
  elseif at == "ASSASSINATE" then claimer_card = "assassin"
  end

  c.cur_action = {
    type = at, source = p.device_id,
    target = p.target, claimer_card = claimer_card,
  }
  c.cur_target = p.target
  c.challenger = nil
  c.blocker = nil

  -- 根据动作类型设置正确的阶段：
  -- INCOME/COUP：直接执行（不可质疑、不可阻断）
  -- FOREIGN_AID：进入 block（可被 Duke 阻断，但不可质疑）
  -- TAX/EXCHANGE/STEAL/ASSASSINATE：进入 challenge（可被质疑）
  if at == "INCOME" or at == "COUP" then
    execute_action(c)
  elseif at == "FOREIGN_AID" then
    c.cur_phase = "block"
  else
    c.cur_phase = "challenge"
  end
  return c
end

-- 质疑：可质疑"主动作"或"阻断"。
-- p.target 含义：被质疑方 device_id（主动作时=cur_action.source；阻断时=cur_action.blocker）
-- p.claim_role：要质疑的那张角色卡名
on_action_CHALLENGE = function(c, p)
  if not role_check(c, p, "CHALLENGE") then return c end
  if state ~= "playing" then return c end
  local pl = c.players[p.device_id]
  if pl == nil or not pl.alive then return c end
  if c.challenger ~= nil then return c end

  if c.cur_phase == "challenge" then
    -- 质疑主动作
    if p.device_id == c.cur_action.source then return c end
    c.challenger = p.device_id
    c.cur_phase = "reveal"
    return c
  elseif c.cur_phase == "blockChallenge" then
    -- 反质疑阻断（只有发起人可发起）
    if c.blocker == nil then return c end
    if p.device_id ~= c.cur_action.source then return c end
    c.challenger = p.device_id
    c.cur_phase = "reveal"
    return c
  end
  return c
end

-- 阻断：仅在 block 阶段可触发
--   FOREIGN_AID：任意非发起人可声明 Duke 阻断
--   STEAL：仅被影响方（c.cur_target）可声明 Captain/Ambassador
--   ASSASSINATE：仅被影响方可声明 Contessa
on_action_BLOCK = function(c, p)
  if not role_check(c, p, "BLOCK") then return c end
  if state ~= "playing" then return c end
  if c.cur_phase ~= "block" then return c end
  if c.blocker ~= nil then return c end

  local at = c.cur_action.type
  local role = p.blocker_card
  if at == "FOREIGN_AID" then
    if p.device_id == c.cur_action.source then return c end
    if role ~= "duke" then return c end
  elseif at == "STEAL" then
    if c.cur_target ~= p.device_id then return c end
    if role ~= "captain" and role ~= "ambassador" then return c end
  elseif at == "ASSASSINATE" then
    if c.cur_target ~= p.device_id then return c end
    if role ~= "contessa" then return c end
  else
    return c
  end

  c.blocker = p.device_id
  c.cur_action.claimer_card = role
  c.cur_phase = "blockChallenge"
  return c
end

-- 翻牌：由 blocker 是否存在区分"主动作质疑 / 阻断质疑"
on_action_REVEAL = function(c, p)
  if not role_check(c, p, "REVEAL") then return c end
  if state ~= "playing" then return c end
  if c.cur_phase ~= "reveal" then return c end
  if c.challenger == nil then return c end

  local isBlockChallenge = (c.blocker ~= nil)
  local revealer = isBlockChallenge and c.blocker or c.cur_action.source
  if p.device_id ~= revealer then return c end

  local role = c.cur_action.claimer_card
  if role == nil then return c end
  if p.role ~= role then return c end

  if player_has_card(c, revealer, role) then
    reveal_card(c, revealer, role)
    c.loser = c.challenger
    c.challenger = nil
    c.lose_reason = isBlockChallenge and "blockChallengerWrong" or "mainChallengerWrong"
  else
    c.loser = revealer
    c.challenger = nil
    c.lose_reason = isBlockChallenge and "blockFailed" or "mainSourceWrong"
  end
  c.cur_phase = "loseCard"
  return c
end

-- 跳过（质疑期 / 阻断期 / 反质疑期）
on_action_PASS_RESP = function(c, p)
  if not role_check(c, p, "PASS_RESP") then return c end
  if state ~= "playing" then return c end

  if c.cur_phase == "challenge" then
    if p.device_id == c.cur_action.source then return c end
    local at = c.cur_action.type
    if at == "FOREIGN_AID" or at == "STEAL" or at == "ASSASSINATE" then
      c.cur_phase = "block"
    else
      execute_action(c)
    end
  elseif c.cur_phase == "block" then
    execute_action(c)
  elseif c.cur_phase == "blockChallenge" then
    -- 发起人放弃反质疑 → 阻断成立，动作被抵消
    c.blocker = nil; c.cur_action = nil; c.cur_target = nil
    c.cur_phase = "action"
    advance_turn(c)
  end
  -- reveal 阶段不允许 PASS，被质疑方要么 REVEAL 要么发 LOSE_CARD 认输
  return c
end

-- 失卡：用 lose_reason 决定后续走向
on_action_LOSE_CARD = function(c, p)
  if not role_check(c, p, "LOSE_CARD") then return c end
  if state ~= "playing" then return c end

  local loser  = c.loser
  local reason = c.lose_reason

  -- reveal 阶段主动认输（被质疑方放弃翻牌，发 LOSE_CARD）
  if loser == nil and c.cur_phase == "reveal" and c.challenger ~= nil then
    local isBlockChallenge = (c.blocker ~= nil)
    local revealer = isBlockChallenge and c.blocker or c.cur_action.source
    if p.device_id ~= revealer then return c end
    loser  = revealer
    reason = isBlockChallenge and "blockFailed" or "mainSourceWrong"
    c.challenger = nil
  end

  if loser == nil then return c end
  if p.device_id ~= loser then return c end   -- 只能本人失卡

  player_lose_slot(c, loser, p.slot)
  c.loser = nil
  c.lose_reason = nil

  -- 胜利判定
  if alive_count(c) <= 1 then
    for did, pl in pairs(c.players) do
      if pl.alive then c.winner = did end
    end
    state = "ended"
    return c
  end

  if reason == "mainChallengerWrong" then
    -- 主动作质疑失败：质疑者已失卡，原动作继续
    c.blocker = nil
    local at = c.cur_action.type
    if at == "FOREIGN_AID" or at == "STEAL" or at == "ASSASSINATE" then
      c.cur_phase = "block"
    else
      execute_action(c)
    end
  elseif reason == "blockFailed" then
    -- 阻断被反质疑成功：阻断无效，原动作继续执行
    c.blocker = nil; c.challenger = nil
    execute_action(c)
  else
    -- mainSourceWrong / blockChallengerWrong / effect：动作结束，推进回合
    c.cur_action = nil; c.cur_target = nil; c.blocker = nil
    c.cur_phase = "action"
    advance_turn(c)
  end
  return c
end
-- EXCHANGE 选保留的 2 张（保留数组的 0~1 索引为 c.exchange_cards 中的下标）
on_action_EXCHANGE_KEEP = function(c, p)
  if not role_check(c, p, "EXCHANGE_KEEP") then return c end
  if state ~= "playing" then return c end
  if c.ex_player == nil or c.exchange_cards == nil then return c end

  local cards  = c.exchange_cards
  local keep_n = c.exchange_keep or 2

  -- 收集要保留的下标（0-based）
  local idxs = {}
  if p.keep ~= nil then
    for _, v in ipairs(p.keep) do table.insert(idxs, v) end
  else
    if p.idx1 ~= nil then table.insert(idxs, p.idx1) end
    if p.idx2 ~= nil then table.insert(idxs, p.idx2) end
  end
  if #idxs ~= keep_n then return c end

  -- 合法性 + 去重
  local seen = {}
  for _, k in ipairs(idxs) do
    if k < 0 or k >= #cards then return c end
    if seen[k] then return c end
    seen[k] = true
  end

  -- 保留 / 归还
  local kept = {}
  for _, k in ipairs(idxs) do table.insert(kept, cards[k + 1]) end
  for i, card in ipairs(cards) do
    if not seen[i - 1] then return_card(c, card) end
  end

  -- 写回手牌：保留 keep_n 张为 alive，其余槽位置死
  local pl = c.players[c.ex_player]
  if keep_n >= 1 then pl.card1 = kept[1]; pl.card1_alive = true
  else pl.card1 = nil; pl.card1_alive = false end
  if keep_n >= 2 then pl.card2 = kept[2]; pl.card2_alive = true
  else pl.card2 = nil; pl.card2_alive = false end
  pl.hand_count = keep_n

  c.ex_player = nil
  c.exchange_cards = nil
  c.exchange_keep = nil
  advance_turn(c)
  return c
end

-- ============== 内部辅助 ==============

-- 质疑期无人质疑后：可阻断 → 进入 block 阶段；否则直接执行
function advance_after_challenge(c)
  local at = c.cur_action.type
  if at == "FOREIGN_AID" or at == "STEAL" or at == "ASSASSINATE" then
    c.cur_phase = "block"
  else
    execute_action(c)
  end
end

-- 阻断期（未被反质疑）：动作被抵消，回到 action 阶段并推进回合
function advance_after_block_challenge(c)
  -- 阻断未被反质疑 → 阻断有效 → 动作被抵消
  c.cur_action = nil
  c.cur_target = nil
  c.cur_phase = "action"
  advance_turn(c)
end

-- 执行动作效果（所有质疑/阻断均已解决后）
function execute_action(c)
  local at = c.cur_action.type
  local src = c.cur_action.source
  local tgt = c.cur_action.target
  local src_pl = c.players[src]

  if at == "INCOME" then
    src_pl.coins = src_pl.coins + 1
  elseif at == "FOREIGN_AID" then
    src_pl.coins = src_pl.coins + 2
  elseif at == "TAX" then
    src_pl.coins = src_pl.coins + 3
  elseif at == "COUP" then
    c.loser = tgt; c.lose_reason = "effect"   -- 金币已在 on_action_ACT 扣除
  elseif at == "STEAL" then
    local t_pl = c.players[tgt]
    local n = math.min(2, t_pl.coins or 0)
    src_pl.coins = src_pl.coins + n
    t_pl.coins = (t_pl.coins or 0) - n
  elseif at == "ASSASSINATE" then
    c.loser = tgt; c.lose_reason = "effect"
  elseif at == "EXCHANGE" then
    local c1 = draw_card(c); local c2 = draw_card(c)
    local options = { c1, c2 }
    local keep_n = 0
    if src_pl.card1_alive then table.insert(options, src_pl.card1); keep_n = keep_n + 1 end
    if src_pl.card2_alive then table.insert(options, src_pl.card2); keep_n = keep_n + 1 end
    c.ex_player = src
    c.exchange_cards = options
    c.exchange_keep = keep_n        -- 需要保留的张数（1 或 2）
    c.cur_phase = "exchange"
    return
  end

  if c.loser ~= nil then
    c.cur_phase = "loseCard"   -- ★ 保留 cur_action，等 LOSE_CARD 推进回合
    return
  end

  c.cur_action = nil; c.cur_target = nil; c.challenger = nil; c.blocker = nil
  c.cur_phase = "action"
  advance_turn(c)
end

-- 推进到下一回合
function advance_turn(c)
  if #(c.player_order or {}) == 0 then
    state = "ended"
    return
  end
  c.cur_player_idx = ((c.cur_player_idx or 0) + 1) % #c.player_order
  c.cur_action = nil
  c.cur_target = nil
  c.challenger = nil
  c.blocker = nil
  c.cur_phase = "action"
  -- 跳过已淘汰玩家
  while c.cur_player_idx < #c.player_order do
    local did = c.player_order[c.cur_player_idx + 1]
    local pl = c.players[did]
    if pl ~= nil and pl.alive then break end
    c.cur_player_idx = c.cur_player_idx + 1
    if c.cur_player_idx >= #c.player_order then c.cur_player_idx = 0 end
  end
end

return {
  definition = { functions = {
    "on_init", "on_join", "on_leave",
    "on_action_ACK", "on_action_START", "on_action_RESET",
    "on_action_ACT", "on_action_CHALLENGE", "on_action_BLOCK",
    "on_action_REVEAL", "on_action_PASS_RESP",
    "on_action_LOSE_CARD", "on_action_EXCHANGE_KEEP",
  }},
  on_init = on_init,
  on_join = on_join,
  on_leave = on_leave,
  on_action_ACK = on_action_ACK,
  on_action_START = on_action_START,
  on_action_RESET = on_action_RESET,
  on_action_ACT = on_action_ACT,
  on_action_CHALLENGE = on_action_CHALLENGE,
  on_action_BLOCK = on_action_BLOCK,
  on_action_REVEAL = on_action_REVEAL,
  on_action_PASS_RESP = on_action_PASS_RESP,
  on_action_LOSE_CARD = on_action_LOSE_CARD,
  on_action_EXCHANGE_KEEP = on_action_EXCHANGE_KEEP,
}
''';