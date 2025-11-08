pcall(function()
  do
    	local text = "WFYBExploits.XYZ"
    	local url = "https://asciified.thelicato.io/api/v2/ascii?text=" .. text
    	local response = game:HttpGet(url)
    	print(response)
    end
end)
