	Tier3 = { Label = "Supreme", Enabled = true, Priority = 60 },
}

-- =============================================================================
-- ROLE CATEGORIES (group rank → role; match your Roblox group)
-- privileges per category: canGift, canAnnounce, canTeleport, adminPanel, musicManage
-- =============================================================================
ClubKitConfig.RoleCategories = {
	{
		id = 1,
		label = "Leadership",
		priority = 140,
		enabled = true,
		privileges = {
			canGift = true,
			canAnnounce = true,
			canTeleport = true,
			adminPanel = true,
			musicManage = true,
		},
		roles = {
			{
				key = "CoOwner",
				label = "Co-Owner",
				chatTag = "CO-OWNER",
				toolFolder = "STAFF",
				teamColor = "New Yeller",
				enabled = true,
				specialRank = { text = "CO-OWNER", gradient = true },
				badgeFrames = { "01-OwnerCoOwnerBadge" }, -- same badge frame as Owner
				roleColor = { primary = "#FBBF24", secondary = "#FDE68A" },
			},
			{
				key = "Staff",
				label = "Staff",
				chatTag = "STAFF",
				toolFolder = "STAFF",
				teamColor = "Royal purple",
				enabled = true,
				specialRank = { text = "STAFF", gradient = true },
				badgeFrames = { "03-AdminBadge" },
				roleColor = { primary = "#7C3AED", secondary = "#A78BFA" },
			},
		},
	},
	{
		id = 2,
		label = "Moderation",
		priority = 130,
		enabled = true,
		privileges = {
			canGift = false,
			canAnnounce = true,
			canTeleport = true,
			adminPanel = false,
			musicManage = false,
		},
		roles = {
			{
				key = "Moderator",
				label = "Moderator",
				chatTag = "MODERATOR",
				toolFolder = "MODERATOR",
				teamColor = "Bright violet",
				enabled = true,
				specialRank = { text = "MODERATOR", gradient = true },
				roleColor = { primary = "#8B5CF6", secondary = "#C4B5FD" },
			},
		},
	},
	{
		id = 3,
		label = "Content",
		priority = 120,
		enabled = true,
		privileges = {
			canGift = false,
			canAnnounce = false,
			canTeleport = false,
			adminPanel = false,
			musicManage = true,
		},
		roles = {
			{
				key = "DJ",
				label = "DJ",
				chatTag = "DJ",
				toolFolder = "DJ",
				teamColor = "Cyan",
				enabled = true,
				specialRank = { text = "DJ", gradient = true },
				showSpecialStatus = true,
				roleColor = { primary = "#06B6D4", secondary = "#67E8F9" },
			},
			{
				key = "LeadDance",
				label = "Lead Dance",
				chatTag = "LEAD DANCE",
				toolFolder = "LEAD DANCE",
				teamColor = "Really red",
				enabled = true,
				specialRank = { text = "LEAD DANCE", gradient = true },
				showSpecialStatus = true,
				roleColor = { primary = "#BE123C", secondary = "#FB7185" },
			},
			{
				key = "Streamer",
				label = "Streamer",
				chatTag = "STREAMER",
				toolFolder = "STREAMER",
				teamColor = "Magenta",
				enabled = true,
				specialRank = { text = "STREAMER", gradient = true },
				showSpecialStatus = true,
				roleColor = { primary = "#C026D3", secondary = "#E879F9" },
			},
			{
				key = "Influencer",
				label = "Influencer",
				chatTag = "INFLUENCER",
				toolFolder = "INFLUENCER",
				teamColor = "Hot pink",
				enabled = true,
				specialRank = { text = "INFLUENCER", gradient = true },
				showSpecialStatus = true,
				roleColor = { primary = "#DB2777", secondary = "#F9A8D4" },
			},
		},
	},
} :: { any }

-- =============================================================================
-- SPENDER ROLES (donor leaderboard — label/chatTag freely editable)
-- =============================================================================
ClubKitConfig.SpenderRoles = {
	CashSpender = {
		Enabled = true,
		Key = "TopSpender",
		Label = "Top Rupiah Spender",
		ChatTag = "TOP RUPIAH SPENDER",
		ToolFolder = "TOP RUPIAH SPENDER",
		MaxRank = 10,
		Priority = 80,
		TeamColor = "Lime green",
		roleColor = { primary = "#84CC16", secondary = "#BEF264" },
		Privileges = {
			canAnnounce = true,
			canTeleport = true,
		},
	},
	RobuxSpender = {
		Enabled = true,
		Key = "RoyaleSpender",
		Label = "Top Robux Donator",
		ChatTag = "TOP ROBUX DONATOR",
		ToolFolder = "TOP ROBUX DONATOR",
		MaxRank = 10,
		Priority = 90,
		TeamColor = "Bright bluish green",
		roleColor = { primary = "#14B8A6", secondary = "#5EEAD4" },
		SpecialRank = { text = "TOP ROBUX DONATOR", gradient = true },
		Privileges = {
			canAnnounce = true,
			canTeleport = true,
		},
	},
}

-- =============================================================================
-- SYSTEM ROLES (Owner/Guest — groupRanks = Roblox group rank)
-- =============================================================================
ClubKitConfig.SystemRoles = {
	Owner = {
		label = "Owner",
		chatTag = "OWNER",
		priority = 15000,
		groupRanks = { 255 },
		specialRank = { text = "OWNER", gradient = true },
		roleColor = { primary = "#FFD700", secondary = "#FFF0A0" },
		teamColor = "Gold",
		badgeFrames = { "01-OwnerCoOwnerBadge" },
		canGift = true,
		giftable = false,
	},
	Guest = {
