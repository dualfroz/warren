local helpers = require("helpers")
local Text = require("text")
local Status = require("status")

local eq = helpers.eq

local tests = helpers.suite()

function tests.joinNaturallyReadsAsPlainEnglishForAnyListLength()
  eq(Text.joinNaturally({ "rat" }), "rat", "a single phrase is returned as is")
  eq(Text.joinNaturally({ "rat", "orc" }), "rat and orc", "two phrases are joined with and, no comma")
  eq(Text.joinNaturally({ "rat", "orc", "troll" }), "rat, orc and troll", "three phrases read as a, b and c")
end

function tests.statusJoinsThroughTheSharedTextHelper()
  eq(Status.joinNaturally, Text.joinNaturally, "Status reuses the general text helper instead of its own copy")
end

return tests
