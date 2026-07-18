-- Tests for the FocusGained/FocusLost autocmd handlers in plugin/lsp-timeout.lua.
--
-- These handlers depend on real LSP clients and vim.uv timers, which aren't
-- practical to exercise end-to-end across the v0.7.2-nightly compat range.
-- Instead: the real autocmds are loaded and fired for real (via
-- nvim_exec_autocmds), real uv timers are used with a tiny timeout (polled
-- via vim.wait), and only the LSP-client boundary (lsp-timeout.nvim-api's
-- client lookups, plus vim.lsp.start) is stubbed with fake client tables.
local spy = require("luassert.spy")

local function fakeClient(name, extra)
	return vim.tbl_extend("force", {
		id = math.random(1000, 999999),
		name = name,
		stop = function(_) end,
		launch = function() end,
		config = {},
		rpc = { terminate = function() end },
	}, extra or {})
end

describe("lsp-timeout plugin autocmds", function()
	local napi
	local origLspClients, origTabClients, origLspStart
	local bufnr

	before_each(function()
		_G.lspTimeOutState = { b = {} }
		vim.g.lspTimeoutConfig = nil
		vim.g["lsp-timeout-config"] = nil

		-- (re)register the augroups/autocmds/commands; safe to re-run since
		-- augroups are created with { clear = true }
		dofile("plugin/lsp-timeout.lua")

		-- bypass VimEnter's real lspconfig/vim.lsp.enable detection entirely
		_G.lspTimeOutState.getConfigsByFt = function()
			return {}
		end

		napi = require("lsp-timeout.nvim-api")
		origLspClients = napi.Lsp.clients
		origTabClients = napi.tabs.current.lsp.clients
		origLspStart = vim.lsp.start

		bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(bufnr)
	end)

	after_each(function()
		napi.Lsp.clients = origLspClients
		napi.tabs.current.lsp.clients = origTabClients
		vim.lsp.start = origLspStart
		if vim.api.nvim_buf_is_valid(bufnr) then
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end
	end)

	describe("FocusLost", function()
		it("does not arm stopTimer when no clients are running", function()
			napi.tabs.current.lsp.clients = function()
				return {}
			end
			napi.Lsp.clients = function(_, _)
				return {}
			end

			vim.g.lspTimeoutConfig = { stopTimeout = 5, silent = true }
			vim.api.nvim_exec_autocmds("FocusLost", { buffer = bufnr })

			assert.is_nil(_G.lspTimeOutState.stopTimer)
		end)

		it("records per-buffer stopped_clients, then stops and detaches them once stopTimeout elapses", function()
			local client = fakeClient("fake-ls")
			local stopSpy = spy.new(function(_) end)
			client.stop = stopSpy

			napi.tabs.current.lsp.clients = function()
				return { client }
			end
			napi.Lsp.clients = function(_, _)
				return { client }
			end

			local detachSpy = spy.new(function(_, _) end)
			local origDetach = vim.lsp.buf_detach_client
			vim.lsp.buf_detach_client = detachSpy

			vim.g.lspTimeoutConfig = { stopTimeout = 5, silent = true }
			vim.api.nvim_exec_autocmds("FocusLost", { buffer = bufnr })

			assert.is_not_nil(_G.lspTimeOutState.stopTimer)
			assert.are.same({ client }, _G.lspTimeOutState.b[bufnr].stopped_clients)

			vim.wait(1000, function()
				return _G.lspTimeOutState.stopTimer == nil
			end)

			assert.spy(stopSpy).was_called_with(true)
			assert.spy(detachSpy).was_called_with(bufnr, client.id)
			assert.is_nil(_G.lspTimeOutState.stopTimer)

			vim.lsp.buf_detach_client = origDetach
		end)

		it("does not arm stopTimer for an ignored filetype", function()
			vim.bo[bufnr].filetype = "fakeft"
			local client = fakeClient("fake-ls")
			napi.tabs.current.lsp.clients = function()
				return { client }
			end
			napi.Lsp.clients = function(_, _)
				return { client }
			end

			vim.g.lspTimeoutConfig = { stopTimeout = 5, silent = true, filetypes = { ignore = { "fakeft" } } }
			vim.api.nvim_exec_autocmds("FocusLost", { buffer = bufnr })

			assert.is_nil(_G.lspTimeOutState.stopTimer)
		end)

		it("is a no-op while paused", function()
			_G.lspTimeOutState.paused = true
			local client = fakeClient("fake-ls")
			napi.tabs.current.lsp.clients = function()
				return { client }
			end
			napi.Lsp.clients = function(_, _)
				return { client }
			end

			vim.g.lspTimeoutConfig = { stopTimeout = 5, silent = true }
			vim.api.nvim_exec_autocmds("FocusLost", { buffer = bufnr })

			assert.is_nil(_G.lspTimeOutState.stopTimer)
			assert.is_nil(_G.lspTimeOutState.b[bufnr])
		end)
	end)

	describe("FocusGained", function()
		it("relaunches a matched stopped client, starts an unmatched one, and clears a pending stopTimer", function()
			local launchSpy = spy.new(function() end)
			local matchedConfig = { name = "match-ls", launch = launchSpy, config = {} }
			local stoppedMatched = fakeClient("match-ls")
			local stoppedUnmatched = fakeClient("other-ls", { config = { name = "other-ls-cfg" } })

			_G.lspTimeOutState.b[bufnr] = { stopped_clients = { stoppedMatched, stoppedUnmatched } }
			_G.lspTimeOutState.getConfigsByFt = function()
				return { matchedConfig }
			end
			napi.Lsp.clients = function(_, _)
				return {}
			end

			local uv = vim.uv or vim.loop
			local staleStopTimer = uv.new_timer()
			staleStopTimer:start(60000, 0, function() end)
			_G.lspTimeOutState.stopTimer = staleStopTimer

			local startSpy = spy.new(function(_) end)
			vim.lsp.start = startSpy

			vim.g.lspTimeoutConfig = { startTimeout = 5, silent = true }
			vim.api.nvim_exec_autocmds("FocusGained", { buffer = bufnr })

			-- the pending stopTimer is cleared synchronously, before the new
			-- startTimer is even armed
			assert.is_nil(_G.lspTimeOutState.stopTimer)
			assert.is_not_nil(_G.lspTimeOutState.startTimer)

			vim.wait(1000, function()
				return _G.lspTimeOutState.startTimer == nil
			end)

			assert.spy(launchSpy).was_called(1)
			assert.spy(startSpy).was_called_with(stoppedUnmatched.config)
			assert.are.same({}, _G.lspTimeOutState.b[bufnr].stopped_clients)
		end)

		it("does not arm startTimer when enough clients are already running", function()
			local availableConfig = { name = "fake-ls", launch = function() end, config = {} }
			_G.lspTimeOutState.getConfigsByFt = function()
				return { availableConfig }
			end
			napi.Lsp.clients = function(_, _)
				return { fakeClient("fake-ls") }
			end

			vim.g.lspTimeoutConfig = { startTimeout = 5, silent = true }
			vim.api.nvim_exec_autocmds("FocusGained", { buffer = bufnr })

			assert.is_nil(_G.lspTimeOutState.startTimer)
		end)

		it("is a no-op while paused", function()
			_G.lspTimeOutState.paused = true
			_G.lspTimeOutState.getConfigsByFt = function()
				return { { name = "fake-ls", launch = function() end, config = {} } }
			end

			vim.g.lspTimeoutConfig = { startTimeout = 5, silent = true }
			vim.api.nvim_exec_autocmds("FocusGained", { buffer = bufnr })

			assert.is_nil(_G.lspTimeOutState.startTimer)
		end)
	end)
end)
