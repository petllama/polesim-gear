-- A stub C_AuctionHouse for the AH tests (test_ah, test_ahpanel).
local A = {}

-- A stub C_AuctionHouse: the browse system with pages and a throttle. -> api, log
-- server: list of browse results returned for every query (pages of `page` results), or a function
-- (query) -> list. ready(): IsThrottledMessageSystemReady. Purchase functions error when called.
function A.stub(server, page)
	page = page or 2
	local log = { sent = {}, more = 0, bought = 0 }
	local api = { ready = true }
	local all, shown = {}, 0
	local function list() local out = {} for i = 1, shown do out[i] = all[i] end return out end
	function api.IsThrottledMessageSystemReady() return api.ready end
	function api.SendBrowseQuery(q)
		assert(api.ready, "sent while throttled")
		log.sent[#log.sent + 1] = q
		all = type(server) == "function" and server(q) or server
		shown = math.min(page, #all)
		log.pending = "updated"
	end
	function api.RequestMoreBrowseResults()
		assert(api.ready, "asked for more while throttled")
		log.more = log.more + 1
		shown = math.min(shown + page, #all)
		log.pending = "added"
	end
	function api.GetBrowseResults() return list() end
	function api.HasFullBrowseResults() return shown >= #all end
	function api.GetItemKeyInfo(key) return { itemID = key.itemID, itemName = api.names and api.names[key.itemID] or "x", quality = 2, isCommodity = false } end
	for _, f in ipairs({ "PlaceBid", "StartCommoditiesPurchase", "ConfirmCommoditiesPurchase" }) do
		api[f] = function() log.bought = log.bought + 1 error("bought") end
	end
	return api, log
end

function A.result(id, price, suffix) return { itemKey = { itemID = id, itemLevel = 0, itemSuffix = suffix or 0, battlePetSpeciesID = 0 }, minPrice = price, totalQuantity = 1, containsOwnerItem = false } end


return A
