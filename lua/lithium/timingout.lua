if SERVER then return end

local function create_font(name, size)
	if not surface or not surface.CreateFont then return end

	surface.CreateFont(name, {
		font = "Tahoma", -- Use guaranteed fallback to avoid missing workshop font spam.
		size = size,
		weight = 500
	})
end

create_font("LITHIUMTimeoutFontBig", 64)
create_font("LITHIUMTimeoutFontMedium", 34)
create_font("LITHIUMTimeoutFontSmall", 20)

local function DrawWarningStripe(x, y, w, h)
	local r = (math.sin(RealTime() * 2) + 1) * 255 / 2
	local s = 40
	surface.SetDrawColor(r, 0, 0, r)
	draw.NoTexture()
	for x1=-s*2+x,w+s+x,s do
		x1 = x1 + ((RealTime() * 20) % s)
		surface.DrawPoly({
			{x=x1, y=y}, {x=x1+s/2, y=y}, {x=x1+s, y=h+y}, {x=x1+s/2, y=h+y},
		})
	end
	surface.SetDrawColor(255-r, 0, 0, 255-r)
	for x1=-s/2-s+x,w-s/2+s+x,s do
		x1 = x1 + ((RealTime() * 20) % s)
		surface.DrawPoly({
			{x=x1, y=y}, {x=x1+s/2, y=y}, {x=x1+s, y=h+y}, {x=x1+s/2, y=h+y},
		})
	end
end

local timeoutcv = GetConVar("cl_timeout")
local starttimingout, endtimingout = nil, nil
local splash = nil
local splashes = {
	(game.SinglePlayer() and "How does something like that even happen in singleplayer?" or "Wowza! Amazing!"),
	"Oh man, I thought that 'server crasher dupe 2024' wouldn't work...",
	":clueless:",
	":cluedin:",
	"Something screwed up, trying to unscrew it...",
	"And you thought it was a good idea to do THIS?",
	"ah for FU-",
	"Are you kidding me? Everything went so smooth!",
	":braindamage:"
}

hook.Add("PostRenderVGUI", "LITHIUM_Timingout", function()
	if not surface or not draw then return end

	local timingout, lastping = GetTimeoutInfo()
	if not timingout and not starttimingout then return end

	local frac, passed = 0, 0
	if not timingout and starttimingout then
		endtimingout = endtimingout or RealTime()
		passed = math.max(0, 1 - (RealTime() - endtimingout))
		frac = math.min(1, passed)
		if frac < 0 then
			starttimingout = nil
			endtimingout = nil
			splash = nil
			return
		end
	else
		starttimingout = starttimingout or RealTime()
		passed = RealTime() - starttimingout
		frac = math.min(1, passed)
	end

	surface.SetDrawColor(0, 0, 0, (127+63) * math.ease.OutCirc(frac))
	surface.DrawRect(0, 0, ScrW(), ScrH())

	splash = splash or splashes[math.random(1, #splashes)]

	DrawWarningStripe(0, -32 * (1-math.ease.OutCirc(frac)), ScrW(), 32)
	DrawWarningStripe(0, ScrH()-32 * math.ease.OutCirc(frac), ScrW(), 32)
	local color = ColorAlpha(color_white, 255 * frac)
	draw.DrawText(string.sub("CONNECTION ISSUES", 1, 17*frac), "LITHIUMTimeoutFontBig", ScrW() / 2, 32, color, TEXT_ALIGN_CENTER)
	draw.DrawText(string.sub(splash, 1, #splash*frac), "LITHIUMTimeoutFontMedium", ScrW() / 2, 96, color, TEXT_ALIGN_CENTER)
	draw.DrawText(string.sub("Last ping received: "..string.format("%.2f", lastping).."s ago", 1, 35*frac), "LITHIUMTimeoutFontMedium", 16, ScrH() - 70, color, TEXT_ALIGN_LEFT)
	draw.DrawText(string.sub("Disconnecting in T-"..string.format("%.2f", math.max(0, timeoutcv:GetFloat()-lastping)), 1, 29*frac), "LITHIUMTimeoutFontMedium", ScrW()-16, ScrH() - 70, color, TEXT_ALIGN_RIGHT)

	color = ColorAlpha(color_white, 255 * math.max(0, math.min(1, passed - 3)))
	draw.DrawText(string.sub("Possible reasons may include:", 1, 29 * math.max(0, math.min(1, passed - 3))), "LITHIUMTimeoutFontSmall", 16, 166, color, TEXT_ALIGN_LEFT)
	for n,txt in pairs({
		"Server has crashed or was shut down incorrectly.",
		"Your internet connection was terminated or experiences extreme lag.",
		"Server is unresponsive to commands or pings."
	}) do
		local line_frac = math.max(0, math.min(1, passed - (n*0.5 + 3)))
		local line_color = ColorAlpha(color_white, 255 * line_frac)
		draw.DrawText(string.sub(txt, 1, #txt * line_frac), "LITHIUMTimeoutFontSmall", 16*2, 166+20 * n, line_color, TEXT_ALIGN_LEFT)
	end
end)
