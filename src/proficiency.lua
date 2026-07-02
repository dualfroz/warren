-- Weapon mastery: every melee swing the player lands (Game:playerAttack)
-- nudges their familiarity with whichever weapon delivered it - or their
-- bare fists, wielding nothing - forward by one point, keyed by the
-- weapon's own name so a build's proficiency carries seamlessly from one
-- identical drop to the next with no separate catalog of weapon
-- "categories" to keep in sync with builder.lua's loot tables, artifacts.
-- lua's named weapons, or a set piece's own name. Crossing a rank threshold
-- grants a small, permanent flat attack bonus with that specific weapon (or
-- fists) alone, read live by Entity:effectiveAttack exactly like momentum.
-- lua's combo stacks or sanity.lua's dread penalty - so re-equipping a
-- weapon already mastered picks the bonus straight back up, but switching
-- to something unfamiliar drops it until that one is mastered in turn.
--
-- Melee reads and writes its own key automatically (Proficiency.keyFor
-- reads the equipped weapon slot, or Proficiency.UNARMED bare-handed), but
-- the underlying Proficiency.onHitWith/bonusFor pair takes any explicit key
-- instead - ranged.lua uses this to track mastery of an equipped bow by its
-- own name, entirely separate from whatever melee weapon (if any) happens
-- to be equipped alongside it, since Ranged.fire deliberately deals damage
-- off baseAttack rather than effectiveAttack (see its own header).

local Proficiency = {}

Proficiency.UNARMED = "fists"

-- Hits needed to cross each mastery rank, and the flat attack bonus that
-- rank grants from then on. Only the highest rank crossed applies (each is
-- already the running total, not a stacking delta), but the gap between
-- ranks widens the deeper it goes, so the later ones are meant to take a
-- genuinely long, dedicated run with one weapon to ever reach.
Proficiency.RANKS = {
  { hits = 15,  bonus = 1 },
  { hits = 40,  bonus = 2 },
  { hits = 80,  bonus = 3 },
  { hits = 150, bonus = 4 },
}

-- The mastery key `entity` is currently swinging: an equipped weapon's own
-- name, or Proficiency.UNARMED for bare fists.
function Proficiency.keyFor(entity)
  return entity.weapon and entity.weapon.name or Proficiency.UNARMED
end

function Proficiency.hits(entity, key)
  return (entity.proficiency and entity.proficiency[key]) or 0
end

-- Records one more landed hit under an explicit `key`, and returns that key
-- plus the newly reached rank's bonus the instant a threshold is first
-- crossed - nil otherwise, so a caller only ever logs a genuine milestone
-- rather than every single swing or shot.
function Proficiency.onHitWith(entity, key)
  entity.proficiency = entity.proficiency or {}
  local before = entity.proficiency[key] or 0
  local after = before + 1
  entity.proficiency[key] = after
  for _, rank in ipairs(Proficiency.RANKS) do
    if before < rank.hits and after >= rank.hits then
      return key, rank.bonus
    end
  end
  return nil
end

-- The flat attack bonus `entity` currently draws from mastery of `key`
-- alone - never a total across every weapon it has ever swung or fired, so
-- switching weapons genuinely costs something.
function Proficiency.bonusFor(entity, key)
  local hits = Proficiency.hits(entity, key)
  local bonus = 0
  for _, rank in ipairs(Proficiency.RANKS) do
    if hits >= rank.hits then bonus = rank.bonus end
  end
  return bonus
end

-- Melee's own auto-keyed shorthand over the two generic functions above:
-- always reads and writes whatever Proficiency.keyFor currently reports for
-- `entity` (its equipped weapon, or bare fists).
function Proficiency.onMeleeHit(entity)
  return Proficiency.onHitWith(entity, Proficiency.keyFor(entity))
end

function Proficiency.attackBonus(entity)
  return Proficiency.bonusFor(entity, Proficiency.keyFor(entity))
end

return Proficiency
