--- Typst Render - Filter
--- @module typst-render
--- @license MIT
--- @copyright 2026 Mickaël Canouil
--- @author Mickaël Canouil
--- @version 1.0.0
--- @brief Compiles {typst} code blocks to images for non-Typst output formats.
--- @description Intercepts ```{typst} CodeBlock elements and compiles them to
---   images (PNG, SVG, or PDF) using the Typst binary bundled with Quarto,
---   making Typst diagrams, figures, and tables usable across all output formats.

--- Extension name constant
local EXTENSION_NAME = 'typst-render'

--- Load modules
local utils = require(quarto.utils.resolve_path('_modules/utils.lua'):gsub('%.lua$', ''))
local code_cell = require(quarto.utils.resolve_path('_modules/code-cell.lua'):gsub('%.lua$', ''))
local cell = code_cell.new({ language = 'typst', comment_prefix = '//|' })

-- ============================================================================
-- CONSTANTS
-- ============================================================================

--- Valid image format set for O(1) lookup
local VALID_FORMAT_SET = { png = true, svg = true, pdf = true }

--- Default option values
local DEFAULTS = {
  format = nil,
  dpi = '144',
  width = 'auto',
  height = 'auto',
  margin = '0.5em',
  background = 'none',
  preamble = '',
  cache = true,
  file = nil,
  root = nil,
  ['font-path'] = nil,
  input = nil,
  echo = false,
  eval = true,
  include = true,
  output = true,
  ['output-location'] = nil,
  classes = nil,
  label = nil,
}

--- Keys consumed by the filter; any other option is forwarded as an HTML attribute.
local KNOWN_KEYS = { cap = true, alt = true, _block_input = true }
for k in pairs(DEFAULTS) do
  KNOWN_KEYS[k] = true
end

--- Check whether a key is consumed by the filter (not forwarded as an attribute).
--- Matches exact known keys and prefix-specific cross-ref keys (e.g. fig-cap, tbl-alt).
--- @param key string
--- @return boolean
local function is_known_key(key)
  if KNOWN_KEYS[key] then
    return true
  end
  return key:match('^%a+%-cap$') ~= nil or key:match('^%a+%-alt$') ~= nil
end

--- Cache subdirectory within the .quarto scratch directory
local CACHE_SUBDIR = '.quarto/typst-render'

-- ============================================================================
-- MODULE STATE
-- ============================================================================

--- Global configuration from document metadata
local global_config = {}

--- Resolved Typst binary path (cached)
local typst_bin = nil

--- Whether Typst binary availability has been checked
local typst_checked = false

--- Block counter for auto-numbering unlabelled blocks
local block_counter = 0

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

--- Resolve a file path following the Quarto convention.
--- Paths starting with "/" are relative to the project root;
--- other paths are relative to the current document directory.
--- @param path string The file path to resolve
--- @return string Resolved file path
local function resolve_file_path(path)
  if path:sub(1, 1) == '/' and quarto.project and quarto.project.directory then
    return pandoc.path.join({ quarto.project.directory, path:sub(2) })
  end
  return path
end

--- Resolve the Typst binary path.
--- @return string|nil Path to the Typst binary, or nil if not found
local function resolve_typst_bin()
  if typst_checked then
    return typst_bin
  end
  typst_checked = true

  local path = quarto.paths.typst()
  if path and path ~= '' then
    typst_bin = path
    return typst_bin
  end

  utils.log_error(EXTENSION_NAME, 'Typst binary not found. Ensure Quarto >= 1.6 is installed.')
  return nil
end

--- Determine the best image format for the current output.
--- @return string Image format: "svg", "pdf", or "png"
local function get_image_format_for_output()
  if quarto.format.is_html_output() then
    return 'svg'
  elseif quarto.format.is_latex_output() then
    return 'pdf'
  elseif quarto.format.is_docx_output() or quarto.format.is_powerpoint_output() then
    return 'png'
  else
    return 'png'
  end
end

--- Resolve a preamble value to Typst code.
--- If the value ends with `.typ`, it is treated as a file path and its contents
--- are read; otherwise the value is used as inline Typst code.
--- @param value string Inline Typst code or path to a `.typ` file
--- @return string|nil Resolved Typst code, or nil on read failure
local function resolve_preamble(value)
  if not value or value == '' then
    return nil
  end
  if value:match('%.typ$') then
    local file_path = resolve_file_path(value)
    local f = io.open(file_path, 'r')
    if f then
      local content = f:read('*a')
      f:close()
      return content
    end
    utils.log_error(EXTENSION_NAME, 'Could not read preamble file: ' .. value)
    return nil
  end
  return value
end

--- Parse a comma-separated string of key=value pairs into a table.
--- @param str string Input string like "key1=val1,key2=val2"
--- @return table Parsed key-value table
local function parse_input_string(str)
  local result = {}
  if not str or str == '' then
    return result
  end
  for pair in str:gmatch('[^,]+') do
    local k, v = pair:match('^%s*(.-)%s*=%s*(.-)%s*$')
    if k and k ~= '' then
      result[k] = v or ''
    end
  end
  return result
end

--- Merge global and per-block input maps. Per-block values override global ones.
--- @param global_input table|nil Global input map from YAML
--- @param block_input string|nil Per-block comma-separated input string
--- @return table Merged input map (may be empty)
local function merge_inputs(global_input, block_input)
  local merged = {}
  if type(global_input) == 'table' then
    for k, v in pairs(global_input) do
      merged[k] = v
    end
  end
  if type(block_input) == 'string' then
    for k, v in pairs(parse_input_string(block_input)) do
      merged[k] = v
    end
  end
  return merged
end

--- Serialise an input map as a sorted, deterministic string for cache hashing.
--- @param input_map table Key-value table
--- @return string Serialised string like "key1=val1|key2=val2"
local function serialise_inputs(input_map)
  local keys = {}
  for k in pairs(input_map) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = k .. '=' .. input_map[k]
  end
  return table.concat(parts, '|')
end

--- Build the `#set page(...)` directive from options (for image compilation).
--- @param opts table Merged options
--- @return string Typst page directive
local function build_page_directive(opts)
  return string.format(
    '#set page(width: %s, height: %s, margin: %s, fill: %s)',
    opts.width, opts.height, opts.margin, opts.background
  )
end

--- Check whether block-level options differ from defaults for native Typst output.
--- Only `background` and `margin` are propagated (as `fill` and `inset`).
--- @param opts table Merged options
--- @return boolean
local function has_custom_block_options(opts)
  return opts.background ~= DEFAULTS.background
    or opts.margin ~= DEFAULTS.margin
end

--- Build the full Typst source with page template.
--- @param code string User Typst code
--- @param opts table Merged options
--- @return string Complete Typst source
local function build_typst_source(code, opts)
  local parts = {}
  parts[#parts + 1] = build_page_directive(opts)
  local preamble = resolve_preamble(opts.preamble)
  if preamble then
    parts[#parts + 1] = preamble
  end
  parts[#parts + 1] = code
  return table.concat(parts, '\n')
end

--- Build a human-readable cache file stem from label or block number and a
--- content hash.  Returns e.g. "typst-fig-my-diagram-a1b2c3d4" or "typst-block-3-a1b2c3d4".
--- @param source string Full Typst source
--- @param fmt string Image format
--- @param dpi string DPI value
--- @param label string|nil Cross-reference label
--- @return string File stem (without extension)
local function compute_cache_stem(source, fmt, dpi, label)
  local hash = pandoc.utils.sha1(source .. '|' .. fmt .. '|' .. dpi):sub(1, 8)
  if type(label) == 'string' and label ~= '' then
    return 'typst-' .. label .. '-' .. hash
  end
  block_counter = block_counter + 1
  return 'typst-block-' .. block_counter .. '-' .. hash
end

--- Ensure the cache directory exists.
--- @return string Absolute path to the cache directory
--- @return string Relative path to the cache directory (for image references)
local function ensure_cache_dir()
  local rel_path = CACHE_SUBDIR
  local abs_path = CACHE_SUBDIR
  if quarto.project and quarto.project.directory then
    abs_path = pandoc.path.join({ quarto.project.directory, CACHE_SUBDIR })
  end
  pandoc.system.make_directory(abs_path, true)
  return abs_path, rel_path
end

--- Compile Typst source to an image file.
--- Uses stdin to pass source code, avoiding temporary .typ files.
--- @param source string Full Typst source code
--- @param opts table Merged options
--- @param img_format string Target image format
--- @return string|nil Path to the compiled image, or nil on failure
local function compile_typst(source, opts, img_format)
  local bin = resolve_typst_bin()
  if not bin then
    return nil
  end

  local dpi = tostring(opts.dpi)

  -- Merge global and per-block input variables
  local merged_input = merge_inputs(opts.input, opts._block_input)
  local input_serial = serialise_inputs(merged_input)

  -- Include inputs in cache hash material
  local hash_source = source
  if input_serial ~= '' then
    hash_source = source .. '|input:' .. input_serial
  end

  local use_cache = opts.cache ~= false
  local stem = compute_cache_stem(hash_source, img_format, dpi, opts.label)
  local abs_cache, rel_cache = ensure_cache_dir()
  local abs_output = pandoc.path.join({ abs_cache, stem .. '.' .. img_format })
  local rel_output = pandoc.path.join({ rel_cache, stem .. '.' .. img_format })

  if use_cache then
    local f = io.open(abs_output, 'r')
    if f then
      f:close()
      return rel_output
    end
  end

  -- Resolve --root: explicit option, project directory, or working directory
  local resolved_root
  if opts.root then
    resolved_root = resolve_file_path(opts.root)
  elseif quarto.project and quarto.project.directory then
    resolved_root = quarto.project.directory
  else
    resolved_root = pandoc.system.get_working_directory()
  end

  local args = { 'compile', '--format', img_format, '--ppi', dpi, '--root', resolved_root }

  -- Add --font-path if specified
  if opts['font-path'] then
    local resolved_font_path = resolve_file_path(opts['font-path'])
    args[#args + 1] = '--font-path'
    args[#args + 1] = resolved_font_path
  end

  -- Add --input flags for each input variable
  local sorted_keys = {}
  for k in pairs(merged_input) do
    sorted_keys[#sorted_keys + 1] = k
  end
  table.sort(sorted_keys)
  for _, k in ipairs(sorted_keys) do
    args[#args + 1] = '--input'
    args[#args + 1] = k .. '=' .. merged_input[k]
  end

  -- Use stdin ('-') instead of a temp file
  args[#args + 1] = '-'
  args[#args + 1] = abs_output

  local ok, result = pcall(pandoc.pipe, bin, args, source)
  if not ok then
    utils.log_error(
      EXTENSION_NAME,
      'Typst compilation failed:\n' .. tostring(result)
    )
    return nil
  end

  -- Typst CLI generates {stem}{page}.{ext} for PNG (e.g., output1.png)
  -- Check if the expected output exists; if not, try the page-numbered variant
  local out_f = io.open(abs_output, 'r')
  if not out_f then
    local page_path = pandoc.path.join({ abs_cache, stem .. '1.' .. img_format })
    local page_f = io.open(page_path, 'r')
    if page_f then
      page_f:close()
      os.rename(page_path, abs_output)
    else
      utils.log_error(EXTENSION_NAME, 'Compiled file not found: ' .. abs_output)
      return nil
    end
  else
    out_f:close()
  end

  return rel_output
end

--- Map from cross-reference prefix to Quarto FloatRefTarget type name.
--- Built-in types are pre-populated; custom types are added from metadata
--- during the Meta pass (see get_configuration).
local REF_TYPE_NAMES = {
  fig = 'Figure',
  tbl = 'Table',
  lst = 'Listing',
}

--- Create a Pandoc Image element from a compiled image.
--- @param img_path string Path to the image file
--- @param opts table Merged options
--- @return pandoc.Para Para containing the image
local function create_image_element(img_path, opts)
  local caption_text = cell.resolve_caption(opts)
  local alt_text = cell.resolve_alt(opts, caption_text)

  local classes = {}
  if quarto.format.is_html_output() then
    classes[#classes + 1] = 'img-fluid'
  end
  if type(opts.classes) == 'string' and opts.classes ~= '' then
    for cls in opts.classes:gmatch('%S+') do
      classes[#classes + 1] = cls
    end
  end

  local kvpairs = {}
  for k, v in pairs(opts) do
    if not is_known_key(k) and type(v) == 'string' then
      kvpairs[#kvpairs + 1] = { k, v }
    end
  end

  local img = pandoc.Image(
    { pandoc.Str(alt_text) },
    img_path,
    '',
    pandoc.Attr('', classes, kvpairs)
  )

  return pandoc.Para({ img })
end

--- Read an external `.typ` file, resolving relative to the project directory.
--- @param file_opt string Path from the `file` option
--- @return string|nil File contents, or nil on failure
local function read_external_file(file_opt)
  local file_path = resolve_file_path(file_opt)
  local f = io.open(file_path, 'r')
  if f then
    local content = f:read('*a')
    f:close()
    return content
  end
  utils.log_error(EXTENSION_NAME, 'Could not read file: ' .. file_opt)
  return nil
end

-- ============================================================================
-- FILTER FUNCTIONS
-- ============================================================================

--- Register custom cross-reference categories from document metadata.
--- Reads `crossref.custom` entries and adds their `key` -> `reference-prefix`
--- mappings to REF_TYPE_NAMES so that wrap_crossref can look them up.
--- @param meta pandoc.Meta
local function register_custom_crossref_types(meta)
  local cr = meta['crossref']
  if not cr then
    return
  end
  local custom = cr['custom']
  if not custom or type(custom) ~= 'table' then
    return
  end
  for _, entry in ipairs(custom) do
    local key = entry['key'] and pandoc.utils.stringify(entry['key'])
    local name = entry['reference-prefix'] and pandoc.utils.stringify(entry['reference-prefix'])
    if key and name then
      REF_TYPE_NAMES[key] = name
    end
  end
end

--- Extract global configuration from document metadata.
--- @param meta pandoc.Meta
--- @return pandoc.Meta
local function get_configuration(meta)
  register_custom_crossref_types(meta)

  local ext_config = nil

  if utils.get_extension_config(meta, EXTENSION_NAME) then
    ext_config = utils.get_extension_config(meta, EXTENSION_NAME)
  elseif meta['typst-render'] then
    ext_config = meta['typst-render']
  end

  if ext_config then
    -- Iterate all DEFAULTS keys explicitly; pairs() skips nil-valued keys,
    -- so we use a separate key list to ensure 'format' etc. are not missed.
    local config_keys = {
      'format', 'dpi', 'width', 'height', 'margin', 'background',
      'preamble', 'cache', 'echo', 'eval', 'include', 'output', 'output-location', 'classes',
      'root', 'font-path',
    }
    for _, k in ipairs(config_keys) do
      local default_val = DEFAULTS[k]
      if ext_config[k] ~= nil then
        local val = ext_config[k]
        if k == 'echo' then
          if type(val) == 'boolean' then
            global_config[k] = val
          else
            local str = pandoc.utils.stringify(val)
            if str == 'fenced' then
              global_config[k] = 'fenced'
            else
              global_config[k] = str == 'true'
            end
          end
        elseif type(default_val) == 'boolean' then
          if type(val) == 'boolean' then
            global_config[k] = val
          else
            local str = pandoc.utils.stringify(val)
            global_config[k] = str == 'true'
          end
        else
          global_config[k] = pandoc.utils.stringify(val)
        end
      end
    end

    -- Handle 'input' separately: store as a key-value table (YAML map)
    if ext_config['input'] ~= nil then
      local raw = ext_config['input']
      if type(raw) == 'table' then
        local input_map = {}
        for k, v in pairs(raw) do
          input_map[tostring(k)] = pandoc.utils.stringify(v)
        end
        global_config['input'] = input_map
      end
    end
  end

  return meta
end

--- Process a {typst} CodeBlock element.
--- @param el pandoc.CodeBlock
--- @return pandoc.Block|pandoc.Blocks|nil
local function process_codeblock(el)
  if not cell.is_code_block(el) then
    return nil
  end

  local block_opts, clean_code, option_lines = cell.parse_options(el.text)

  -- Stash per-block input string before merge overwrites it with global table
  local block_input_str = nil
  if type(block_opts.input) == 'string' then
    block_input_str = block_opts.input
    block_opts.input = nil
  end

  local opts = cell.merge_options(block_opts, global_config, DEFAULTS)
  opts._block_input = block_input_str

  if not cell.should_include(opts) then
    return pandoc.Null()
  end

  local do_eval = opts.eval ~= false
  local do_echo = opts.echo == true or opts.echo == 'fenced'
  local is_fenced = opts.echo == 'fenced'
  local output_mode = cell.resolve_output_mode(opts)

  -- Handle eval/echo matrix: both false means hidden block
  if not do_eval and not do_echo then
    return pandoc.Null()
  end

  -- Resolve source code
  local code = clean_code
  if opts.file then
    code = read_external_file(opts.file)
    if not code then return el end
  end

  -- Echo-only: show source listing without compilation
  if not do_eval then
    return cell.create_echo_block(code, is_fenced, option_lines)
  end

  -- Output suppressed: skip compilation, show echo block only
  if output_mode == 'false' then
    if do_echo then
      return cell.create_echo_block(code, is_fenced, option_lines)
    end
    return pandoc.Null()
  end

  -- Native Typst output: pass through as scoped RawBlock, wrapped in crossref if needed
  if quarto.format.is_typst_output() then
    local preamble = resolve_preamble(opts.preamble)
    local parts = {}
    if preamble then
      parts[#parts + 1] = preamble
    end
    parts[#parts + 1] = code
    local inner = table.concat(parts, '\n')
    local scoped_code
    if has_custom_block_options(opts) then
      local params = { 'width: 100%' }
      if opts.margin ~= DEFAULTS.margin then
        params[#params + 1] = 'inset: ' .. opts.margin
      end
      if opts.background ~= DEFAULTS.background then
        params[#params + 1] = 'fill: ' .. opts.background
      end
      scoped_code = '#[\n#block(' .. table.concat(params, ', ') .. ')[\n' .. inner .. '\n]\n]'
    else
      scoped_code = '#[\n' .. inner .. '\n]'
    end
    local result = cell.wrap_crossref(pandoc.RawBlock('typst', scoped_code), opts, REF_TYPE_NAMES)
    if do_echo then
      local echo_block = cell.create_echo_block(code, is_fenced, option_lines)
      return pandoc.Blocks({ echo_block, result })
    end
    return result
  end

  -- Determine image format
  local img_format = opts.format
  if not img_format or not VALID_FORMAT_SET[img_format] then
    img_format = get_image_format_for_output()
  end

  -- Warn about PDF in HTML
  if img_format == 'pdf' and quarto.format.is_html_output() then
    utils.log_warning(
      EXTENSION_NAME,
      'PDF images are not supported in HTML output. Falling back to PNG.'
    )
    img_format = 'png'
  end

  -- Build and compile
  local full_source = build_typst_source(code, opts)
  local img_path = compile_typst(full_source, opts, img_format)

  if not img_path then
    utils.log_warning(EXTENSION_NAME, 'Compilation failed; returning original code block.')
    return el
  end

  local result = cell.wrap_crossref(create_image_element(img_path, opts), opts, REF_TYPE_NAMES)

  local output_location = cell.resolve_output_location(opts, EXTENSION_NAME)
  if output_location then
    local echo_block = do_echo and cell.create_echo_block(code, is_fenced, option_lines) or nil
    return cell.apply_output_location(echo_block, result, output_location)
  end

  if do_echo then
    local echo_block = cell.create_echo_block(code, is_fenced, option_lines)
    return pandoc.Blocks({ echo_block, result })
  end

  return result
end

-- ============================================================================
-- FILTER EXPORT
-- ============================================================================

return {
  { Meta = get_configuration },
  { CodeBlock = process_codeblock },
}
