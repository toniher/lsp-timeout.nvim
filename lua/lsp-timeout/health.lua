--- @module lsp-timeout.health
--- :checkhealth lsp-timeout
local M = {}

-- NVIM v0.7.2 has no vim.health global at all (only require("health"));
-- NVIM <0.10 (post-move) only has vim.health.report_*; newer versions alias
-- the old names to the new ones but print a deprecation notice, so prefer
-- the new API when present.
local health = vim.health or require("health")
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local err = health.error or health.report_error

local function checkLspCommands()
	-- NVIM v0.12+: lsp enable/stop commands (built-in)
	-- NVIM <0.12: LspStart/LspStop commands (via lspconfig)
	local hasLspEnable = vim.lsp and type(vim.lsp.enable) == "function"
	local hasLspStart = vim.fn.exists(":LspStart") == 1
	local hasLspStop = vim.fn.exists(":LspStop") == 1

	if hasLspEnable then
		ok("vim.lsp.enable/vim.lsp.get_configs available (NVIM 0.12+)")
	elseif hasLspStart and hasLspStop then
		ok(":LspStart/:LspStop available (via nvim-lspconfig)")
	else
		err(
			"LSP commands (LspStart/LspStop or vim.lsp.enable) are NOT found."
				.. " Make sure nvim-lspconfig is installed or use NVIM v0.12+"
		)
	end

	local hasGetConfigs = vim.lsp and type(vim.lsp.get_configs) == "function"
	if hasGetConfigs then
		ok("vim.lsp.get_configs available")
	else
		local lspconfigOk, util = pcall(require, "lspconfig.util")
		if lspconfigOk and util.get_config_by_ft then
			ok("lspconfig.util.get_config_by_ft available")
		else
			err(
				"Could not find LSP config getter (vim.lsp.get_configs or lspconfig.util)."
					.. " Please use NVIM v0.12+ or install nvim-lspconfig!"
			)
		end
	end
end

local function checkConfig()
	local Config = require("lsp-timeout.config").Config
	local deprecatedKey = vim.g["lsp-timeout-config"]
	local userConfig = deprecatedKey or vim.g.lspTimeoutConfig

	if deprecatedKey then
		warn('vim.g["lsp-timeout-config"] is deprecated, use vim.g.lspTimeoutConfig instead (removal planned for v1.3.0)')
	end

	if not userConfig then
		ok("no user config set, using defaults")
		return
	end

	local validateOk, validateErr = pcall(function()
		Config:new(vim.deepcopy(userConfig)):validate()
	end)

	if validateOk then
		ok("config validated successfully")
	else
		err("config validation failed: " .. tostring(validateErr))
	end
end

local function checkTimers()
	local state = _G.lspTimeOutState
	if not state then
		ok("no lsp-timeout state yet (plugin not triggered this session)")
		return
	end

	for _, timerName in ipairs({ "stopTimer", "startTimer" }) do
		local timer = state[timerName]
		if not timer then
			ok(("%s not set"):format(timerName))
		else
			local activeOk, isActive = pcall(function()
				return timer:is_active()
			end)
			if activeOk and isActive then
				ok(("%s is active (a stop/start is currently pending)"):format(timerName))
			else
				warn(("%s is set but not active - may be a stale reference"):format(timerName))
			end
		end
	end
end

function M.check()
	start("lsp-timeout.nvim")
	checkLspCommands()

	start("lsp-timeout.nvim: config")
	checkConfig()

	start("lsp-timeout.nvim: timers")
	checkTimers()
end

return M
