-- math-alt.lua
-- For Typst/PDF-UA-1 output: adds alt text to math equations using the
-- LaTeX source as the text alternative. Uses pandoc.write to get the
-- already-converted Typst math syntax, then wraps it so Typst can attach
-- the alt attribute.
--
-- Two strategies:
--   Math(el)      — handles pandoc Math nodes in prose (has LaTeX source)
--   RawBlock/RawInline — handles math embedded in raw Typst output from
--                  tinytable/modelsummary, which emits pre-formed Typst
--                  RawBlocks that pandoc never parses as Math nodes.
--                  Alt text is the Typst math body (LaTeX source unavailable).

function Math(el)
  if FORMAT ~= "typst" then return nil end

  -- Get the Typst-converted math string via pandoc's own Typst writer
  local tmp = pandoc.Pandoc({ pandoc.Para({ el }) })
  local typst = pandoc.write(tmp, "typst"):match("^%s*(.-)%s*$")

  -- Escape the LaTeX source for use as a Typst string literal
  local alt = el.text
    :gsub("\\", "\\\\")
    :gsub('"', '\\"')
    :gsub("\n", " ")

  local is_block = tostring(el.mathtype == "DisplayMath")

  -- Extract body from a temp equation, then recreate with alt text.
  -- Can't use ..it.fields() directly in a show rule because Typst doesn't
  -- expose `alt` as a filterable/checkable field, causing infinite recursion.
  local code = string.format(
    '#{ let _q = %s; math.equation(_q.body, alt: "%s", block: %s) }',
    typst, alt, is_block
  )

  return pandoc.RawInline("typst", code)
end

-- Wrap bare $...$ patterns in raw Typst strings.
-- Used for math inside RawBlock/RawInline output (e.g., tinytable notes).
-- Treats the body as LaTeX source and converts to Typst via pandoc,
-- matching the Math(el) approach so LaTeX in notes works the same as
-- LaTeX in prose (HTML output is unaffected; these handlers only run
-- when FORMAT == "typst").
local function wrap_math_in_typst(text)
  return (text:gsub("%$(.-)%$", function(body)
    -- Detect display math: Typst uses leading+trailing space ($ x $)
    local is_display = (body:sub(1, 1) == " " and body:sub(-1) == " ")
    -- Trim boundary spaces for display math to get the bare LaTeX source
    local latex = is_display and body:match("^ (.+) $") or body

    -- Convert LaTeX math → Typst via pandoc (same path as Math(el) above)
    local math_el = pandoc.Math(
      is_display and "DisplayMath" or "InlineMath",
      latex
    )
    local tmp = pandoc.Pandoc({ pandoc.Para({ math_el }) })
    local typst = pandoc.write(tmp, "typst"):match("^%s*(.-)%s*$")

    -- Use LaTeX source as the alt text
    local alt = latex
      :gsub("\\", "\\\\")
      :gsub('"', '\\"')
      :gsub("\n", " ")

    return string.format(
      '#{ let _q = %s; math.equation(_q.body, alt: "%s", block: %s) }',
      typst, alt, tostring(is_display)
    )
  end))
end

function RawInline(el)
  if FORMAT ~= "typst" or el.format ~= "typst" then return nil end
  -- Skip elements already processed by Math() above
  if el.text:find("math%.equation%(", 1, true) then return nil end
  local new = wrap_math_in_typst(el.text)
  if new ~= el.text then return pandoc.RawInline("typst", new) end
end

function RawBlock(el)
  if FORMAT ~= "typst" or el.format ~= "typst" then return nil end
  if el.text:find("math%.equation%(", 1, true) then return nil end
  local new = wrap_math_in_typst(el.text)
  if new ~= el.text then return pandoc.RawBlock("typst", new) end
end
