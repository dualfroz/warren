local Text = {}

function Text.joinNaturally(phrases)
  if #phrases == 1 then return phrases[1] end
  return table.concat(phrases, ", ", 1, #phrases - 1) .. " and " .. phrases[#phrases]
end

return Text
