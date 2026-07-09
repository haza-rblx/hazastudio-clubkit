--!strict
--[[
  INTERNAL — buyer tidak edit file ini.
  Satu sumber buyer: Hazastudio_ClubKitConfig/ClubKitConfig.luau

  Hanya berisi default Showcase (angka random demo) untuk field yang tidak diisi buyer.
]]

local ClubKitDefaults = {}

ClubKitDefaults.Showcase = {
	Enabled = false,
	LeaderboardUseOwnerOnly = false,
	SourceUserId = 0,
	MinAmount = 100000,
	MaxAmount = 10000000,
	RobuxMinAmount = 100,
	RobuxMaxAmount = 50000,
	LeaderboardLimit = 10,
	RefreshInterval = 300,
	Profiles = nil :: { { UserId: number, Username: string?, DisplayName: string? } }?,
	Communities = nil :: { { CommunityId: number, CommunityName: string, CommunityLogo: string? } }?,
}

return ClubKitDefaults
