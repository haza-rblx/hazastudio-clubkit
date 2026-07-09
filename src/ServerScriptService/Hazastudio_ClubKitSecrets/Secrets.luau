--!strict
-- Server-only secrets. Path: ServerScriptService.Hazastudio_ClubKitSecrets.Secrets
--
-- This module is NEVER replicated to clients. All server-side code that needs
-- API secrets should require this module instead of reading from Config.
--
-- TEMPLATE: fill these before enabling donation API or game-data API features.
-- Must match the secrets configured on your Cloudflare Worker / backend.
--
-- SECURITY: never commit real secrets here. Leave empty for distribution.
-- Deployer fills these in ServerScriptService.Hazastudio_ClubKitSecrets.Secrets
-- after inserting the .rbxm. Keep your live secrets out of source control.

local Secrets = {}

-- Cloudflare Game Data API secret (OverheadService group ranks, ProfileSocialService)
Secrets.GameDataApiSecret = ""

-- Donation API secret (DonationService Bagi-Bagi / Saweria worker)
Secrets.DonationApiSecret = ""

return Secrets
