--- MC Validation - Common validation and lookup utilities for Quarto extensions
--- @module validation
--- @license MIT
--- @copyright 2026 Mickaël Canouil
--- @author Mickaël Canouil
--- @version 1.0.0

local M = {}

-- ============================================================================
-- ARRAY VALIDATION
-- ============================================================================

--- Validate value against array of valid values with optional formatting.
--- Checks if a value exists in a predefined array and optionally formats it.
--- Useful for validating animation names, size keywords, etc.
---
--- @param value string|nil Value to validate
--- @param valid_array table<integer, string> Array of valid values
--- @param formatter function|string|nil Optional formatter: function(value), prefix string, or nil
--- @return string|nil Formatted value if valid and formatter provided, empty string if valid without formatter, nil if invalid
--- @usage local result = M.is_valid_value("bounce", {"bounce", "flash"}, "animate__") -- returns "animate__bounce"
--- @usage local result = M.is_valid_value("invalid", {"bounce", "flash"}, "animate__") -- returns nil
function M.is_valid_value(value, valid_array, formatter)
  if value == nil or value == '' then
    return nil
  end

  -- Check if value exists in valid_array
  for _, valid in ipairs(valid_array) do
    if valid == value then
      -- Value is valid, apply formatter if provided
      if formatter == nil then
        return ''
      elseif type(formatter) == "function" then
        return formatter(value)
      elseif type(formatter) == "string" then
        -- Assume formatter is a prefix to add
        return formatter .. value
      end
    end
  end

  -- Value not found in valid_array
  return nil
end

--- Check if value exists in array (boolean check only).
--- Simple membership test without formatting.
---
--- @param value any Value to check
--- @param valid_array table<integer, any> Array of valid values
--- @return boolean True if value is in array, false otherwise
--- @usage local exists = M.in_array("bounce", {"bounce", "flash"}) -- returns true
function M.in_array(value, valid_array)
  if value == nil then
    return false
  end

  for _, valid in ipairs(valid_array) do
    if valid == value then
      return true
    end
  end

  return false
end

-- ============================================================================
-- KEYWORD MAPPING
-- ============================================================================

--- Convert keyword to value using mapping table.
--- Looks up a keyword in a mapping table and returns the corresponding value.
--- Falls back to default if provided, otherwise returns the keyword itself.
---
--- @param keyword string|nil Keyword to convert
--- @param mapping table<string, string> Mapping table (keyword → value)
--- @param default string|nil Default value if keyword not found (optional)
--- @return string|nil Mapped value, default, or keyword itself
--- @usage local size = M.keyword_to_value("large", {large = "1.2em"}) -- returns "1.2em"
--- @usage local size = M.keyword_to_value("2em", {large = "1.2em"}) -- returns "2em" (passthrough)
function M.keyword_to_value(keyword, mapping, default)
  if keyword == nil or keyword == '' then
    return default
  end

  -- Check if keyword exists in mapping
  if mapping[keyword] then
    return mapping[keyword]
  end

  -- Not found: return default if provided, otherwise return keyword itself
  if default ~= nil then
    return default
  end

  return keyword
end

--- Predefined size keywords to CSS em values.
--- Supports LaTeX-style size keywords, numeric multipliers, and Tailwind-style sizes.
--- @type table<string, string>
M.SIZE_KEYWORDS = {
  -- LaTeX-style sizes
  ['tiny']         = '0.5em',
  ['scriptsize']   = '0.7em',
  ['footnotesize'] = '0.8em',
  ['small']        = '0.9em',
  ['normalsize']   = '1em',
  ['large']        = '1.2em',
  ['Large']        = '1.5em',
  ['LARGE']        = '1.75em',
  ['huge']         = '2em',
  ['Huge']         = '2.5em',
  -- Numeric multipliers
  ['1x']           = '1em',
  ['2x']           = '2em',
  ['3x']           = '3em',
  ['4x']           = '4em',
  ['5x']           = '5em',
  ['6x']           = '6em',
  ['7x']           = '7em',
  ['8x']           = '8em',
  ['9x']           = '9em',
  ['10x']          = '10em',
  -- Tailwind-style sizes
  ['2xs']          = '0.625em',
  ['xs']           = '0.75em',
  ['sm']           = '0.875em',
  ['lg']           = '1.25em',
  ['xl']           = '1.5em',
  ['2xl']          = '2em'
}

--- Convert size keyword to CSS font-size property.
--- Converts size keywords (e.g., "large", "2x") to CSS font-size values.
--- If the input is already a CSS value (contains units), returns it with font-size prefix.
---
--- @param size string|nil Size keyword or CSS value
--- @return string CSS font-size property (e.g., "font-size: 1.2em;") or empty string
--- @usage local css = M.size_to_css("large") -- returns "font-size: 1.2em;"
--- @usage local css = M.size_to_css("16px") -- returns "font-size: 16px;"
function M.size_to_css(size)
  if size == nil or size == '' then
    return ''
  end

  -- Check if it's a predefined keyword
  if M.SIZE_KEYWORDS[size] then
    return 'font-size: ' .. M.SIZE_KEYWORDS[size] .. ';'
  end

  -- Assume it's a custom CSS value (e.g., "16px", "1.5rem")
  return 'font-size: ' .. size .. ';'
end

--- Predefined modal size keywords to Bootstrap classes.
--- Maps Bootstrap modal size keywords to their corresponding CSS classes.
--- @type table<string, string>
M.MODAL_SIZE_CLASSES = {
  ['sm'] = 'modal-sm',
  ['lg'] = 'modal-lg',
  ['xl'] = 'modal-xl'
}

-- ============================================================================
-- FILE EXTENSION VALIDATION
-- ============================================================================

--- Check if URI has one of the specified extensions.
--- Performs case-insensitive extension matching by default.
--- Extensions can be provided with or without leading dot.
---
--- @param uri string|nil File URI to check
--- @param extensions table<integer, string> Array of extensions (e.g., {".md", "qmd", ".txt"})
--- @param case_sensitive boolean|nil Whether to match case-sensitively (default: false)
--- @return boolean True if URI ends with one of the extensions, false otherwise
--- @usage local is_md = M.has_extension("file.md", {".md", ".markdown"}) -- returns true
--- @usage local is_md = M.has_extension("file.MD", {".md"}, true) -- returns false (case-sensitive)
function M.has_extension(uri, extensions, case_sensitive)
  if uri == nil or uri == '' or extensions == nil then
    return false
  end

  --- @type string URI for matching (lowercase if case-insensitive)
  local match_uri = case_sensitive and uri or uri:lower()

  for _, ext in ipairs(extensions) do
    --- @type string Extension to match (ensure it starts with dot)
    local match_ext = ext
    if not match_ext:match('^%.') then
      match_ext = '.' .. match_ext
    end

    --- @type string Extension for matching (lowercase if case-insensitive)
    if not case_sensitive then
      match_ext = match_ext:lower()
    end

    -- Check if URI ends with this extension
    if match_uri:match('%' .. match_ext .. '$') then
      return true
    end
  end

  return false
end

--- Check if URI is a markdown file.
--- Convenience function to check for markdown extensions: .md, .markdown, .qmd
---
--- @param uri string|nil File URI to check
--- @return boolean True if markdown file, false otherwise
--- @usage local is_markdown = M.is_markdown("doc.qmd") -- returns true
function M.is_markdown(uri)
  return M.has_extension(uri, { '.md', '.markdown', '.qmd' })
end

-- ============================================================================
-- MODULE EXPORT
-- ============================================================================

return M
