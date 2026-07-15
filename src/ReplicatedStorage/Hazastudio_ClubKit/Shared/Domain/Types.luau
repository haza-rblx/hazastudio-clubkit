--!strict
-- Shared/Domain/Types.lua
local Types = {}
-- ============================================================
-- RESULT PATTERN
-- ============================================================
export type Result<T> =
	{
		ok: true,
		value: T,
	}
	| {
		ok: false,
		error: string,
	}
-- ============================================================
-- ROLE
-- ============================================================
export type RoleKey =
	"Owner"
	| "Investor"
	| "Staff"
	| "LeadDance"
	| "DJ"
	| "Streamer"
	| "Exclusive"
	| "RoyaleSpender"
	| "TopSpender"
	| "VVIP"
	| "VIP"
	| "Guest"
	-- Legacy keys (DataStore / old saves); normalize via Config.Roles.LEGACY_ALIASES.
	| "CoOwner"
	| "AfterTeam"
	| "Developer"
	| "Admin"
	| "Influencer"
	| "Spender"
	| "Tier3"
	| "Tier2"
	| "Tier1"
	| "ELITEMember"
	| "VVIPMember"
	| "VIPMember"
	| "Member"
export type MembershipTier =
	"Tier3" | "Tier2" | "Tier1" | "ELITEMember" | "VVIPMember" | "VIPMember" | "Member" | "Guest"
export type ShopMembershipTier = "Tier3" | "Tier2" | "Tier1"
export type GiftedMembershipEntry = {
	tier: MembershipTier,
	grantedBy: number?,
	grantedAt: number,
	source: string?,
}
export type TitleSizeKey = "S" | "M" | "L" | "XL" | "XXL"
export type TitleStyleData = {
	label: string,
	family: string,
	animMode: string,
	animSpeed: number,
	bgColors: { { number } },
	textColors: { { number } },
	bgRotation: number,
	textRotation: number,
	strokeColor: { number },
}
export type CommunityData = {
	id: number,
	name: string?,
	logo: string?,
}
export type CommunityLookupResult =
	{
		status: "found",
		community: CommunityData,
	}
	| {
		status: "not_found",
		query: string,
	}
	| {
		status: "ambiguous",
		query: string,
		candidates: { CommunityData },
	}
-- ============================================================
-- DATASTORE PAYLOAD
-- Data yang disimpan di DataStore per player
-- ============================================================
export type OverheadStoredData = {
	specialTitle: string?, -- nil = row hidden
	specialTitlePreset: string?, -- Title color preset mode ID (e.g. "Rainbow"), nil = legacy style path
	specialTitleSize: TitleSizeKey?,
	specialTitleFont: string?, -- Enum.Font name
	specialTitleStyle: TitleStyleData?,
	specialTitlePosition: string?, -- "Top" | "Stacked", nil = default (Top)
	specialRank: string?, -- nil = pakai rank normal (legacy, bisa dihapus)
	specialSubRole: string?, -- nil | "DJ" | "Influencer"
	giftedRole: string?, -- RoleKey yang di-gift, override group rank
	membershipBadge: string?, -- legacy compatibility
	ownedMembership: MembershipTier?,
	giftedMemberships: { GiftedMembershipEntry }?,
	giftedBy: number?, -- UserId yang ngasih gift
	giftedAt: number?, -- os.time() saat gift
	coupleData: any?, -- CoupleData, nil = single
	couplePartner: string?, -- display name pasangan untuk overhead (derived dari coupleData)
	couplePartnerId: number?, -- UserId pasangan (derived dari coupleData)
	showCoupleName: boolean?,
	publicOverheadLayerVisible: { [string]: boolean }?,
	publicOverheadBadgeVisible: { [string]: boolean }?,
	topDonateRank: number?, -- 1, 2, 3... nil = hidden
	topDonateText: string?, -- teks custom
	topSpenderRank: number?, -- 1, 2, 3... nil = hidden
	topSpenderText: string?, -- teks custom
	communityId: number?, -- Roblox Community (Group) Id yang aktif ditampilkan
	suppressCommunityBadge: boolean?, -- true = /clearcommun, jangan pakai primary fallback
	streakDays: number, -- default 0
	lastLoginAt: number, -- os.time() terakhir login, 0 = belum pernah
	level: number?, -- XP level (LevelSystemEnabled)
	xp: number?, -- XP progress within current level
	_version: number,
}
-- ============================================================
-- OVERHEAD PAYLOAD
-- Data lengkap yang dikirim server -> client
-- ============================================================
export type OverheadPayload = {
	userId: number,
	displayName: string,
	hasRobloxPremium: boolean,
	role: RoleKey,
	-- Row visibility + content
	specialTitle: string?,
	specialTitlePreset: string?, -- Title color preset mode ID (e.g. "Rainbow"), nil = legacy style path
	specialTitleSize: TitleSizeKey?,
	specialTitleFont: string?, -- Enum.Font name
	specialTitleStyle: TitleStyleData?,
	specialTitlePosition: string?, -- "Top" | "Stacked"
	specialRank: string?, -- nil = 04-SpecialRank hidden
	specialRankGradient: boolean,
	statusText: string?, -- nil = 00-SpecialStatus hidden
	rankText: string, -- selalu ada, minimal "GUEST"
	rankGradient: boolean,
	effectiveMembership: MembershipTier,
	membershipLabel: string,
	membershipRankText: string,
	membershipChatTag: string,
	membershipBadgeFrame: string?,
	membershipGradientName: string?,
	chatPrimaryTag: string,
	chatCoupleTag: string?,
	streakDays: number,
	level: number?,
	xp: number?,
	xpProgress: number?,
	xpNeeded: number?,
	levelText: string?,
	isCoupled: boolean,
	relationshipMode: ProfileRelationshipMode,
	showCoupleName: boolean,
	couplePartner: string?,
	topDonateRank: number?,
	topDonateText: string?,
	topSpenderRank: number?,
	topSpenderText: string?,
	isSpender: boolean, -- true kalo player masuk top leaderboard (Bagi-Bagi atau Robux)
	communityId: number?,
	communityName: string?,
	communityLogo: string?,
	likesCount: number,
	robuxDonated: number,
	cashDonated: number,
	-- Badge list yang harus VISIBLE (sisanya hidden)
	visibleBadges: { string },
	publicOverheadLayerVisible: { [string]: boolean },
	publicOverheadBadgeVisible: { [string]: boolean },
}
export type AboutRosterEntry = {
	userId: number,
	displayName: string,
	username: string,
	role: RoleKey,
	updatedAt: number,
}
-- ============================================================
-- COUPLE SYSTEM
-- ============================================================
export type CoupleStatus = "none" | "pending_sent" | "pending_received" | "coupled"
export type CoupleState = "IDLE" | "WAITING" | "COUPLED"
export type CoupleData = {
	partnerId: number?, -- UserId pasangan, nil = tidak punya couple
	partnerName: string?, -- DisplayName pasangan
	partnerUsername: string?, -- Username pasangan
	pendingTarget: number?, -- UserId yang direquest, nil = tidak ada
	coupledAt: number?, -- os.time() saat couple terbentuk
	couplesSince: number?, -- os.time() saat couple terbentuk (alias)
	_version: number?,
}
export type CoupleRequest = {
	fromUserId: number,
	fromName: string,
	fromUsername: string,
	toUserId: number,
	requestId: string,
	sentAt: number,
}
-- ============================================================
-- COUPLE REMOTE PAYLOADS
-- ============================================================
export type CoupleRequestPayload = {
	requestId: string,
	fromUserId: number,
	fromName: string,
	fromUsername: string,
}
export type CoupleResponsePayload = {
	requestId: string,
	accepted: boolean,
}
-- ============================================================
-- GIFT COMMAND PAYLOAD
-- ============================================================
export type GiftCommand = {
	targetUsername: string,
	roleKey: RoleKey,
	requestId: string,
}
-- ============================================================
-- INTERNAL CACHE ENTRY
-- ============================================================
export type CacheEntry<T> = {
	value: T,
	exp: number,
}
-- ============================================================
-- SYNC DANCE
-- ============================================================
export type FavoriteAnimations = {
	[string]: boolean,
}
export type SyncState = {
	isSyncing: boolean,
	leaderName: string?,
	leaderDisplay: string?,
	currentAnim: string?,
	currentSpeed: number,
	favoritedAnims: FavoriteAnimations,
	isInputLocked: boolean,
	isPanelOpen: boolean,
	-- Tambahkan field yang dipakai di SyncStore tapi tidak ada di type
	isDancePreparing: boolean,
	isDanceReady: boolean,
	pendingAnimationName: string?,
	pendingAnimationObject: Animation?,
	syncTargetUserId: number?,
}
export type SyncNotificationPayload = {
	type: string,
	leaderName: string?,
	leaderDisplay: string?,
	currentAnim: string?,
	targetUserId: number?,
}
-- ============================================================
-- CARRY SYSTEM
-- ============================================================
export type CarryStyle = "Piggyback" | "Bridal" | "Hug" | "Tandem" | "Fireman" | "Choke"
export type CarryCommandType = "REQUEST" | "ACCEPT" | "REJECT" | "END"
export type CarryCommandPayload = {
	type: CarryCommandType,
	requestId: string,
	payload: any,
}
export type CarryRequest = {
	carrierId: number,
	targetId: number,
	style: CarryStyle,
	sentAt: number,
}
export type CarryStateMode = "idle" | "selecting" | "waiting" | "pending" | "carrying"
-- ============================================================
-- AVATAR CONTEXT MENU
-- ============================================================
export type ProfileRelationshipMode = "Single" | "Taken" | "Fun"
export type ProfileStoredData = {
	bio: string?,
	displayNameOverride: string?,
	relationshipMode: ProfileRelationshipMode?,
	statusText: string?,
	lastBioUpdate: number?,
	lastStatusUpdate: number?,
	_version: number,
}
export type SocialProofData = {
	followersCount: number?,
	connectionsCount: number?,
}
export type AvatarContextPayload = {
	userId: number,
	displayName: string,
	username: string,
	role: RoleKey,
	effectiveMembership: MembershipTier,
	visibleBadges: { string },
	streakDays: number,
	couplePartner: string?,
	communityId: number?,
	communityName: string?,
	communityLogo: string?,
	relationshipText: string,
	bio: string?,
	statusText: string?,
	followersCount: number?,
	connectionsCount: number?,
	likesCount: number,
	viewerHasLiked: boolean,
	canSendGift: boolean,
	canSendFriendRequest: boolean,
	canInvestigateAvatar: boolean,
	canLike: boolean,
	canCarry: boolean,
	canSyncDance: boolean,
}
export type AvatarContextRequest = {
	targetUserId: number,
	requestId: string,
}
export type AvatarContextLikeAction = "like" | "unlike"
export type AvatarLikeTransition = "first_like" | "reliked" | "unliked" | "noop"
export type AvatarContextLikeRequest = {
	requestId: string,
	targetUserId: number,
	action: AvatarContextLikeAction,
}
export type AvatarContextResponse =
	{
		requestId: string,
		ok: true,
		payload: AvatarContextPayload,
	}
	| {
		requestId: string,
		ok: false,
		error: string,
	}
export type AvatarContextProfileUpdatedPayload = {
	targetUserId: number,
	bio: string?,
	statusText: string?,
}
export type AvatarContextUpdatedPayload = {
	targetUserId: number,
	payload: AvatarContextPayload,
}
export type AvatarContextLikeResult = {
	requestId: string,
	ok: boolean,
	targetUserId: number,
	likesCount: number?,
	viewerHasLiked: boolean?,
	transition: AvatarLikeTransition?,
	error: string?,
}
export type AvatarLikeEffectPayload = {
	fromUserId: number,
	toUserId: number,
	heartCount: number,
}
-- ============================================================
-- SETTINGS MENU
-- ============================================================
export type CameraFocusMode = "Torso" | "Head" | "FullBody"
export type SmoothLevel = "Off" | "Medium" | "High"
export type GraphicsPreset = "Low" | "Balanced" | "High"
export type UIScaleMode = "Small" | "Normal" | "Large"
export type OverheadDistanceMode = "Near" | "Medium" | "Far"
export type ShadowQuality = "Off" | "Balanced" | "High"
export type ChatBubbleVisibility = "All" | "Nearby" | "Off"
export type ProfileMenuPayload = {
	displayName: string,
	displayNameOverride: string?,
	bio: string?,
	statusText: string?,
	specialTitle: string?,
	canEditSpecialTitle: boolean,
	relationshipMode: ProfileRelationshipMode,
	isCoupled: boolean,
	couplePartner: string?,
	showCoupleName: boolean,
}

export type SettingsStoredData = {
	cameraFocus: CameraFocusMode,
	fov: number,
	smooth: SmoothLevel,
	uiScaleMode: UIScaleMode,
	eyeComfortMode: boolean,
	colorBrightness: number,
	colorContrast: number,
	colorSaturation: number,
	depthOfField: number,
	playerEffects: boolean,
	hideAllParticles: boolean,
	textures: number,
	musicVolume: number,
	-- 1+ = music default base is 100% (migrated from old 50% kit default)
	_musicVolBase: number,
	graphicsPreset: GraphicsPreset,
	shadowQuality: ShadowQuality,
	overheadDistance: OverheadDistanceMode,
	overheadLayerVisible: { [string]: boolean },
	overheadBadgeVisible: { [string]: boolean },
	chatBubbleVisibility: ChatBubbleVisibility,
	hideAdminAnnounce: boolean,
	hideCoupleAnnounce: boolean,
	hideDonationAnnounce: boolean,
	hideDonationWorldEffect: boolean,
	hideDonationAura: boolean,
	hideDonatorHighlight: boolean,
	hideSystemAnnounce: boolean,
	graphicsOverrides: { [string]: boolean },
	_version: number,
}

export type SettingsSessionData = {
	overheadVisible: boolean,
	overheadLayerVisible: { [string]: boolean },
	overheadBadgeVisible: { [string]: boolean },
	hideAllGui: boolean,
}

export type SettingsPayload = SettingsStoredData & SettingsSessionData
-- ============================================================
-- COMMAND LIBRARY
-- ============================================================
export type CommandLibraryCategory = "Profile" | "Community" | "Session" | "Admin"
export type CommandLibraryVisibilityMap = {
	[RoleKey]: boolean,
}
export type CommandLibraryEntry = {
	id: string,
	alias: string,
	display: string,
	description: string,
	category: CommandLibraryCategory,
	needsArguments: boolean,
	needsTrailingSpace: boolean,
	iconKey: string?,
	visibleToRoles: CommandLibraryVisibilityMap,
}
export type CommandLibraryExecuteRequest = {
	requestId: string,
	commandText: string,
}
export type CommandLibraryExecuteResponse =
	{
		requestId: string,
		ok: true,
	}
	| {
		requestId: string,
		ok: false,
		error: string,
	}
-- ============================================================
-- LOGGER INTERFACE
-- ============================================================
export type ILogger = {
	debug: (self: ILogger, msg: string, ctx: { [string]: any }?) -> (),
	info: (self: ILogger, msg: string, ctx: { [string]: any }?) -> (),
	warn: (self: ILogger, msg: string, ctx: { [string]: any }?) -> (),
	error: (self: ILogger, msg: string, ctx: { [string]: any }?) -> (),
}
-- ============================================================
-- REPOSITORY INTERFACE
-- ============================================================
export type IOverheadRepository = {
	load: (self: IOverheadRepository, userId: number) -> Result<OverheadStoredData>,
	loadStrict: (self: IOverheadRepository, userId: number) -> Result<OverheadStoredData>,
	update: (
		self: IOverheadRepository,
		userId: number,
		mutator: (current: OverheadStoredData) -> OverheadStoredData
	) -> Result<OverheadStoredData>,
	save: (self: IOverheadRepository, userId: number, data: OverheadStoredData) -> Result<nil>,
	flushSession: ((self: IOverheadRepository, userId: number) -> Result<nil>)?,
	invalidateCache: (self: IOverheadRepository, userId: number) -> (),
}
export type IAboutRosterRepository = {
	loadEntries: (self: IAboutRosterRepository) -> Result<{ AboutRosterEntry }>,
	upsertEntry: (self: IAboutRosterRepository, entry: AboutRosterEntry) -> Result<{ AboutRosterEntry }>,
	isRosterRole: (self: IAboutRosterRepository, role: string) -> boolean,
}
-- ============================================================
-- SERVICE INTERFACE
-- ============================================================
export type IOverheadService = {
	buildPayload: (self: IOverheadService, player: Player) -> Result<OverheadPayload>,
	buildPayloadWithMeta: (self: IOverheadService, player: Player) -> { result: Result<OverheadPayload>, usedFallback: boolean },
	getStored: (self: IOverheadService, userId: number) -> Result<OverheadStoredData>,
	invalidateGroupCache: (self: IOverheadService, userId: number) -> (),
	getRawGroupRole: (self: IOverheadService, player: Player) -> RoleKey,
	getEffectivePayload: (self: IOverheadService, player: Player) -> Result<OverheadPayload>,
	resolveCommunity: (self: IOverheadService, player: Player, communityId: number) -> Result<CommunityData>,
	resolveCommunityByQuery: (self: IOverheadService, player: Player, query: string) -> Result<CommunityLookupResult>,
	getAboutRosterEntries: (self: IOverheadService) -> Result<{ AboutRosterEntry }>,
	syncAboutRosterEntry: (
		self: IOverheadService,
		player: Player,
		payload: OverheadPayload
	) -> Result<{ AboutRosterEntry }>,
	isAboutRosterRole: (self: IOverheadService, role: string) -> boolean,
}
-- ============================================================
-- DONATION / SAWERIA SYSTEM
-- ============================================================
export type DonationEntry = {
	rank: number,
	saweriaName: string,
	robloxUsername: string?, -- nil jika belum ter-match
	robloxUserId: number?,
	totalAmount: number,
	lastDonationAt: string, -- ISO date string dari sheets
}
export type DonationNotifPayload = {
	saweriaName: string,
	amount: number,
	message: string?,
	newRank: number?, -- rank mereka setelah donasi, nil jika tidak masuk top 10
	robloxUsername: string?,
	robloxUserId: number?,
	robloxDisplayName: string?,
	totalDonationAmount: number?,
	source: string?, -- "cash" | "robux" | legacy provider keys | nil
}
export type DonationLeaderboardPayload = {
	daily: { DonationEntry },
	allTime: { DonationEntry },
	updatedAt: number, -- os.time() saat data di-fetch
}
export type DonorProfilePayload = {
	userId: number,
	username: string,
	displayName: string,
	robuxTotal: number,
	robuxRank: number?,
	cashTotal: number,
	cashRank: number?,
}
return Types
