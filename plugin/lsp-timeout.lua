local uv = vim.uv or vim.loop
local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd
local auclear = vim.api.nvim_clear_autocmds

-- If this blocks throws an error, you have misconfigured your lsp-timeout
local auLSTO = augroup("LSPTimeout", { clear = true })
local auLSTOBL = augroup("LSPTimeoutBufferLocal", { clear = true })

_G.lspTimeOutState = _G.lspTimeOutState or { b = {} }

autocmd({ "VimEnter" }, {
	desc = "Check if nvim-lspconfig commands are available",
	group = auLSTO,
	once = true,
	callback = function()
		-- We depend on lspconfig utils
		-- If there is a none, clear autcomd
		-- and report an error
		--
		--- Return true if no lsp-config commands are found
		local lspconfigFailed = false
		-- NVIM v0.12+: lsp enable/stop commands (built-in)
		-- NVIM <0.12: LspStart/LspStop commands (via lspconfig)
		local hasLspEnable = vim.lsp and type(vim.lsp.enable) == "function"
		local hasLspStart = vim.fn.exists(":LspStart") == 1
		local hasLspStop = vim.fn.exists(":LspStop") == 1

		-- For NVIM 0.12+, built-in vim.lsp.enable() is available
		-- For older versions, lspconfig provides LspStart/LspStop commands
		local lspCmdsAvailable = hasLspEnable or (hasLspStart and hasLspStop)
		if not lspCmdsAvailable then
			local message = "LSP commands (LspStart/LspStop or lsp enable/stop) are NOT found."
				.. " Make sure lspconfig.nvim is installed or use NVIM v0.12+"
			vim.notify(message, vim.log.levels.ERROR)
			lspconfigFailed = true
		end

		-- For NVIM 0.12+, use built-in vim.lsp.get_configs()
		-- For older versions, use lspconfig.util.get_config_by_ft()
		local lspcfgUtil = nil
		local getConfigsByFt = nil

		if vim.lsp and vim.lsp.get_configs then
			getConfigsByFt = function(ft)
				local configs = vim.lsp.get_configs({ filetype = ft, enabled = true })
				-- Convert to lspconfig-like format for compatibility
				return configs
			end
		else
			local ok, util = pcall(require, "lspconfig.util")
			if ok and util.get_config_by_ft then
				lspcfgUtil = util
				getConfigsByFt = function(ft)
					return lspcfgUtil.get_config_by_ft(ft)
				end
			end
		end

		if not getConfigsByFt then
			vim.notify(
				"lsp-timeout: Could not find LSP config getter (vim.lsp.get_configs or lspconfig.util). Please use NVIM v0.12+ or install lspconfig.nvim!",
				vim.log.levels.ERROR
			)
			lspconfigFailed = true
		end

		if lspconfigFailed then
			auclear({ group = auLSTO })
			auclear({ group = auLSTOBL })
			return
		end

		-- Store the config getter globally for use in autocmds
		_G.lspTimeOutState.getConfigsByFt = getConfigsByFt

		-- CONTINUE: [October 29, 2023] warn users about
		local userConfig = vim.g["lsp-timeout-config"] or vim.g.lspTimeoutConfig
		if userConfig then
			local Config = require("lsp-timeout.config").Config
			Config:new(userConfig):validate()
		end
		if vim.g["lsp-timeout-config"] then
			vim.deprecate('vim.g["lsp-timeout-config"]', "vim.g.lspTimeoutConfig", "v1.3.0", "lsp-timeout.nvim", false)
		end
	end,
})

autocmd({ "FocusGained" }, {
	desc = "Start LSP servers if application window is focused",
	group = auLSTO,
	callback = function(fgAuEvent)
		local lspPostponeStartup = function(auEvent, clientsAvailable)
			-- Clear up lsp stop timer
			if _G.lspTimeOutState.stopTimer then
				_G.lspTimeOutState.stopTimer:stop()
				_G.lspTimeOutState.stopTimer:close()
				_G.lspTimeOutState.stopTimer = nil
			end

			local ok, configModule = pcall(require, "lsp-timeout.config")
			if not ok or not configModule or not configModule.default then
				vim.notify("lsp-timeout: Could not load config default!", vim.log.levels.ERROR)
				return
			end
			local config = configModule.default:extend(
				vim.b[auEvent.buf].lspTimeoutConfig or vim.g["lsp-timeout-config"] or vim.g.lspTimeoutConfig or {}
			)
			if vim.tbl_contains(config.filetypes.ignore, vim.bo[auEvent.buf].filetype) then
				return
			end

			-- LuaFormatter off
			local napi = require("lsp-timeout.nvim-api")
			local clientsRunning = napi.Lsp:clients({ buf = auEvent.buf })
			_G.lspTimeOutState.b[auEvent.buf] = _G.lspTimeOutState.b[auEvent.buf] or {}
			local clientsStopped = _G.lspTimeOutState.b[auEvent.buf].stopped_clients or {}
			local clientsLspConfig = {}
			local clientsOthers = {}
			-- LuaFormatter on
			if #clientsStopped == 0 then
				clientsLspConfig = clientsAvailable
			else
				for i, clientStopped in ipairs(clientsStopped) do
					local lspClientToRun = nil
					for j, lspConfigClient in ipairs(clientsAvailable) do
						if clientStopped.name == lspConfigClient.name then
							lspClientToRun = lspConfigClient
							break
						end
					end

					if lspClientToRun ~= nil then
						table.insert(clientsLspConfig, lspClientToRun)
					else
						table.insert(clientsOthers, clientStopped)
					end
				end
			end

			if not _G.lspTimeOutState.startTimer and #clientsRunning < (#clientsLspConfig + #clientsOthers) then
				-- Postpone startup
				local timeout = config.startTimeout

				-- ref: https://github.com/neovim/neovim/pull/22846
				_G.lspTimeOutState.startTimer = uv.new_timer()
				_G.lspTimeOutState.startTimer:start(
					timeout,
					0,
					vim.schedule_wrap(function()
						if not config.silent then
							-- LuaFormatter off
							vim.notify(
								"lsp-timeout: "
									.. #clientsLspConfig + #clientsOthers
									.. " inactive LSPs found, restarting... ",
								vim.log.levels.INFO
							)
							-- LuaFormatter on
						end

						for _, client in ipairs(clientsLspConfig) do
							client.launch()
						end
						for _, client in ipairs(clientsOthers) do
							vim.lsp.start(client.config)
						end

						_G.lspTimeOutState.b[auEvent.buf].stopped_clients = {}

						if _G.lspTimeOutState.startTimer then
							_G.lspTimeOutState.startTimer:stop()
							_G.lspTimeOutState.startTimer:close()
							_G.lspTimeOutState.startTimer = nil
						end
					end)
				)
			end
		end

		-- clear up previously setup buffer local event listeners
		auclear({ group = auLSTOBL })
		local napi = require("lsp-timeout.nvim-api")
		local getConfigsByFt = _G.lspTimeOutState.getConfigsByFt

		-- Evalutabe every window/buffer in currently focused tab
		local tabPageWindows = vim.api.nvim_tabpage_list_wins(0)
		local tabPageBuffers = vim.tbl_map(function(winHandle)
			return vim.api.nvim_win_get_buf(winHandle)
		end, tabPageWindows)
		for i, bufferHandle in ipairs(tabPageBuffers) do
			-- LuaFormatter off
			local winHandle = tabPageWindows[i]
			local bufWritable = napi.Buffer:option("modifiable", bufferHandle)
			local bufType = napi.Buffer:option("filetype", bufferHandle)
			local winIsDiff = napi.Window:option("diff", winHandle)
			-- LuaFormatter on

			-- Skip readonly and diff windows (diffviews) - there are no LSPs
			if not bufWritable or winIsDiff then
				goto loop_tpb_end
			end

			-- Startup a FocusGained buffer found in current tab
			if bufferHandle == fgAuEvent.buf then
				local clientsAvailable = {}
				if getConfigsByFt then
					clientsAvailable = getConfigsByFt(bufType) or {}
				end
				if #clientsAvailable > 0 then
					lspPostponeStartup(fgAuEvent, clientsAvailable)
				end
				goto loop_tpb_end
			end

			-- If a current FocusGained buffer in focused tab is readonly,
			-- bind writable ones to a disposable lsp startup-handler
			autocmd({ "BufEnter" }, {
				once = true,
				-- pattern  = "*",
				group = auLSTOBL,
				buffer = bufferHandle,
				callback = function(auEvent)
					local getConfigsByFt = _G.lspTimeOutState.getConfigsByFt
					local clientsAvailable = {}
					if getConfigsByFt then
						clientsAvailable = getConfigsByFt(vim.bo[auEvent.buf].filetype) or {}
					end
					if #clientsAvailable > 0 then
						lspPostponeStartup(auEvent, clientsAvailable)
					end
					-- Clean up the rest of buffer-local event listeners
					auclear({ group = auLSTOBL })
				end,
				desc = "Start LSP servers if inner window is focused",
			})

			::loop_tpb_end::
		end -- for loop end
	end,
})

autocmd({ "FocusLost" }, {
	desc = "Stop LSP servers if application window isn't focused",
	group = auLSTO,
	callback = function(auEvent)
		-- Clear up lsp start timer
		if _G.lspTimeOutState.startTimer then
			_G.lspTimeOutState.startTimer:stop()
			_G.lspTimeOutState.startTimer:close()
			_G.lspTimeOutState.startTimer = nil
		end

		-- LuaFormatter on
		local napi = require("lsp-timeout.nvim-api")
		local clientsRunning = napi.Lsp.Clients:new(napi.tabs.current.lsp:clients())
		_G.lspTimeOutState.b[auEvent.buf] = {}
		_G.lspTimeOutState.b[auEvent.buf].stopped_clients = clientsRunning
		local clientsNum = #clientsRunning
		local tabPageWindows = vim.api.nvim_tabpage_list_wins(0)
		-- LuaFormatter off

		if not _G.lspTimeOutState.stopTimer and clientsNum > 0 then
			local ok, configModule = pcall(require, "lsp-timeout.config")
			if not ok or not configModule or not configModule.default then
				vim.notify("lsp-timeout: Could not load config default!", vim.log.levels.ERROR)
				return
			end
			local config = configModule.default:extend(
				vim.b[auEvent.buf].lspTimeoutConfig or vim.g["lsp-timeout-config"] or vim.g.lspTimeoutConfig or {}
			)
			if vim.tbl_contains(config.filetypes.ignore, vim.bo[auEvent.buf].filetype) then
				return
			end
			local timeout = config.stopTimeout

			_G.lspTimeOutState.stopTimer = uv.new_timer()
			_G.lspTimeOutState.stopTimer:start(
				timeout,
				0,
				vim.schedule_wrap(function()
					-- Stop all clients
					clientsRunning:stop(true)
					for i, clientRunning in ipairs(clientsRunning) do
						vim.lsp.buf_detach_client(auEvent.buf, clientRunning.id)
					end
					if not config.silent then
						-- LuaFormatter off
						local messageOnWindows = #tabPageWindows > 1
								and (" in current tab windows"):format(#tabPageWindows)
							or ""
						vim.notify(
							("lsp-timeout.nvim: nvim has lost focus, stop %s language servers%s"):format(
								clientsNum,
								messageOnWindows
							),
							vim.log.levels.INFO
						)
						-- LuaFormatter on
					end
					_G.lspTimeOutState.stopTimer = nil
				end)
			)
		end
	end,
})
