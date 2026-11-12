--[[
    * sub-translate-AI.lua
    *
    * AUTHORS: dyphire (original: sub-fastwhisper.lua)
    * License: MIT
    * link: https://github.com/dyphire/mpv-sub-fastwhisper
    *
    * The faster-whisper transcription part has been stripped. This script only
    * translates the current external .srt subtitle through an OpenAI-compatible
    * API and builds a bilingual .ass file.
    * Usage: script-message-to sub_translate_AI translate
]]

local msg = require 'mp.msg'
local utils = require 'mp.utils'
local options = require "mp.options"

---- Script Options ----
local o = {
    ---- GPT API Options ----
    -- Compatible with other AI API with the same structure as the GPT API
    api_url = "https://api.openai.com/v1/chat/completions",
    api_key = "",
    api_mode = "gpt-4o",
    -- 采样温度。翻译不需要创造性：低温更稳、废话 token 更少。
    -- 重试时脚本会自动再降到 0.2。
    api_temperature = 0.3,
    -- Give up on a single request after this many seconds. Without it a stuck
    -- server would keep the translation hanging forever.
    api_timeout = 120,
    -- Rate per minute used by the API
    -- See the corresponding API documentation for instructions
    api_rate = 15,
    -- How many subtitle entries are packed into a single request.
    -- Bigger batches mean fewer round trips and less repeated prompt overhead,
    -- so they are usually faster overall. Lower it if the model starts dropping
    -- or merging lines (watch for "Mismatch" warnings in the console).
    -- Rejected batches are automatically re-queued at half the size, so a
    -- size the model cannot handle costs one failed request, not the file.
    batch_size = 30,
    -- When following playback, the handful of lines actually on screen are
    -- peeled off into a tiny request of this many lines, so the text you are
    -- waiting for comes back in a second or two instead of after a whole
    -- batch. 2 = 当前行 + 下一行：请求越小首显越快（单行生成 ~1s）。
    -- 0 disables the split.
    hot_lines = 2,
    -- How many requests may be in flight at the same time.
    -- Mind the product batch_size * max_parallel: the server has to keep every
    -- in-flight request in its context at once, and overflowing it makes the
    -- requests fail outright (LM Studio: "Context size has been exceeded").
    -- Measured safe point on a ~8k token context: 30 * 4 = 120 lines.
    max_parallel = 4,
    -- How many of the preceding lines are prepended to each request as
    -- context. This is what keeps names, honorifics and tone consistent across
    -- batch boundaries. 2~4 works well; 0 turns it off.
    context_lines = 3,
    -- Translation target language
    translate = "Chinese",
    -- Clean up what a translated line ends with: the model adds a full stop to
    -- nearly every line whether the prompt forbids it or not, and sometimes
    -- trails off into a comma, a colon or a semicolon. Those are stripped;
    -- "..." / "…" / "!" / "?" / "~" are kept, they carry meaning.
    strip_trailing_punctuation = true,
    -- Optional anchor words for the erotic register, in the translation
    -- target language (e.g. Chinese: 小穴). Empty keeps the generic
    -- word-selection rule only. The hint is injected ONLY as a positive
    -- preference for explicit sexual lines; medical or non-sexual lines are
    -- told to keep normal correct terminology, so legitimate anatomical
    -- words in documentaries or medical dramas are unaffected.
    explicit_vocab_hint = "",
    -- Follow the playback position: translate the part you are watching first,
    -- so subtitles show up where you are actually looking instead of strictly
    -- from the beginning of the file
    follow_playback = true,
    -- Seconds between two refreshes of the bilingual .ass while translating.
    -- Every refresh rewrites the file and makes mpv reload the subtitle
    -- track, so batches finishing close together share one refresh. Raising
    -- it only changes how often the file is rewritten, never its content.
    -- A batch that covers the position currently on screen always refreshes
    -- immediately, whatever this is set to.
    refresh_interval = 0.5,
    -- Specify the font to be used for the generated ass captions
    font_name = "sans-serif",
    -- Font size (in the 1920x1080 script coordinate space) of the translated
    -- line -- the one you actually read
    font_size = 70,
    -- Font size of the original line underneath it
    orig_font_size = 46,
    -- Colour of the original line, as plain RGB hex like in a CSS stylesheet
    -- (ASS itself stores colours as BGR, this option takes normal RGB and
    -- converts it). The default reproduces the look inherited from upstream,
    -- which is an amber tone rather than the blue it looks like at a glance.
    orig_color = "EBA862",
    -- Transparency of the original line, 0 = fully opaque, 255 = invisible
    orig_alpha = 0,
    -- Distance from the bottom edge, so a two line block is not glued to it
    margin_v = 40,
}

options.read_options(o)
------------------------

-- Trim leading/trailing blanks. Spelled out once: it used to be inlined as
-- gsub pairs at half a dozen call sites.
local function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- Plain "RRGGBB" (+ alpha) to the "&HAABBGGRR" spelling ASS expects
local function rgb_to_ass(hex, alpha)
    hex = tostring(hex or ""):gsub("^#", ""):gsub("^&H", ""):gsub("&$", "")
    if not hex:match("^%x%x%x%x%x%x$") then hex = "62A8EB" end
    local r, g, b = hex:sub(1, 2), hex:sub(3, 4), hex:sub(5, 6)
    local a = math.max(0, math.min(255, math.floor(tonumber(alpha) or 0)))
    return string.format("&H%02X%s%s%s", a, b:upper(), g:upper(), r:upper())
end

local function clamp_int(value, default, low)
    return math.max(low, math.floor(tonumber(value) or default))
end

local font_size = clamp_int(o.font_size, 70, 10)
local orig_font_size = clamp_int(o.orig_font_size, 46, 8)
local margin_v = clamp_int(o.margin_v, 40, 0)
local hot_lines = clamp_int(o.hot_lines, 5, 0)
local orig_colour = rgb_to_ass(o.orig_color, o.orig_alpha)
-- Content of the last .ass written per file, used to skip no-op reloads
local last_ass_content = {}
-- Parsed original subtitles, keyed by file name. The source file never changes
-- during a translation, so it is parsed once instead of on every refresh.
local originals_cache = {}

local pending_queue = {}
local pump_scheduled = false
local in_progress_batches = 0
local progress_cache = {}
local translated_cache = {}
-- Content-level dedup: the same source line repeated elsewhere in the file
-- (choruses, catchphrases) reuses the first translation instead of costing
-- another request.
local content_cache = {}
-- Guards against a second trigger while a translation is still running (the
-- queue would be rebuilt and every line requested twice)
local translating = false
-- Cancel handles of the requests currently in flight, aborted when a file is
-- unloaded so a late callback cannot touch a new file's state
local active_cancels = {}
-- Bumped on every unload. Callbacks and timers scheduled by a translation must
-- not touch the state of the run that comes after them: an aborted request
-- would otherwise revive the old run, keep translating the old file and add
-- its .ass to whatever is loaded next.
local run_epoch = 0
-- Set by translate_and_write while a run is active: re-sorts the pending
-- queue around the new playback position and pumps. Cleared on unload.
local seek_pump = nil
local function is_protocol(path)
    return type(path) == 'string' and (path:find('^%a[%w.+-]-://') ~= nil or path:find('^%a[%w.+-]-:%?') ~= nil)
end

-- Drop ASS override tags and HTML tags: they carry no meaning for a
-- translation and the model may start imitating them.
local function strip_tags(text)
    return (text or ""):gsub("{[^{}]-}", ""):gsub("<[^<>]-", "")
end

-- Lines that carry nothing to translate: music notes, ellipsis, bare numbers.
local function is_noop_text(text)
    local stripped = strip_tags(text):gsub("[%s%p]", ""):gsub("[%d]", "")
    return stripped == ""
end

-- Does the text contain CJK characters? Used to tell "already translated"
-- (identical output is fine) from "the model just echoed the input".
local function has_cjk(text)
    return text:find("[\228-\233][\128-\191]") ~= nil
end

-- Recognise "1 |", "1.", "1)", "[1]", "1:", "1、" and the fullwidth bar.
local function line_number(line)
    return line:match("^%s*%[%s*(%d+)%s*%]%s*[|｜]%s*")
        or line:match("^%s*(%d+)%s*[|｜]%s*")
        or line:match("^%s*%[?%s*(%d+)%s*%]?%s*[%.%)%:、]%s+")
end

-- Reduce one line of model output to "<number>", "<translated text>"
local function sanitize_output_line(line)
    local s = trim(line or "")
    s = s:gsub("^[-*>#%s]+", ""):gsub("^[\"'`]+", "")
    local num = line_number(s)
    if not num then return nil, nil end

    local text = s
    local bar = text:find("[|｜]")
    if bar then
        text = text:sub(bar + 1)
    else
        text = text:gsub("^%s*%[%s*%d+%s*%]%s*[%.%)%:、]%s*", "")
    end
    text = trim(text)

    -- "1 | 1 | text" -- some models repeat the number; strip it once more
    local inner = text:match("^%s*%[?%s*(%d+)%s*%]?%s*[|｜]%s*(.+)$")
    if inner == num then
        text = trim(text:gsub("^%s*%[?%s*%d+%s*%]?%s*[|｜]%s*", ""))
    end

    if text == "" then return nil, nil end
    return num, text
end

-- Whole-string patterns only: a multibyte character inside a Lua character
-- class [] is treated as its raw bytes, which silently cuts UTF-8 text in
-- half ("。，" matching the 0x80 byte inside "”").
local CLOSING_MARKS = { '%"', "%'", '”', '’', '」', '』',
                        '）', '】', '》', '%)', '%]' }
-- Nothing of these can end a spoken line: a subtitle is cut off by the next
-- cut, so a line that trails off into one of them just looks broken. Both the
-- Chinese and the ASCII spelling are listed.
local TRIM_MARKS    = { '。', '．', '｡', '%.',                  -- .
                        '，', ',', '、',                        -- ,
                        '；', '%;', '：', ':',                  -- ; :
                        '·', '・' }                             -- middot
-- Trailing blanks: the ASCII ones, the CJK full width space and the
-- non-breaking space. Lua's %s only knows the ASCII ones.
local SPACE_MARKS   = { '[ \t]', '　', '\194\160' }
-- ... / ! / ? say something: an unfinished sentence, a shout, a question. A
-- trailing "~" / "～" is a drawn out vowel. Never removed.
local KEPT_MARKS    = { '%.%.%.', '%.%.', '…', '%!', '%?', '！', '？',
                        '~', '～' }

local function ends_with_any(s, marks)
    for _, m in ipairs(marks) do
        if s:find(m .. "[ \t]*$") then return true end
    end
    return false
end

-- Right trim that also knows the CJK full width space and the nbsp
local function rstrip(s)
    local changed = true
    while changed do
        changed = false
        for _, m in ipairs(SPACE_MARKS) do
            local stripped = s:match("^(.-)" .. m .. "$")
            if stripped and stripped ~= "" then
                s, changed = stripped, true
            end
        end
    end
    return s
end

-- Peel the trailing closing marks off so the punctuation hiding behind them
-- can be examined ("他说：“走吧。”" -> "他说：“走吧。", "”"). More than one can
-- stack up ("。”）"), so it keeps peeling until there is none left.
local function split_closing(s)
    local body, closing = s, ""
    local changed = true
    while changed do
        changed = false
        body = rstrip(body)
        for _, m in ipairs(CLOSING_MARKS) do
            local stripped = body:match("^(.-)" .. m .. "$")
            if stripped and stripped ~= "" then
                closing = m:gsub("^%%", "") .. closing
                body, changed = stripped, true
                break
            end
        end
    end
    return body, (closing ~= "" and closing or nil)
end

-- Clean up the punctuation a line ends with. The model ignores the "no full
-- stop" instruction in the prompt (measured on hy-mt2-7b) and ends nearly
-- every line with "。", and it is not unusual for it to trail off into a
-- comma, a colon or a semicolon either -- usually a sign that it merged two
-- source lines. Those are dropped from the end; "..." / "…" / "!" / "?" / "~"
-- are kept, they are part of how the line is spoken.
local function trim_trailing_punctuation(text)
    if not text or o.strip_trailing_punctuation == false then return text end
    local s = rstrip(text)
    if s == "" then return s end

    local body, closing = split_closing(s)

    local changed = true
    while changed do
        changed = false
        body = rstrip(body)
        if body == "" or ends_with_any(body, KEPT_MARKS) then break end
        for _, m in ipairs(TRIM_MARKS) do
            -- Only ASCII blanks here: a multibyte char inside [] would be
            -- split into raw bytes; the CJK space is handled by rstrip().
            local stripped = body:match("^(.-)" .. m .. "[ \t]*$")
            -- Keep a lone "。": blanking the line would lose the subtitle
            if stripped and stripped ~= "" then
                body, changed = stripped, true
                break
            end
        end
    end
    if closing then return body .. closing:gsub("^%%", "") end
    return body
end

local function file_exists(path)
    if path then
        local meta = utils.file_info(path)
        return meta and meta.is_file
    end
    return false
end

-- Punctuation / quote / blank normalisation for the "already translated?"
-- comparison below. File scope, not nested inside is_text_identical: that one
-- runs once per translated line on every .ass refresh, and a closure created
-- per call is pure garbage churn.
local function normalize_text(text)
    text = text:gsub("，", ",")
              :gsub("。", ".")
              :gsub("！", "!")
              :gsub("？", "?")
              :gsub("；", ";")
              :gsub("：", ":")
              :gsub("“", "\"")
              :gsub("”", "\"")
              :gsub("‘", "'")
              :gsub("’", "'")
              :gsub("（", "(")
              :gsub("）", ")")
              :gsub("【", "[")
              :gsub("】", "]")
              :gsub("《", "<")
              :gsub("》", ">")
              :gsub("、", "/")
              :gsub("～", "~")

    text = text:gsub("[%p%s]", "")
    text = text:lower()
    return text
end

local function is_text_identical(text1, text2)
    -- Two cheap rejections before the seventeen gsubs below, which run once per
    -- subtitle on every .ass refresh. The normalisation only touches
    -- punctuation, blanks and case, so a CJK character on one side and none on
    -- the other can never come out equal -- and that is the ordinary "English in
    -- Chinese out" case, normalised for nothing.
    if text1 == text2 then return true end
    if has_cjk(text1) ~= has_cjk(text2) then return false end

    return normalize_text(text1) == normalize_text(text2)
end

local function format_time(time_str)
    local h, m, s, ms = nil, nil, nil, nil
    -- "," is the separator .srt actually uses; without it in this pattern every
    -- comma separated timestamp fell through to the "give up, return as is"
    -- branch below, and a one digit hour reached the .ass unpadded ("0:00:01.00"
    -- for "0:00:01,000").
    if time_str:match("^%d+:%d+:%d+[%.,:]%d+$") then
        h, m, s, ms = time_str:match("(%d+):(%d+):(%d+)[%.,:](%d+)")
    elseif time_str:match("^%d+:%d+[%.,:]%d+$") then
        h = 0
        m, s, ms = time_str:match("(%d+):(%d+)[%.,:](%d+)")
    else
        return time_str
    end

    return string.format("%02d:%02d:%02d,%03d", h, m, s, ms)
end

-- A whole "start --> end" line: one or two digit hours, seconds optional,
-- "," / "." / ":" before the milliseconds, blanks around the arrow optional.
-- Shared by the parser and normalize_timestamp; it used to be spelled
-- out three times, and the copies did not accept the same lines (one copy
-- demanded a blank on each side of the arrow, the others did not).
local TIMESTAMP_LINE = "^%s*(%d+:%d+:?%d*[%.,:]%d+)%s*%-%-%>%s*(%d+:%d+:?%d*[%.,:]%d+)%s*$"

local function timestamp_to_seconds(timestamp)
    local h, m, s, ms = timestamp:match("(%d+):(%d+):(%d+)[,%.](%d+)")
    if not (h and m and s and ms) then return 0 end
    return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s) + tonumber(ms) / 1000
end

-- Bring any "start --> end" string to one canonical form, so that timestamps
-- coming from the original file, from the model output and from the cached
-- .translate.srt all end up using the same key.
local function normalize_timestamp(timestamp)
    if type(timestamp) ~= "string" then return timestamp end
    local start_time, end_time = timestamp:match(TIMESTAMP_LINE)
    if start_time and end_time then
        return format_time(start_time) .. " --> " .. format_time(end_time)
    end
    return timestamp
end

local function get_current_sub()
    local sub = mp.get_property_native("current-tracks/sub")
    if sub then
        if sub.external and not is_protocol(sub["external-filename"])
        and sub["external-filename"]:lower():match("%.srt$") then
            return sub["external-filename"]
        end
    end
    return nil
end

local function check_sub(sub_file)
    local tracks = mp.get_property_native("track-list")
    local _, sub_title = utils.split_path(sub_file)
    for _, track in ipairs(tracks) do
        local external_filename = track["external-filename"]
        local track_title = track["title"]
        if external_filename then
            _, track_title = utils.split_path(external_filename)
        end

        if track["type"] == "sub" and track_title == sub_title then
            return true, track["id"]
        end
    end
    return false, nil
end

-- Track id of the bilingual .ass currently loaded, per file.
local ass_track_id = {}

-- Put a freshly written .ass on screen without dropping the subtitle for a
-- frame. sub-reload tears the track down and builds it again, and the gap in
-- between is exactly what shows up as the subtitle blinking once per refresh.
-- Adding a second track from the same file and removing the old one afterwards
-- reverses the order: mpv has already parsed and selected the new track before
-- the old one goes away, so something is on screen the whole time.
-- (Measured: sub-add returns with the new track already in track-list and
-- selected; sub-remove of the previous id leaves the sid where it is.)
local function norm_path(p)
    if not p then return nil end
    return p:gsub("\\", "/"):lower()
end

-- Which file a track id belongs to. Comparing file names instead of ids
-- matters when the same file is loaded twice: check_sub() only ever returns
-- the first match, which is not necessarily the one on screen.
local function file_of_track(id)
    if not id then return nil end
    for _, track in ipairs(mp.get_property_native("track-list") or {}) do
        if track["type"] == "sub" and track["id"] == id then
            return track["external-filename"]
        end
    end
    return nil
end

local function append_sub(sub_file, source_file)
    local prev_sid = mp.get_property("sid")
    local old_id = ass_track_id[sub_file]
    local prev_file = norm_path(file_of_track(tonumber(prev_sid)))

    mp.commandv("sub-add", sub_file)
    local new_id = mp.get_property_number("sid")
    if not new_id then return end

    -- Keep the new track selected when: nothing was selected before, the
    -- bilingual .ass was already on screen (a refresh), or the track on screen
    -- was the very .srt being translated -- then showing the bilingual result
    -- is what pressing the key was for. Any other track the user picked is
    -- left alone: a plain sub-add would steal the selection from it.
    local keep_new = not prev_sid or prev_sid == "no"
        or tonumber(prev_sid) == new_id
        or tonumber(prev_sid) == old_id
        or (prev_file and prev_file == norm_path(source_file))
    if not keep_new then
        mp.set_property("sid", prev_sid)
    end

    if not old_id then
        ass_track_id[sub_file] = new_id
        msg.debug(string.format("ass track added: id=%s (kept=%s)",
            tostring(new_id), tostring(keep_new)))
        return
    end
    if new_id == old_id then
        -- The add did not produce a second track: keep what is on screen
        return
    end

    mp.commandv("sub-remove", old_id)
    ass_track_id[sub_file] = new_id
    msg.debug(string.format("ass track swapped: %s -> %s (kept=%s)",
        tostring(old_id), tostring(new_id), tostring(keep_new)))
end

-- Add a track only if it is not loaded yet, without touching the selection.
-- Used for the plain translated .srt: it is written to while translating, and
-- reloading it would keep stealing the selection from the bilingual .ass.
local function add_sub_once(sub_file)
    local sub = check_sub(sub_file)
    if not sub then
        mp.commandv('sub-add', sub_file, 'auto')
    end
end

-- Replace a file in one step. mpv reads the .ass while it is being rewritten;
-- a half written file makes the subtitle track come up empty until the next
-- refresh, which looks like the subtitle blinking out for a moment.
local function write_file_atomic(path, content)
    local tmp = path .. ".tmp"
    local file = io.open(tmp, "w")
    if not file then return false end
    file:write(content)
    file:close()
    os.remove(path)
    if os.rename(tmp, path) then return true end
    -- Rename refused (file still open elsewhere): fall back to an in-place
    -- write rather than losing the update.
    file = io.open(path, "w")
    if not file then return false end
    file:write(content)
    file:close()
    return true
end

-- Parse an .srt file into entries: the raw timestamp line (the translation
-- cache key) plus start/end times in the .ass spelling, and the text. One
-- parser serves the source file, the cached .translate.srt and the bilingual
-- .ass generation -- the two parsers that used to share this work disagreed
-- on entries without a trailing blank line, and every fix had to be made
-- twice. Entries without a timestamp are kept but carry nil times; callers
-- that need times must check for them.
local function parse_srt(file_path)
    local file = io.open(file_path, "r")
    if not file then
        msg.error("Unable to open file: " .. file_path)
        return nil
    end

    local subtitles = {}
    local index, timestamp, start_time, end_time, text
    -- One place for "this entry is finished": the blank line after an entry,
    -- the next index line and the end of the file all mean the same thing.
    -- Only the blank line used to be handled, so a file whose last entry has
    -- no trailing blank line lost it.
    local function flush()
        if text then
            table.insert(subtitles, {
                index = index, timestamp = timestamp,
                start_time = start_time, end_time = end_time,
                text = text,
            })
        end
        index, timestamp, start_time, end_time, text = nil, nil, nil, nil, nil
    end

    for line in file:lines() do
        line = line:gsub("[\r\n]+", "")
        local ts_start, ts_end = line:match(TIMESTAMP_LINE)
        if line:match("^%d+$") then
            flush()
            index = tonumber(line)
        elseif ts_start then
            timestamp = line
            -- Normalise to "HH:MM:SS.cc". Check and extraction are the same
            -- pattern now, so a line that passes the check can no longer come
            -- out with a nil field and crash the gsub right after it.
            start_time = format_time(ts_start):gsub(",", "."):sub(1, -2)
            end_time = format_time(ts_end):gsub(",", "."):sub(1, -2)
        elseif line ~= "" then
            text = (text and text .. "\n" or "") .. line
        else
            flush()
        end
    end
    flush()
    file:close()
    return subtitles
end

-- Generating ASS subtitles files
local function generate_ass(subtitles_file)
    local ass_name = string.format(".%s.ass", o.translate)
    local translated_file = subtitles_file:gsub("%.srt$", ".translate.srt")
    local merge_file = subtitles_file:gsub("%.srt$", ass_name)

    if not file_exists(subtitles_file) then return end
    -- The source file never changes during a translation, so parse it once and
    -- keep it: this function runs again on every refresh.
    local originals = originals_cache[subtitles_file]
    if not originals then
        originals = parse_srt(subtitles_file)
        originals_cache[subtitles_file] = originals
    end
    if not originals or #originals == 0 then return end

    -- Index the translated lines by their start time, so that every original
    -- line is always written out (untranslated ones fall back to the original
    -- text) -- otherwise seeking to a part that is not translated yet shows
    -- nothing at all.
    local trans_map = {}
    if next(translated_cache) ~= nil then
        -- Reuse what is already in memory instead of re-reading the file.
        -- translated_cache is keyed by the full "start --> end" line; the ass
        -- writer needs the same key in parse_srt's "HH:MM:SS.cc" spelling.
        -- Keyed by start AND end: two entries of an overlapping dialogue can
        -- share a start time, and a start-only key made them clobber each
        -- other's translation -- which of the two won depended on pairs()
        -- iteration order, i.e. on pure chance.
        for key, text in pairs(translated_cache) do
            if text ~= "" then
                local start_time = key:match("^(%d+:%d+:%d+[,%.]%d+)")
                local end_time = key:match("%-%->%s*(%d+:%d+:%d+[,%.]%d+)")
                if start_time and end_time then
                    start_time = start_time:gsub(",", "."):sub(1, -2)
                    end_time = end_time:gsub(",", "."):sub(1, -2)
                    trans_map[start_time .. " --> " .. end_time] = text
                end
            end
        end
    elseif file_exists(translated_file) then
        local translated = parse_srt(translated_file)
        if translated then
            for _, t in ipairs(translated) do
                if t.text and t.text ~= "" then
                    trans_map[t.start_time .. " --> " .. t.end_time] = trim_trailing_punctuation(t.text)
                end
            end
        end
    end

    local function to_ass_text(s)
        return (s or ""):gsub("\r", ""):gsub("\n", "\\N")
    end
    local function style_line(name, size, colour)
        return string.format("Style: %s,%s,%d,%s,&HF0000000,&H00000000,&H32000000,0,0,0,0,100,100,0,0.00,1,2,1,2,5,5,%d,-1\n",
            name, o.font_name, size, colour, margin_v)
    end

    local out = {}
    out[#out + 1] = "[Script Info]\n"
    out[#out + 1] = "Title: Bilingual Subtitles\n"
    out[#out + 1] = "ScriptType: v4.00+\n"
    out[#out + 1] = "WrapStyle: 0\n"
    out[#out + 1] = "ScaledBorderAndShadow: yes\n"
    out[#out + 1] = "PlayResX: 1920\n"
    out[#out + 1] = "PlayResY: 1080\n"
    out[#out + 1] = "\n"
    out[#out + 1] = "[V4+ Styles]\n"
    out[#out + 1] = "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n"
    out[#out + 1] = style_line("Default", font_size, "&H00FFFFFF")
    -- A named style for the original line: cheaper to render and far easier to
    -- tune than repeating an inline override on all several hundred lines.
    out[#out + 1] = style_line("Original", orig_font_size, orig_colour)
    out[#out + 1] = "\n"
    out[#out + 1] = "[Events]\n"
    out[#out + 1] = "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"

    for _, sub in ipairs(originals) do
        -- Entries without a timestamp cannot be looked up or written
        if sub.start_time and sub.end_time then
            local original_text = to_ass_text(trim(sub.text))

            if original_text ~= "" then
                local translate_text = trans_map[sub.start_time .. " --> " .. sub.end_time]
                translate_text = translate_text and to_ass_text(trim(translate_text)) or ""

                if translate_text == "" or is_text_identical(translate_text, original_text) then
                    -- Not translated yet (or already in the target language): show the original
                    out[#out + 1] = string.format("Dialogue: 0,%s,%s,Default,,0,0,0,,%s\n",
                        sub.start_time, sub.end_time, translate_text ~= "" and translate_text or original_text)
                else
                    out[#out + 1] = string.format("Dialogue: 0,%s,%s,Default,,0,0,0,,%s\\N{\\rOriginal}%s\n",
                        sub.start_time, sub.end_time, translate_text, original_text)
                end
            end
        end
    end

    local content = table.concat(out)
    -- Rewriting an identical file would make mpv reload the subtitle track for
    -- nothing, which shows up as the subtitle blinking once per refresh.
    -- Comparing the two strings is what Lua does natively (a length check plus a
    -- memcmp); hashing the content byte by byte in a Lua loop over a several
    -- hundred kilobyte file costs far more than the comparison it avoids.
    if last_ass_content[merge_file] == content then return end
    last_ass_content[merge_file] = content

    write_file_atomic(merge_file, content)
    -- Pass the .srt being translated so the refresh can tell "the user is
    -- watching the source" (switch to the bilingual result) from "the user
    -- picked some other track" (leave it alone).
    append_sub(merge_file, subtitles_file)
end

-- Sanity check on what the model sent back, before any of it is written to the
-- subtitle file. A small local model will happily drop lines, echo the input or
-- go off on a tangent; catching that here is much better than writing garbage.
-- It is pure (its own arguments plus has_cjk), so it sits at file scope and can
-- be exercised without a running mpv.
local function validate_batch(results, sources)
    if #results < #sources then
        return false, "missing lines"
    end
    -- A model that has fallen into a loop repeats the same line over and over
    -- and gives up varying the rest of the batch, so a repeat only reads as a
    -- loop once it takes up a third of the batch. An absolute count used to
    -- condemn any batch carrying four identical short lines ("Yes.", a name),
    -- which a film reaches easily -- and a condemned batch is retried and, once
    -- the retry passes are used up, reported as permanently untranslated.
    local repeat_cap = math.max(4, math.ceil(#sources / 3))
    local seen, echoed = {}, 0
    for i = 1, #sources do
        local t = results[i]
        if not t or t == "" then
            return false, "empty translation"
        end
        if #t > (#sources[i] * 6) + 60 then
            return false, "runaway output"
        end
        seen[t] = (seen[t] or 0) + 1
        if seen[t] >= repeat_cap then
            return false, "repeated output"
        end
        if t == sources[i] and not has_cjk(sources[i]) then
            echoed = echoed + 1
        end
    end
    if echoed == #sources and #sources > 1 then
        return false, "echoed the input"
    end
    return true
end

-------------Translation function----------------
-- Call the GPT API
local function call_gpt_api(subtitles, callback, temperature)
    msg.info("AI subtitle translation in progress")
    -- Keep the instructions strict: the less the model chats around the actual
    -- translation, the fewer tokens it has to generate, and the faster each
    -- request comes back.
    -- The lines are sent as "<number> | <text>" instead of carrying the full
    -- "HH:MM:SS,mmm --> HH:MM:SS,mmm" timestamp: the timestamp costs about 30
    -- extra tokens per line, once in the prompt and once again in the output.
    -- Dropping it roughly halves the token count (measured: 2.4~3x faster).
    -- Comprehensive prompt, merged from the best rules of all translation
    -- frontends in play (mpv batch protocol + PotPlayer ChatGPT/AI plugins):
    -- spoken-first phrasing, subtitle length, tone and term consistency, no
    -- softening, trailing-punctuation ban, no romanization. Numbered-line
    -- protocol unchanged -- it is what keeps mapping model output back to
    -- entries reliable.
    local prompt = string.format("You are a professional subtitle translator. " ..
    "Translate each line into natural, spoken %s -- the way native speakers actually talk, not a literal rendering. " ..
    "Rules: " ..
    "1. Calibrate intensity to the source: explicit or sexual source lines must be translated with " ..
    "direct, plainly sexual %s vocabulary -- never euphemized, never replaced with vague, clinical " ..
    "or textbook terms, and no cruder than the source. To pick each word, ask which form of the word " ..
    "appears in %s adult-video subtitles: use that one, never the form used in news reports or " ..
    "medical textbooks. If the source is mild or polite, keep the translation equally mild. " ..
    "2. Subtitle style: short enough to read in one glance. " ..
    "3. Preserve the speaker's tone, register, emotion and sentence-final particles; " ..
    "keep honorifics and forms of address consistent. " ..
    "4. Keep character names, place names and recurring terms consistent throughout. " ..
    "5. Never romanize; write %s script directly. " ..
    -- The example must use a concrete number. With the literal placeholder
    -- ("N | text") a small model -- most visibly on a 2~3 line batch, which is
    -- exactly what the hot split produces -- echoes the letter N as-is
    -- ("N | 谢谢您"), every number lookup then fails, the batch falls back to
    -- positional alignment and gets rejected the moment it returns one line
    -- short. Measured: 2 and 3 line batches 0/5 correct with "N", 5/5 with "1".
    "Format: input lines look like \"1 | text\" (a context section may precede them, marked as do-not-translate). " ..
    "Output exactly one line per input line, in order, keeping each \"1 | \" prefix unchanged; " ..
    "translate only the text after it. Never merge, split, renumber or add lines. " ..
    "No explanations, no notes, no blank lines.", o.translate, o.translate, o.translate, o.translate)

    -- The generic register rule stands on its own; the optional hint adds a
    -- scoped positive anchor for explicit lines only, never a global ban.
    if trim(o.explicit_vocab_hint) ~= "" then
        prompt = prompt ..
            " When a source line is itself explicit, prefer wording consistent with the register " ..
            "of this reference list: " ..
            trim(o.explicit_vocab_hint) ..
            ". Natural, fluent variation is welcome -- the list sets the register, it does not " ..
            "restrict word choice. Avoid clinical or textbook terms. Medical, documentary or " ..
            "otherwise non-sexual lines always use normal correct terminology."
    end

    local request_body = {
        messages = {
            {
                role = "system",
                content = prompt
            },
            {
                role = "user",
                content = subtitles
            }
        },
        model = o.api_mode,
        temperature = temperature or o.api_temperature
    }

    local request_json = utils.format_json(request_body)

    local command = {
        "curl", "-s", "-X", "POST", o.api_url,
        "-H", "Content-Type: application/json",
        "-H", "Authorization: Bearer " .. o.api_key,
        "-d", request_json
    }

    if o.api_timeout and o.api_timeout > 0 then
        table.insert(command, "--max-time")
        table.insert(command, tostring(o.api_timeout))
    end

    local abort_signal
    abort_signal = mp.command_native_async({
        name = "subprocess",
        args = command,
        capture_stdout = true,
        capture_stderr = true,
    }, function(success, result, error)
        -- mpv reports a failed or aborted subprocess as success == false with
        -- result == nil. Indexing result here used to throw inside the
        -- callback, which meant callback(nil) never ran: the batch stayed
        -- marked as "in translation" forever, in_progress_batches never came
        -- back down and the run hung below 100% with translating still true.
        if not success or not result or result.status ~= 0 then
            msg.info("API request failed: " .. ((result and result.stderr) or error or "Unknown error"))
            callback(nil)
            return
        end

        local response = utils.parse_json(result.stdout)
        if response and response.choices and #response.choices > 0 then
            callback(response.choices[1].message.content)
        else
            msg.info("Unable to parse API response")
            callback(nil)
        end
    end)

    return function()
        if abort_signal then mp.abort_async_command(abort_signal) end
    end
end

-- Translate subtitles and write to file
local function translate_and_write(subtitles, subtitles_file)
    local batch_size = math.max(1, math.floor(tonumber(o.batch_size) or 20))
    -- Mutable: lowered automatically when the server starts rejecting requests
    local parallel_cap = math.max(1, math.floor(tonumber(o.max_parallel) or 4))
    -- Clamped like the other numbers from the options: api_rate = 0 would make
    -- delay_between_calls infinite and mp.add_timeout() would be handed "inf".
    local max_calls_per_minute = math.max(1, math.floor(tonumber(o.api_rate) or 15))
    local delay_between_calls = 60 / max_calls_per_minute
    local translated_file = subtitles_file:gsub("%.srt$", ".translate.srt")
    local retry_pass = 0
    local failed_batches = 0
    -- Rejection attempts per lone-line batch: halving stops at len==1, so a
    -- single line that keeps getting rejected needs its own retry budget.
    local single_retries = {}
    local finished = false
    -- Hot-batch bookkeeping: start indexes already peeled into a tiny
    -- on-screen request (see pump), reset when the queue is rebuilt.
    local hot_split = {}
    -- Requests currently in flight, keyed by batch start index:
    -- {cancel = abort fn, s = range start (s), e = range end (s)}.
    -- Lets a seek give up a slot that is working on content far away.
    local in_flight = {}
    -- Mutable: retries run cooler, which cuts down on the wild rewordings
    local cur_temperature = o.api_temperature
    local last_pct = 0
    local pump  -- declared here so the async callbacks below can call it
    -- The run this closure belongs to; see run_epoch
    local my_epoch = run_epoch

    -- Drop a batch that failed or did not pass the sanity check: put its
    -- range back into the queue as two halves, so the next attempt runs at
    -- half the size. A model that drops or merges lines at 30 lines per
    -- request usually copes fine with 15 -- and without the split every
    -- full-size retry is a whole batch generation wasted before the lines
    -- get another chance. After two failures in a row back off globally as
    -- well: less parallelism and a lower temperature.
    local function reject_batch(keys, start_index, len)
        for _, k in ipairs(keys) do
            progress_cache[k] = nil
        end
        failed_batches = failed_batches + 1
        if failed_batches >= 2 then
            batch_size = math.max(10, math.floor(batch_size / 2))
            parallel_cap = math.max(1, math.floor(parallel_cap / 2))
            cur_temperature = math.min(cur_temperature, 0.2)
            failed_batches = 0
            msg.info(string.format("Backing off to batch_size=%d, max_parallel=%d, temperature=%.2f",
                batch_size, parallel_cap, cur_temperature))
        end
        if start_index and len and len > 1 then
            local half = math.max(1, math.floor(len / 2))
            table.insert(pending_queue, {i = start_index, n = half})
            table.insert(pending_queue, {i = start_index + half, n = len - half})
        elseif start_index and len and len == 1 then
            -- A lone line used to vanish from this run when rejected. Retry it
            -- a bounded number of times; after that give up gracefully -- the
            -- .ass falls back to the original text for untranslated lines.
            single_retries[start_index] = (single_retries[start_index] or 0) + 1
            if single_retries[start_index] <= 2 then
                table.insert(pending_queue, {i = start_index, n = 1})
            else
                msg.warn(string.format("Line %d still rejected as a single line, leaving it untranslated", start_index))
            end
        end
        in_progress_batches = in_progress_batches - 1
        -- A server that fails instantly (model still loading, bad request)
        -- would otherwise be hammered again within the same tick: give it a
        -- beat to recover.
        mp.add_timeout(1, pump)
    end

    -- Regenerating the whole .ass file after every single batch is wasted work
    -- when batches come back quickly; coalesce the refreshes into one. The
    -- timer waits only the time still left until the next refresh boundary
    -- instead of always a full interval, so a batch landing right after a
    -- flush does not pay the whole interval again.
    local refresh_interval = tonumber(o.refresh_interval) or 0.5
    refresh_interval = math.max(0.1, math.min(5, refresh_interval))
    local ass_dirty = false
    local flush_timer
    local last_flush = 0
    local function flush_ass(file)
        flush_timer = nil
        -- This timer can outlive the file it was started for: writing that
        -- .ass now would re-add its track (append_sub) to whatever file has
        -- been loaded since.
        if my_epoch ~= run_epoch then return end
        last_flush = mp.get_time()
        if ass_dirty then
            ass_dirty = false
            generate_ass(file)
        end
    end
    -- immediate: the batch that just came back covers the position currently
    -- on screen, so the user is waiting on this exact text -- skip the
    -- coalescing wait and rewrite the .ass right away.
    local function request_ass(file, immediate)
        ass_dirty = true
        if immediate then
            if flush_timer then flush_timer:kill() end
            flush_timer = nil
            flush_ass(file)
            return
        end
        if flush_timer then return end
        local remaining = refresh_interval - (mp.get_time() - last_flush)
        flush_timer = mp.add_timeout(math.max(0.05, remaining), function() flush_ass(file) end)
    end

    -- Parsed once per run: the timestamps never change, but sort_queue() asks
    -- for the time range of every pending batch on every pump, and the batch
    -- builder and the missing-lines scan ask for the key of every entry on
    -- every pass -- all of that used to re-parse the timestamp strings.
    local entry_keys = {}
    local entry_times = {}
    for i, s in ipairs(subtitles) do
        local ts = s.timestamp
        entry_keys[i] = ts and normalize_timestamp(ts) or nil
        local st = ts and ts:match("^(%d+:%d+:%d+[,%.]%d+)")
        local en = ts and ts:match("%-%->%s*(%d+:%d+:%d+[,%.]%d+)")
        entry_times[i] = {
            start = st and timestamp_to_seconds(st) or 0,
            finish = en and timestamp_to_seconds(en) or 0,
        }
    end

    -- Time range covered by a batch. Queue items carry their own length
    -- ({i = start, n = lines}) so rejected batches can be re-queued as
    -- smaller pieces without the global batch_size interfering.
    local function batch_range(start_index, len)
        local last = math.min(start_index + (len or batch_size) - 1, #subtitles)
        return entry_times[start_index].start, entry_times[last].finish
    end

    -- Sort the pending batches by distance to the current playback position:
    -- the part being watched (and what comes next) first, then the rest.
    local function sort_queue()
        if not o.follow_playback then
            table.sort(pending_queue, function(a, b) return a.i < b.i end)
            return
        end
        local pos = mp.get_property_number("time-pos") or 0
        local range = {}
        for _, item in ipairs(pending_queue) do
            local s, e = batch_range(item.i, item.n)
            range[item] = { start = s, finish = e }
        end
        table.sort(pending_queue, function(a, b)
            local ra, rb = range[a], range[b]
            -- "upcoming" = the batch has not ended yet, i.e. it covers the
            -- current position or comes later
            local fa = ra.finish >= pos
            local fb = rb.finish >= pos
            if fa ~= fb then return fa end  -- upcoming first
            if fa then return ra.start < rb.start end  -- upcoming: nearest first
            return ra.start > rb.start                 -- already passed: nearest first
        end)
    end

    -- Dynamically calculate parallelism
    local function calculate_parallel_calls()
        local available_time = 60
        local required_time_per_call = delay_between_calls
        local max_parallel_calls = math.floor(available_time / required_time_per_call)
        return math.max(1, math.min(max_parallel_calls, parallel_cap))
    end

    -- Process each batch of translations in parallel. len comes from the
    -- queue item; a smaller piece keeps the lines on screen from waiting for
    -- a full batch, and half-size retries rescue dropped-line batches.
    local function process_batch(batch_start_index, len)
        -- Calculate the end index for the current batch
        local end_index = math.min(batch_start_index + (len or batch_size) - 1, #subtitles)
        local batch = {}

        -- Send "N | text" lines instead of "timestamp | text": the number is
        -- far cheaper to produce than a timestamp, and it still lets us map
        -- every translated line back to the entry it belongs to.
        local batch_keys = {}
        local batch_sources = {}
        for i = batch_start_index, end_index do
            local subtitle = subtitles[i]
            local key = entry_keys[i]
            -- Only process untranslated subtitles. An entry without a
            -- timestamp (malformed srt) has no key to cache it under, so it is
            -- skipped instead of indexing the cache with nil.
            if key and not translated_cache[key] and not progress_cache[key] then
                -- A subtitle entry may span several lines; flatten it so that
                -- one entry stays one line, otherwise the numbering breaks.
                local one_line = strip_tags(subtitle.text):gsub("[\r\n]+", " ")
                -- Nothing translatable in there ("...", "♪"): keep the
                -- original and save the tokens
                if is_noop_text(one_line) then
                    translated_cache[key] = one_line
                elseif content_cache[one_line] then
                    -- Repeated line: reuse the earlier translation, no request
                    translated_cache[key] = content_cache[one_line]
                else
                    table.insert(batch, #batch_keys + 1 .. " | " .. one_line)
                    table.insert(batch_keys, key)
                    table.insert(batch_sources, one_line)
                    progress_cache[key] = true  -- Mark as in translation
                end
            end
        end

        -- Skip the batch if no new subtitles need translation
        if #batch == 0 then
            msg.debug("No new subtitles to translate for batch: " .. batch_start_index .. " to " .. end_index)
            return
        end

        -- Prepend the tail of what comes before the batch. Without it the
        -- model has no idea who is speaking and names / pronouns / honorifics
        -- drift from one batch to the next.
        local context = {}
        local ctx_count = math.max(0, math.floor(tonumber(o.context_lines) or 0))
        for i = math.max(1, batch_start_index - ctx_count), batch_start_index - 1 do
            local prev = strip_tags(subtitles[i].text):gsub("[\r\n]+", " ")
            if prev ~= "" then
                -- 已翻过的前文带上实际译法（src => dst），译名、称谓和语气
                -- 跨批次才对得上；没翻过就只有原文。复用 content_cache 的键
                -- 生成规则，保证命中。
                local dst = content_cache[prev]
                if dst then
                    table.insert(context, "- " .. prev .. " => " .. dst)
                else
                    table.insert(context, "- " .. prev)
                end
            end
        end

        -- Combine the batch into a single string
        local batch_text
        -- Nearest-point reminder: small models weight the user message more
        -- than the tail of a long system prompt, so the register-anchor rule
        -- for explicit vocabulary is repeated right next to the lines themselves.
        local vocab_reminder = ""
        if trim(o.explicit_vocab_hint) ~= "" then
            vocab_reminder = "\n(When a line above is explicit, prefer wording consistent with the reference list's register in the system prompt.)"
        end
        if #context > 0 then
            batch_text = "[Previous lines (src => translation when available), for context only - do not translate, do not output]\n"
                .. table.concat(context, "\n")
                .. "\n\n[Translate these " .. #batch .. " lines]"
                .. vocab_reminder .. "\n"
                .. table.concat(batch, "\n")
        else
            batch_text = "[Translate these " .. #batch .. " lines]"
                .. vocab_reminder .. "\n"
                .. table.concat(batch, "\n")
        end

        -- Call GPT API for asynchronous translation. cancel is declared before
        -- the call on purpose: a local declared *by* the assignment (local
        -- cancel = call_gpt_api(...)) is not in scope inside the callback, Lua
        -- reads it as a global there, and the cleanup below never matched.
        local cancel
        cancel = call_gpt_api(batch_text, function(translated_text)
            for i = #active_cancels, 1, -1 do
                if active_cancels[i] == cancel then
                    table.remove(active_cancels, i)
                end
            end
            in_flight[batch_start_index] = nil

            -- The file was unloaded while this request was in flight. Without
            -- this the callback would rebuild the queue of the old run and
            -- restart it against a file nobody is watching any more.
            if my_epoch ~= run_epoch then return end

            -- Handle API call failure: do NOT fall back to the original text,
            -- that would silently mark the whole batch as "translated" and it
            -- would never be retried (a context overflow on the server looks
            -- exactly like this). Release the lines and back off instead.
            if not translated_text then
                msg.warn("Translation request failed, this batch will be retried")
                reject_batch(batch_keys, batch_start_index, end_index - batch_start_index + 1)
                return
            end

            -- Models often wrap the answer in a markdown code block or prepend
            -- a sentence like "Here is the translation"; drop both.
            translated_text = translated_text:gsub("\r", "")
            translated_text = translated_text:gsub("^```[^\n]*\n?", ""):gsub("\n?```%s*$", ""):gsub("```", "")

            -- Split the translated text into lines, dropping empty ones
            local translated_lines = {}
            for line in translated_text:gmatch("[^\n]+") do
                local text = trim(line)
                if text ~= "" then
                    table.insert(translated_lines, text)
                end
            end

            -- A preamble shifts every line by one; strip leading lines that do
            -- not carry a number before mapping.
            while #translated_lines > #batch_keys and not line_number(translated_lines[1]) do
                table.remove(translated_lines, 1)
            end

            -- Map "N | translation" back onto the entry it belongs to
            local by_number = {}
            for _, line in ipairs(translated_lines) do
                local num, text = sanitize_output_line(line)
                if num and text and not by_number[num] then
                    by_number[num] = text
                end
            end

            local results = {}
            for k = 1, #batch_keys do
                results[k] = by_number[tostring(k)]
                if not results[k] and translated_lines[k] then
                    -- Numbering lost: fall back to the line position
                    local _, text = sanitize_output_line(translated_lines[k])
                    results[k] = text
                end
            end

            local accepted, reason = validate_batch(results, batch_sources)
            if not accepted then
                msg.warn("Batch rejected (" .. reason .. "), will retry with a smaller batch")
                reject_batch(batch_keys, batch_start_index, end_index - batch_start_index + 1)
                return
            end

            -- After the sanity check: the model ends almost every line with a
            -- full stop (and sometimes a comma or colon) even though the
            -- prompt forbids it.
            for k = 1, #batch_keys do
                results[k] = trim_trailing_punctuation(results[k])
            end

            -- Open the file for appending the translated subtitles
            local file = io.open(translated_file, "a")
            if not file then
                msg.error("Unable to open file: " .. translated_file)
                reject_batch(batch_keys, batch_start_index, end_index - batch_start_index + 1)
                return
            end

            -- Write the translated subtitles to the file
            local latest_content = {}
            local current_index = batch_start_index
            for k = 1, #batch_keys do
                latest_content[batch_keys[k]] = results[k]
                -- Cache the translated result
                translated_cache[batch_keys[k]] = results[k]
                -- Feed the content-level dedup cache
                content_cache[batch_sources[k]] = results[k]
                -- Remove from the in-progress cache
                progress_cache[batch_keys[k]] = nil
                -- Write to file
                file:write(current_index .. "\n")
                file:write(batch_keys[k] .. "\n")
                file:write(results[k] .. "\n\n")
                current_index = current_index + 1
            end
            file:close()

            -- Lines the model dropped would stay marked as "in translation"
            -- forever and never be picked up again -- release them so the
            -- retry pass can have another go at them.
            for _, k in ipairs(batch_keys) do
                if not latest_content[k] then
                    progress_cache[k] = nil
                end
            end

            local done_count = 0
            for _ in pairs(translated_cache) do done_count = done_count + 1 end
            msg.info(string.format("Translated %d/%d lines (batch %d-%d)",
                done_count, #subtitles, batch_start_index, end_index))

            local pct = math.floor(done_count * 100 / #subtitles)
            if pct >= 100 or pct >= last_pct + 10 then
                last_pct = pct - (pct % 10)
                mp.osd_message(string.format("AI 字幕翻译 %d%%", last_pct), 2)
            end
            -- Refresh the bilingual .ass. The plain translated .srt is left
            -- alone until the translation is done: reloading it would pull the
            -- selected track away from the .ass and drop the original line.
            -- When the batch covers what is on screen right now (±1s) the user
            -- is waiting on exactly this text: refresh without waiting.
            local immediate = false
            local pos = mp.get_property_number("time-pos")
            if pos then
                local s = entry_times[batch_start_index].start
                local e = entry_times[end_index].finish
                immediate = pos >= s - 1 and pos <= e + 1
            end
            request_ass(subtitles_file, immediate)

            -- Update in-progress batch count
            in_progress_batches = in_progress_batches - 1

            -- Keep going with the next batch (re-sorted by the playback position)
            pump()
        end, cur_temperature)

        -- Registered for the on_unload abort; the callback removes itself again.
        -- This insert was missing at some point, which silently turned the
        -- unload abort into a loop over an empty table.
        table.insert(active_cancels, cancel)
        in_flight[batch_start_index] = {
            cancel = cancel,
            s = entry_times[batch_start_index].start,
            e = entry_times[end_index].finish,
        }

        -- Increase in-progress batch count
        in_progress_batches = in_progress_batches + 1
    end

    -- Pull batches off the queue while there are free slots
    pump = function()
        -- A timer from before the unload firing now: the queue it was meant to
        -- work on is gone and rebuilding it would restart the old translation.
        if my_epoch ~= run_epoch then return end
        pump_scheduled = false
        -- Sorted once per pump: the loop below is synchronous, so the playback
        -- position cannot move between its iterations -- re-sorting after every
        -- launched batch re-evaluated the whole queue for nothing.
        if #pending_queue > 0 then sort_queue() end

        -- Hot-priority: while a request covering the current position is in
        -- flight, hold all other slots. A 7B model is GPU-bound -- the hot
        -- batch competing with three full-size batches is what made the first
        -- display wait 8+s; alone it comes back in ~1-2s. The cost is a slot
        -- for the duration of the hot window (a couple of seconds per trigger
        -- or seek), the total run time barely moves.
        local hot_in_flight = false
        if o.follow_playback and hot_lines > 0 then
            local pos = mp.get_property_number("time-pos")
            if pos then
                for _, flight in pairs(in_flight) do
                    if pos >= flight.s - 1 and pos <= flight.e + 1 then
                        hot_in_flight = true
                        break
                    end
                end
            end
        end
        local max_parallel_calls = hot_in_flight and 1 or calculate_parallel_calls()

        -- Peel a small "hot" batch off the front item when it covers the
        -- current position: the handful of lines actually on screen come back
        -- in a second or two instead of after a whole batch, and the rest of
        -- the batch follows right behind as a normal request. Only split when
        -- a slot is free and the piece launches right away: splitting while
        -- everything waits would let every timer-driven pump shave two more
        -- lines off the front and fragment the whole queue into micro-batches.
        if o.follow_playback and hot_lines > 0 and #pending_queue > 0
            and in_progress_batches < max_parallel_calls then
            local front = pending_queue[1]
            if not hot_split[front.i] and front.n > hot_lines then
                local pos = mp.get_property_number("time-pos")
                local s, e = batch_range(front.i, front.n)
                if pos and pos >= s - 1 and pos <= e + 1 then
                    hot_split[front.i] = true
                    table.insert(pending_queue, 2, {i = front.i + hot_lines, n = front.n - hot_lines})
                    pending_queue[1] = {i = front.i, n = hot_lines}
                    msg.debug(string.format("hot batch split off: %d-%d (front of queue)",
                        front.i, front.i + hot_lines - 1))
                    -- Launch the hot batch alone this tick. Firing it together
                    -- with the full-size batches lets the server (continuous
                    -- batching) fold them into one generation, so the two lines
                    -- on screen wait for the 28-line prefill behind them:
                    -- measured 1.6s alone-with-the-rest vs 0.6s on its own.
                    -- The rest goes out on the next pump, total time unchanged.
                    max_parallel_calls = 1
                end
            end
        end

        while in_progress_batches < max_parallel_calls and #pending_queue > 0 do
            local item = table.remove(pending_queue, 1)
            process_batch(item.i, item.n)
        end

        if #pending_queue == 0 and in_progress_batches == 0 then
            -- Anything the model dropped gets one more chance (bigger batches
            -- make dropped lines more likely). Give up after two extra passes
            -- so a broken backend cannot loop forever.
            local missing = 0
            for i = 1, #subtitles do
                local key = entry_keys[i]
                if not key or not translated_cache[key] then
                    missing = missing + 1
                end
            end

            if missing > 0 and retry_pass < 2 then
                retry_pass = retry_pass + 1
                msg.info(string.format("Retrying %d untranslated lines (pass %d)", missing, retry_pass))
                pending_queue = {}
                for i = 1, #subtitles, batch_size do
                    table.insert(pending_queue, {i = i, n = math.min(batch_size, #subtitles - i + 1)})
                end
                hot_split = {}
                mp.add_timeout(0.2, pump)
                return
            end

            -- Timers scheduled by earlier waves may fire pump again after
            -- everything is done; do not rebuild the ass file once per timer.
            if finished then return end
            finished = true
            ass_dirty = false

            msg.info("Subtitle translation completed!")
            -- Only now that the .srt is complete: added without "auto" it would
            -- take over the selection from the bilingual .ass.
            add_sub_once(translated_file)
            generate_ass(subtitles_file)

            translating = false
            if missing > 0 then
                mp.osd_message(string.format("字幕翻译完成，但有 %d 条未能翻译（请检查 AI 服务）", missing), 6)
            else
                mp.osd_message("AI 字幕翻译完成", 4)
            end
            return
        end

        -- All slots busy or waiting for a slot: retry later
        if #pending_queue > 0 and not pump_scheduled then
            pump_scheduled = true
            mp.add_timeout(delay_between_calls, pump)
        end
    end

    -- A seek re-prioritises the queue right away instead of waiting for the
    -- next batch callback to trigger a pump: the batches covering the new
    -- position move to the front and launch as soon as a slot is free.
    seek_pump = function()
        if my_epoch ~= run_epoch or not o.follow_playback then return end
        if #pending_queue == 0 then return end
        sort_queue()

        -- All slots busy: abort the in-flight request that is farthest from
        -- the new position so the lines on screen after the seek do not wait
        -- for a whole batch of the old position to finish. The aborted lines
        -- re-enter the queue via reject_batch, nothing is lost. Only clearly
        -- distant batches (more than half a minute away) are given up.
        local max_parallel_calls = calculate_parallel_calls()
        if hot_lines > 0 and in_progress_batches >= max_parallel_calls then
            local pos = mp.get_property_number("time-pos")
            if pos then
                local victim, dist
                for _, flight in pairs(in_flight) do
                    local d
                    if pos < flight.s then d = flight.s - pos
                    elseif pos > flight.e then d = pos - flight.e
                    else d = 0 end
                    if d > 30 and (not dist or d > dist) then
                        victim, dist = flight, d
                    end
                end
                if victim then
                    msg.debug("seek: aborting a far in-flight batch to free a slot")
                    victim.cancel()
                    return  -- the reject path pumps again once the slot is back
                end
            end
        end

        pump()
    end

    -- Build the queue of batch items ({i = start, n = lines})
    pending_queue = {}
    hot_split = {}
    for i = 1, #subtitles, batch_size do
        table.insert(pending_queue, {i = i, n = math.min(batch_size, #subtitles - i + 1)})
    end

    pump()
end

-- Translate .srt file
local function translate_srt_file(subtitles_file)
    if translating then
        mp.osd_message("字幕翻译正在进行中", 3)
        return
    end

    if not o.api_key or o.api_key == "" then
        mp.osd_message("未配置 api_key，无法翻译字幕", 5)
        msg.error("api_key is empty, subtitle translation aborted")
        return
    end

    if not subtitles_file then
        subtitles_file = get_current_sub()
    end
    if not subtitles_file then
        mp.osd_message("当前没有可翻译的外部 srt 字幕", 5)
        msg.error("No external .srt subtitle is currently loaded")
        return
    end

    -- Parse the original subtitle file
    local subtitles = parse_srt(subtitles_file)
    if not subtitles or #subtitles == 0 then
        mp.osd_message("字幕文件为空或解析失败", 5)
        msg.error("Failed to parse .srt file: " .. subtitles_file)
        return
    end

    -- Reuse whatever a previous run already translated, so triggering the
    -- translation again only pays for the missing lines
    local translated_file = subtitles_file:gsub("%.srt$", ".translate.srt")
    if file_exists(translated_file) then
        local already = parse_srt(translated_file)
        local reused = 0
        for _, entry in ipairs(already or {}) do
            local key = normalize_timestamp(entry.timestamp)
            if key and entry.text and entry.text ~= "" and not translated_cache[key] then
                -- Older cache files still carry the trailing full stop
                translated_cache[key] = trim_trailing_punctuation(entry.text)
                reused = reused + 1
            end
        end
        if reused > 0 then
            msg.info("Reusing " .. reused .. " already translated lines")
        end
    end

    mp.osd_message("AI 字幕翻译中", 5)
    msg.info("AI subtitle translation started: " .. subtitles_file)

    -- Start translating
    translating = true
    translate_and_write(subtitles, subtitles_file)
end
--------------------------------------------------

mp.add_hook("on_unload", 50, function()
    -- First, before the aborts below: a callback fired synchronously by
    -- abort_async_command must already find itself outdated, or it would
    -- resurrect the run that is being torn down.
    run_epoch = run_epoch + 1
    -- Kill the requests still in flight: their callbacks would otherwise run
    -- against the state of whatever file gets loaded next
    for _, cancel in ipairs(active_cancels) do
        if cancel then cancel() end
    end
    active_cancels = {}
    translating = false
    pending_queue = {}
    pump_scheduled = false
    in_progress_batches = 0
    progress_cache = {}
    translated_cache = {}
    content_cache = {}
    last_ass_content = {}
    originals_cache = {}
    ass_track_id = {}
    seek_pump = nil
    collectgarbage()
end)

-- Trigger with: script-message translate [optional path to an .srt]
mp.register_script_message("translate", translate_srt_file)

-- Re-prioritise the translation queue after a seek. The short delay lets the
-- new position settle, so sort_queue() reads the time-pos the user jumped to
-- rather than the one before the seek.
mp.register_event("seek", function()
    if not seek_pump then return end
    mp.add_timeout(0.1, function()
        if seek_pump then seek_pump() end
    end)
end)
