-- Executor-friendly remote loader (main.luau)
-- Place your raw script URL in `url` or paste code into `inline_payload`.
-- Designed to work with many Roblox executors (syn, request, http_request, game:HttpGet, HttpService).

local url = "https://raw.githubusercontent.com/USER/REPO/BRANCH/path/to/script.lua" -- REPLACE with raw script URL
local inline_payload = nil -- or place your Lua code here as a string to run without HTTP

local function try_call(fn, ...)
    local ok, res = pcall(fn, ...)
    if ok then return res end
    return nil, res
end

local function http_get(u)
    -- syn.request (returns table with Body)
    if typeof and typeof(syn) ~= "nil" and syn.request then
        local ok, res = try_call(syn.request, {Url = u, Method = "GET"})
        if ok and type(res) == "table" and res.Body then return res.Body end
    end

    -- request / http_request (some executors)
    local reqfn = request or http_request or http and http.request
    if reqfn then
        local ok, res = try_call(reqfn, {Url = u, Method = "GET"})
        -- some request implementations return string, some return table
        if ok then
            if type(res) == "table" and res.Body then return res.Body end
            if type(res) == "string" then return res end
        end
    end

    -- game:HttpGet
    if game and game.HttpGet then
        local ok, res = try_call(function() return game:HttpGet(u) end)
        if ok and type(res) == "string" then return res end
    end

    -- HttpService:GetAsync
    local ok, HttpService = pcall(function() return game:GetService("HttpService") end)
    if ok and HttpService and HttpService.GetAsync then
        local got, res = try_call(function() return HttpService:GetAsync(u) end)
        if got then return res end
    end

    return nil, "no http method available or all requests failed"
end

local function run_code(code)
    if not code or type(code) ~= "string" or #code == 0 then
        return false, "no code to run"
    end

    -- prefer loadstring when available (many executors provide it)
    local loader = loadstring or load
    if not loader then
        return false, "no loadstring/load function available"
    end

    local fn, err = loader(code)
    if not fn then
        return false, ("compile error: " .. tostring(err))
    end

    local ok, ret = pcall(fn)
    if not ok then
        return false, ("runtime error: " .. tostring(ret))
    end

    return true, ret
end

local function main()
    local code

    if inline_payload and type(inline_payload) == "string" and #inline_payload > 0 then
        code = inline_payload
    elseif url and type(url) == "string" and #url > 0 then
        local res, err = http_get(url)
        if not res then
            warn("Failed to fetch remote script:", err)
            return
        end
        code = res
    else
        warn("No inline payload or url provided. Set `url` or `inline_payload` in the file.")
        return
    end

    local ok, result = run_code(code)
    if not ok then
        warn("Script execution failed:", result)
    else
        print("Script executed successfully")
    end
end

-- Run safely
pcall(main)
