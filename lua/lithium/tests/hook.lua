require("lithium")

local name = "lithium_hook_selftest"

local GM = {}

local function RunTest()
	hook.GetLithiumTable()[name] = nil
	do
		local ret = 0
		lithium.log("[HOOK] [SELFTEST] Basic hook test running")

		GM[name] = function(_, ret_) return ret_ end
		local ran = false
		hook.Add(name, "1", function()
			ran = true
		end)

		ret = hook.Call(name, GM, 1)

		assert(ran == true, "hook.Call didn't run the hook")
		assert(ret == 1, "hook.Call didn't run the gamemode function or returned the wrong value")
		lithium.log("[HOOK] [SELFTEST] Basic hook test OK")
	end

	do
		lithium.log("[HOOK] [SELFTEST] hook.GetTable compatibility shape test running")
		local event = name .. "_gettable"
		hook.Add(event, "tableShape", function() end)
		local tbl = hook.GetTable()
		assert(type(tbl) == "table", "hook.GetTable should return a table")
		assert(type(tbl[event]) == "table", "hook.GetTable should contain event table")
		assert(type(tbl[event]["tableShape"]) == "function", "hook.GetTable should map id -> function")
		hook.Remove(event, "tableShape")
		lithium.log("[HOOK] [SELFTEST] hook.GetTable compatibility shape test OK")
	end

	do
		lithium.log("[HOOK] [SELFTEST] Hook order test running")
		local order = {}
		for i = 1, 3 do
			hook.Add(name, tostring(i), function() table.insert(order, tostring(i)) end, HOOK_NORMAL)
		end
		hook.Call(name, {})

		assert(table.concat(order) == "123", "Hooks with the same priority did not execute in order of addition (got "..table.concat(order)..")")
		lithium.log("[HOOK] [SELFTEST] Hook order test OK")
	end

	do
		lithium.log("[HOOK] [SELFTEST] Hook removal test running")
		local executed = {}
		hook.Add(name, "1", function() table.insert(executed, "hook1") end)
		hook.Add(name, "2", function() table.insert(executed, "hook2") end)
		hook.Add(name, "3", function() table.insert(executed, "hook3") end)

		hook.Remove(name, "1")
		hook.Call(name, {})

		assert(not table.HasValue(executed, "hook1"), "Removed hook should not execute")
		lithium.log("[HOOK] [SELFTEST] Hook removal test OK")
		hook.Remove(name, "2")
		hook.Remove(name, "3")
	end

	do
		lithium.log("[HOOK] [SELFTEST] Hook replace test running")
		local executed = false
		hook.Add(name, "hook", function() executed = true end)
		hook.Add(name, "hook", function() executed = false end)

		hook.Call(name, {})

		assert(executed == false, "Hook should have its functionality replaced")
		lithium.log("[HOOK] [SELFTEST] Hook replace test OK")
		hook.Remove(name, "hook")
	end

	do
		lithium.log("[HOOK] [SELFTEST] Complex hook chain test running")
		local order = {}
		for i = 1, 5 do
			hook.Add(name, "hook" .. tostring(i), function() table.insert(order, "hook" .. tostring(i)) end)
		end

		hook.Call(name, {})

		assert(table.concat(order) == "hook1hook2hook3hook4hook5", "Complex chain of hooks did not execute correctly")
		lithium.log("[HOOK] [SELFTEST] Complex hook chain test OK")
		for i = 1, 5 do hook.Remove(name, "hook" .. tostring(i)) end
	end

	do
		lithium.log("[HOOK] [SELFTEST] Concurrent hook add/remove in call test running")
		local function dynamic_hook() hook.Remove(name, "dynamic") end
		hook.Add(name, "static", function() hook.Add(name, "dynamic", dynamic_hook) end)

		hook.Call(name, {})

		assert(pcall(hook.Call, name, {}), "Should be stable after concurrent add/remove during call")
		lithium.log("[HOOK] [SELFTEST] Concurrent hook add/remove in call OK")
		hook.Remove(name, "static")
	end

	do
		lithium.log("[HOOK] [SELFTEST] Nested hook call test running")
		local nested_called = false
		hook.Add(name, "outer", function() hook.Call("nested", {}) end)
		hook.Add("nested", "inner", function() nested_called = true end)

		hook.Call(name, {})

		assert(nested_called, "Nested hook calls should be handled correctly")
		lithium.log("[HOOK] [SELFTEST] Nested hook call test OK")
		hook.Remove(name, "outer")
		hook.Remove("nested", "inner")
	end

	do
		lithium.log("[HOOK] [SELFTEST] Nested remove/replace test running")
		local event = name .. "_nested_mut"
		local sequence = {}
		hook.Add(event, "first", function()
			table.insert(sequence, "first")
			hook.Remove(event, "second")
			hook.Add(event, "third", function() table.insert(sequence, "third") end)
		end)
		hook.Add(event, "second", function() table.insert(sequence, "second") end)

		hook.Call(event, {})
		assert(table.concat(sequence, ",") == "first", "second should be removed during iteration and third should not run in same pass")
		sequence = {}
		hook.Call(event, {})
		assert(table.concat(sequence, ",") == "first,third", "new hook should run on following call")
		hook.Remove(event, "first")
		hook.Remove(event, "second")
		hook.Remove(event, "third")
		lithium.log("[HOOK] [SELFTEST] Nested remove/replace test OK")
	end

	do
		lithium.log("[HOOK] [SELFTEST] Hook with varargs test running")
		local args_received = false
		hook.Add(name, "varargs", function(...) args_received = {...} end)

		hook.Call(name, {}, 1, 2, 3)

		assert(args_received and #args_received == 3 and args_received[1] == 1 and args_received[2] == 2 and args_received[3] == 3, "Hooks should handle variable arguments correctly")

		lithium.log("[HOOK] [SELFTEST] Hook with varargs test OK")
		hook.Remove(name, "varargs")
	end

	do
		lithium.log("[HOOK] [SELFTEST] Diagnostics source aggregation test running")
		if hook.ResetLithiumDiagnostics and hook.GetLithiumDiagnostics then
			hook.ResetLithiumDiagnostics()
			local event = name .. "_diag_source"
			hook.Add(event, "diag", function() return nil end)
			hook.Call(event, {})
			local diag = hook.GetLithiumDiagnostics()
			assert(type(diag.by_source) == "table", "diagnostics should expose by_source table")
			hook.Remove(event, "diag")
		end
		lithium.log("[HOOK] [SELFTEST] Diagnostics source aggregation test OK")
	end

	do
		lithium.log("[HOOK] [SELFTEST] Gamemode hook test running")
		GM[name] = function() return "gm_called" end

		local ret = hook.Call(name, GM)

		assert(ret == "gm_called", "The gamemode function should run and return its value when no hooks are present")
		lithium.log("[HOOK] [SELFTEST] Gamemode hook test OK")
	end

	do
		lithium.log("[HOOK] [SELFTEST] High priority hook running before GM test running")
		GM[name] = function() return "gm_not_called" end
		local returnValue = nil
		hook.Add(name, "PreHookReturn", function() return "pre_returned" end, HOOK_HIGH)

		returnValue = hook.Call(name, GM)

		assert(returnValue == "pre_returned", "High priority hook with return should stop execution and return its value")
		lithium.log("[HOOK] [SELFTEST] High priority hook running before GM test OK")
		hook.Remove(name, "PreHookReturn")
	end

	do
		lithium.log("[HOOK] [SELFTEST] Different priority hooks run test running")
		local normal_hook_ran = false
		local post_hook_ran = false
		hook.Add(name, "normalhook", function() normal_hook_ran = true end, HOOK_NORMAL)
		hook.Add(name, "posthook", function() post_hook_ran = true end, HOOK_LOW)

		hook.Call(name, {})

		assert(normal_hook_ran and post_hook_ran, "Both normal and low hooks should run")
		lithium.log("[HOOK] [SELFTEST] Different priority hooks run test OK")
		hook.Remove(name, "normalhook")
		hook.Remove(name, "posthook")
	end

	do
		lithium.log("[HOOK] [SELFTEST] Removing hook in call test running")
		local hookran = false
		local function removing_hook() hook.Remove(name, "dynamicHook") end
		hook.Add(name, "removing_hook", removing_hook, HOOK_HIGH)
		hook.Add(name, "dynamicHook", function() hookran = true end, HOOK_NORMAL)

		hook.Call(name, {})

		assert(not hookran, "Hook should not run after being removed")
		lithium.log("[HOOK] [SELFTEST] Removing hook in call test OK")
		hook.Remove(name, "removing_hook")
		hook.Remove(name, "dynamicHook")
	end

	do
		lithium.log("[HOOK] [SELFTEST] GMod wrong behaviour replication test running")
		local a, b, c
		hook.Add(name, "a", function()
			a = true
			hook.Add(name, "c", function()
				c = true
			end)
		end)
		hook.Add(name, "b", function()
			b = true
		end)

		hook.Call(name)
		assert(a == true and b == true and c == nil, "something is wrong, called: a: " .. tostring(a) .. " b: " .. tostring(b) .. " c: " .. tostring(c))
		a, b, c = nil, nil, nil
		hook.Call(name)
		assert(a == true and b == true and c == true, "something is wrong, called: a: " .. tostring(a) .. " b: " .. tostring(b) .. " c: " .. tostring(c))
		lithium.log("[HOOK] [SELFTEST] GMod wrong behaviour replication test OK")
		hook.Remove(name, "a")
		hook.Remove(name, "b")
		hook.Remove(name, "c")
	end

	do
		lithium.log("[HOOK] [SELFTEST] IsValid-able as hook name test running")
		local entity = {
			IsValid = function()
				return true
			end
		}

		hook.Add(name, entity, function()
			return true
		end)

		assert(hook.Call(name, nil, 1) == true, "hook.Call didn't run the hook or returned the wrong value")

		lithium.log("[HOOK] [SELFTEST] IsValid-able as hook name test OK")
		hook.Remove(name, entity)
	end

	do
		lithium.log("[HOOK] [SELFTEST] Mixed invalid/valid hook ID test running")
		local event = name .. "_mixed_ids"
		hook.Add(event, "string_ok", function() return "ok" end)
		local invalid_numeric = hook.Add(event, 123, function() end)
		assert(invalid_numeric == nil, "numeric hook id should not be accepted")
		assert(hook.GetTable()[event]["string_ok"] ~= nil, "valid hook id should still exist")
		hook.Remove(event, "string_ok")
		lithium.log("[HOOK] [SELFTEST] Mixed invalid/valid hook ID test OK")
	end

	do
		lithium.log("[HOOK] [SELFTEST] IsValid-able turning invalid as hook name test running")
		local called = 0
		local entity = {
			IsValid = function()
				called = called + 1
				if called <= 2 then
					return true
				end
				return false
			end
		}

		hook.Add(name, entity, function()
			return true
		end)

		assert(hook.Call(name, nil, 1) == true, "hook.Call didn't run the hook or returned the wrong value")
		assert(hook.Call(name, nil, 1) == nil, "hook.Call entity was called even though it became invalid")

		lithium.log("[HOOK] [SELFTEST] IsValid-able turning invalid as hook name test OK")
	end

	do
		lithium.log("[HOOK] [SELFTEST] Dispatcher fallback migration test running")
		local cv = GetConVar and GetConVar("lithium_hook_selftest_allow_fallback") or nil
		if not (cv and cv:GetBool()) then
			lithium.log("[HOOK] [SELFTEST] Dispatcher fallback migration test skipped (set lithium_hook_selftest_allow_fallback 1 to enable)")
		elseif not (lithium.hook_dispatcher and lithium.hook_dispatcher.fallback_to_legacy) then
			lithium.log("[HOOK] [SELFTEST] Dispatcher fallback migration test skipped (dispatcher unavailable)")
		else
			local event = name .. "_fallback_migration"
			local order = {}

			hook.Add(event, "A", function() table.insert(order, "A") end)
			hook.Add(event, "B", function() table.insert(order, "B") end)

			local switched = lithium.hook_dispatcher.fallback_to_legacy("selftest migration", { event = event })
			assert(switched == true or switched == false, "fallback_to_legacy should return a boolean")

			hook.Call(event, {})
			assert(table.concat(order, ",") == "A,B", "Migrated hooks should preserve order and execute")

			hook.Add(event, "B", function() table.insert(order, "B2") end)
			hook.Add(event, "C", function() table.insert(order, "C") end)
			hook.Call(event, {})
			assert(order[#order - 2] == "A" and order[#order - 1] == "B2" and order[#order] == "C", "Post-fallback replacement/add should remain sane")

			local tbl = hook.GetTable()
			assert(type(tbl[event]) == "table" and type(tbl[event]["A"]) == "function" and type(tbl[event]["B"]) == "function", "GetTable shape should remain valid after fallback")

			local before = lithium.hook_dispatcher.get_stats and lithium.hook_dispatcher.get_stats().fallback_count or 0
			local switched_again = lithium.hook_dispatcher.fallback_to_legacy("selftest repeated", { event = event })
			local after = lithium.hook_dispatcher.get_stats and lithium.hook_dispatcher.get_stats().fallback_count or before
			assert(switched_again == false, "Repeated fallback attempt should be ignored once legacy is active")
			assert(after == before, "Repeated fallback should not mutate fallback counters")

			hook.Remove(event, "A")
			hook.Remove(event, "B")
			hook.Remove(event, "C")
			lithium.log("[HOOK] [SELFTEST] Dispatcher fallback migration test OK")
		end
	end
end

local success, error_msg = pcall(RunTest)
if not success then
	lithium.warn(error_msg)
	PrintTable(hook.GetLithiumTable()[name] or {})
end
return success
