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
  input = nil,
  echo = false,
  eval = true,
  include = true,
  output = true,
  ['output-location'] = nil,
  classes = nil,
  label = nil,
  pages = 'all',
  ['layout-ncol'] = nil,
}

--- Keys consumed by the filter; any other option is forwarded as an HTML attribute.
local KNOWN_KEYS = {
  cap = true,
  alt = true,
  _block_input = true,
  _inline = true,
  root = true,
  ['font-path'] = true,
  ['package-path'] = true,
}
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

--- Cache base directory within the .quarto scratch directory
local CACHE_BASE = '.quarto/typst-render'

--- Per-document cache subdirectory (set during Meta pass)
local cache_subdir = nil

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

--- Inline counter for auto-numbering inline expressions
local inline_counter = 0

--- Whether the PPTX inline warning has been shown
local pptx_inline_warned = false

--- Set of cache filenames produced or hit during this render (for cleanup)
local used_cache_files = {}

--- Set of image format extensions produced during this render (for cleanup)
local used_cache_formats = {}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

--- Read the entire contents of a file.
--- @param path string The file path to read
--- @return string|nil File contents, or nil if the file cannot be opened
local function read_file(path)
  local f = io.open(path, 'r')
  if not f then
    return nil
  end
  local content = f:read('*a')
  f:close()
  return content
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
  elseif quarto.format.is_typst_output() then
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
    local file_path = utils.resolve_project_path(value)
    local content = read_file(file_path)
    if content then
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

--- Parse a pages specification string into a sorted, deduplicated list of page numbers.
--- Supports: "all", single numbers ("3"), ranges ("1-3"), open-ended ranges ("3-"),
--- and comma-separated combinations ("1,3-5,8").
--- @param pages_str string Pages specification
--- @param total_pages number Total number of pages available
--- @return table List of valid page numbers (sorted, deduplicated)
local function parse_pages(pages_str, total_pages)
  if pages_str == 'all' then
    local result = {}
    for i = 1, total_pages do
      result[i] = i
    end
    return result
  end

  local seen = {}
  local result = {}
  for part in pages_str:gmatch('[^,]+') do
    part = part:match('^%s*(.-)%s*$')
    local lo, hi = part:match('^(%d+)%-(%d+)$')
    if not lo then
      local open_lo = part:match('^(%d+)%-$')
      if open_lo then
        lo = open_lo
        hi = tostring(total_pages)
      else
        local single = part:match('^(%d+)$')
        if single then
          lo = single
          hi = single
        end
      end
    end
    if lo then
      lo = tonumber(lo)
      hi = tonumber(hi)
      for i = lo, hi do
        if i >= 1 and i <= total_pages then
          if not seen[i] then
            seen[i] = true
            result[#result + 1] = i
          end
        else
          utils.log_warning(
            EXTENSION_NAME,
            'Page ' .. tostring(i) .. ' is out of range (1-' .. tostring(total_pages) .. '); skipping.'
          )
        end
      end
    else
      utils.log_warning(
        EXTENSION_NAME,
        'Invalid page specification "' .. part .. '"; skipping.'
      )
    end
  end

  table.sort(result)
  return result
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
local function compute_cache_stem(source, fmt, dpi, label, inline)
  local hash = pandoc.utils.sha1(source .. '|' .. fmt .. '|' .. dpi):sub(1, 8)
  if type(label) == 'string' and label ~= '' then
    return 'typst-' .. label .. '-' .. hash
  end
  if inline then
    inline_counter = inline_counter + 1
    return 'typst-inline-' .. inline_counter .. '-' .. hash
  end
  block_counter = block_counter + 1
  return 'typst-block-' .. block_counter .. '-' .. hash
end

--- Ensure the cache directory exists.
--- @return string|nil Absolute path to the cache directory, or nil on failure
--- @return string|nil Relative path to the cache directory (for image references)
local function ensure_cache_dir()
  if not cache_subdir then
    utils.log_error(EXTENSION_NAME, 'Cache subdirectory not initialised.')
    return nil, nil
  end
  local abs_path = pandoc.path.join({ quarto.project.directory, cache_subdir })
  local ok, err = pcall(pandoc.system.make_directory, abs_path, true)
  if not ok then
    utils.log_error(EXTENSION_NAME, 'Could not create cache directory: ' .. tostring(err))
    return nil, nil
  end
  return abs_path, cache_subdir
end

--- Discover page-numbered output files produced by Typst CLI.
--- Typst generates {stem}1.{ext}, {stem}2.{ext}, ... for PNG/SVG.
--- @param abs_cache string Absolute path to cache directory
--- @param rel_cache string Relative path to cache directory
--- @param stem string File stem (without extension)
--- @param ext string File extension (e.g., "png", "svg")
--- @return table List of relative paths to discovered page files
local function discover_page_files(abs_cache, rel_cache, stem, ext)
  local pages = {}
  local i = 1
  while true do
    local page_name = stem .. tostring(i) .. '.' .. ext
    local page_path = pandoc.path.join({ abs_cache, page_name })
    local f = io.open(page_path, 'r')
    if not f then
      break
    end
    f:close()
    used_cache_files[page_name] = true
    pages[#pages + 1] = pandoc.path.join({ rel_cache, page_name })
    i = i + 1
  end
  return pages
end

--- Compile Typst source to an image file (or multiple files for multi-page output).
--- Uses stdin to pass source code, avoiding temporary .typ files.
--- @param source string Full Typst source code
--- @param opts table Merged options
--- @param img_format string Target image format
--- @return table|nil List of paths to compiled images, or nil on failure
local function compile_typst(source, opts, img_format)
  local bin = resolve_typst_bin()
  if not bin then
    return nil
  end

  local dpi = tostring(opts.dpi)
  if not dpi:match('^%d+$') or tonumber(dpi) <= 0 then
    utils.log_warning(
      EXTENSION_NAME,
      'Invalid dpi value "' .. dpi .. '"; falling back to default (' .. DEFAULTS.dpi .. ').'
    )
    dpi = DEFAULTS.dpi
  end

  -- Merge global and per-block input variables
  local merged_input = merge_inputs(opts.input, opts._block_input)
  local input_serial = serialise_inputs(merged_input)

  -- Include inputs in cache hash material
  local hash_source = source
  if input_serial ~= '' then
    hash_source = source .. '|input:' .. input_serial
  end

  local use_cache = opts.cache ~= false
  local stem = compute_cache_stem(hash_source, img_format, dpi, opts.label, opts._inline)
  local abs_cache, rel_cache = ensure_cache_dir()
  if not abs_cache then
    return nil
  end
  used_cache_formats[img_format] = true

  -- PDF uses a direct output path; PNG/SVG use a page-number template
  -- so Typst CLI can produce one file per page ({stem}{p}.{ext}).
  local is_paged = img_format ~= 'pdf'
  local abs_output, rel_output
  if is_paged then
    abs_output = pandoc.path.join({ abs_cache, stem .. '{p}.' .. img_format })
    rel_output = nil -- not used directly; discover_page_files builds paths
  else
    abs_output = pandoc.path.join({ abs_cache, stem .. '.' .. img_format })
    rel_output = pandoc.path.join({ rel_cache, stem .. '.' .. img_format })
  end

  if use_cache then
    if is_paged then
      local first_page = pandoc.path.join({ abs_cache, stem .. '1.' .. img_format })
      local f = io.open(first_page, 'r')
      if f then
        f:close()
        local pages = discover_page_files(abs_cache, rel_cache, stem, img_format)
        if #pages > 0 then
          return pages
        end
      end
    else
      local f = io.open(abs_output, 'r')
      if f then
        f:close()
        used_cache_files[stem .. '.' .. img_format] = true
        return { rel_output }
      end
    end
  end

  -- Resolve --root: global config or Quarto project directory
  local resolved_root
  if global_config.root then
    resolved_root = utils.resolve_project_path(global_config.root)
  else
    resolved_root = quarto.project.directory
  end

  local args = { 'compile', '--format', img_format, '--ppi', dpi, '--root', resolved_root }

  -- Add --font-path flags (global-only; always a list after get_configuration)
  local font_paths = global_config['font-path']
  if font_paths then
    for _, p in ipairs(font_paths) do
      args[#args + 1] = '--font-path'
      args[#args + 1] = utils.resolve_project_path(p)
    end
  end

  -- Add --package-path if specified (global-only)
  if global_config['package-path'] then
    args[#args + 1] = '--package-path'
    args[#args + 1] = utils.resolve_project_path(global_config['package-path'])
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

  if is_paged then
    -- PNG/SVG: Typst CLI generates {stem}1.{ext}, {stem}2.{ext}, ...
    local pages = discover_page_files(abs_cache, rel_cache, stem, img_format)
    if #pages > 0 then
      return pages
    end
    utils.log_error(EXTENSION_NAME, 'No compiled page files found for stem: ' .. stem)
    return nil
  else
    -- PDF: single file at the exact output path
    local f = io.open(abs_output, 'r')
    if f then
      f:close()
      used_cache_files[stem .. '.' .. img_format] = true
      return { rel_output }
    end
    utils.log_error(EXTENSION_NAME, 'Compiled file not found: ' .. abs_output)
    return nil
  end
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

--- Create a Pandoc element from one or more compiled page images.
--- Single-page output returns a Para; multi-page output returns a Div
--- with optional layout-ncol for Quarto's layout processing.
--- @param page_paths table List of image paths
--- @param opts table Merged options
--- @return pandoc.Block Para (single page) or Div (multiple pages)
local function create_multi_page_element(page_paths, opts)
  if #page_paths == 1 then
    return create_image_element(page_paths[1], opts)
  end

  local blocks = {}
  for _, path in ipairs(page_paths) do
    blocks[#blocks + 1] = create_image_element(path, opts)
  end

  local div_attrs = {}
  if opts['layout-ncol'] then
    div_attrs[#div_attrs + 1] = { 'layout-ncol', tostring(opts['layout-ncol']) }
  end

  return pandoc.Div(blocks, pandoc.Attr('', {}, div_attrs))
end

--- Read an external `.typ` file, resolving relative to the project directory.
--- @param file_opt string Path from the `file` option
--- @return string|nil File contents, or nil on failure
local function read_external_file(file_opt)
  local file_path = utils.resolve_project_path(file_opt)
  local content = read_file(file_path)
  if content then
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

  -- Build per-document cache subdirectory from the input file stem
  local doc_stem = 'default'
  local input_file = quarto.doc.input_file
  if input_file and input_file ~= '' then
    local input_name = pandoc.path.filename(input_file)
    doc_stem = input_name:match('^(.+)%.[^.]+$') or input_name
  end
  cache_subdir = pandoc.path.join({ CACHE_BASE, doc_stem })

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
      'root', 'package-path', 'pages', 'layout-ncol',
    }
    for _, k in ipairs(config_keys) do
      local default_val = DEFAULTS[k]
      if ext_config[k] ~= nil then
        local val = ext_config[k]
        if k == 'cache' then
          if type(val) == 'boolean' then
            global_config[k] = val
          else
            local str = pandoc.utils.stringify(val)
            if str == 'clean' then
              global_config[k] = 'clean'
            else
              global_config[k] = str == 'true'
            end
          end
        elseif k == 'echo' then
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
        elseif k == 'output' then
          if type(val) == 'boolean' then
            global_config[k] = val
          else
            local str = pandoc.utils.stringify(val)
            if str == 'asis' then
              global_config[k] = 'asis'
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

    -- Handle 'font-path' separately: accept a string or list of strings
    if ext_config['font-path'] ~= nil then
      local raw = ext_config['font-path']
      local raw_type = pandoc.utils.type(raw)
      if raw_type == 'List' then
        local paths = {}
        for _, v in ipairs(raw) do
          paths[#paths + 1] = pandoc.utils.stringify(v)
        end
        global_config['font-path'] = paths
      else
        global_config['font-path'] = { pandoc.utils.stringify(raw) }
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

  -- Clear per-document cache when caching is disabled (cache: false).
  -- When cache is true or 'clean', existing files are preserved.
  if global_config.cache == false then
    local abs_cache = pandoc.path.join({ quarto.project.directory, cache_subdir })
    local list_ok, entries = pcall(pandoc.system.list_directory, abs_cache)
    if list_ok then
      for _, filename in ipairs(entries) do
        if filename:match('^typst%-') then
          os.remove(pandoc.path.join({ abs_cache, filename }))
        end
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

  -- Per-block "cache: clean" is not supported; warn and treat as true
  if type(block_opts.cache) == 'string' and block_opts.cache:lower() == 'clean' then
    utils.log_warning(
      EXTENSION_NAME,
      'Per-block "cache: clean" is not supported; treating as "cache: true".'
    )
    opts.cache = true
  elseif opts.cache == 'clean' then
    -- Global 'clean' mode: normalise to true for this block's compilation
    opts.cache = true
  end

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
  if quarto.format.is_typst_output() and output_mode == 'asis' then
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
  if img_format and not VALID_FORMAT_SET[img_format] then
    utils.log_warning(
      EXTENSION_NAME,
      'Invalid format "' .. img_format .. '"; auto-detecting from output format.'
    )
    img_format = nil
  end
  if not img_format then
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
  local all_pages = compile_typst(full_source, opts, img_format)

  if not all_pages then
    utils.log_warning(EXTENSION_NAME, 'Compilation failed; returning error block.')
    local error_block = pandoc.Div(
      pandoc.Blocks({
        pandoc.Para({
          pandoc.Strong({ pandoc.Str('[typst-render] Compilation failed for this block.') }),
        }),
      }),
      pandoc.Attr('', { 'typst-render-error' }, {})
    )
    if do_echo then
      local echo_block = cell.create_echo_block(code, is_fenced, option_lines)
      return pandoc.Blocks({ echo_block, error_block })
    end
    return error_block
  end

  -- Apply page selection
  local selected_pages
  if img_format == 'pdf' and opts.pages ~= 'all' then
    utils.log_warning(
      EXTENSION_NAME,
      'Page selection is not supported for PDF format; embedding the full PDF.'
    )
    selected_pages = all_pages
  else
    local page_indices = parse_pages(opts.pages, #all_pages)
    selected_pages = {}
    for _, idx in ipairs(page_indices) do
      selected_pages[#selected_pages + 1] = all_pages[idx]
    end
  end

  if #selected_pages == 0 then
    utils.log_warning(EXTENSION_NAME, 'No pages matched the selection; returning empty block.')
    return pandoc.Null()
  end

  local result = cell.wrap_crossref(create_multi_page_element(selected_pages, opts), opts, REF_TYPE_NAMES)

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

--- Create a bare inline Image element from a compiled image.
--- Emits format-specific raw markup to size the image to match
--- surrounding text (height: 1em, auto width, vertical centring).
--- @param img_path string Path to the image file
--- @param opts table Merged options
--- @return pandoc.Inline Inline image element
local function create_inline_image_element(img_path, opts)
  if quarto.format.is_typst_output() then
    return pandoc.RawInline(
      'typst',
      '#box(height: 1.1em, baseline: 20%, image("' .. img_path .. '"))'
    )
  end

  if quarto.format.is_latex_output() then
    return pandoc.RawInline(
      'latex',
      '\\raisebox{-0.3em}{\\includegraphics[height=1.3em]{' .. img_path .. '}}'
    )
  end

  if quarto.format.is_docx_output() then
    local img = pandoc.Image(
      { pandoc.Str('typst inline expression') },
      img_path
    )
    img.attr = pandoc.Attr('', {}, { { 'height', '1em' } })
    return img
  end

  if not quarto.format.is_html_output() then
    return pandoc.Image(
      { pandoc.Str('typst inline expression') },
      img_path
    )
  end

  local extra_classes = ''
  if type(opts.classes) == 'string' and opts.classes ~= '' then
    extra_classes = ' ' .. opts.classes
  end

  local style
  if quarto.doc.is_format('revealjs') then
    style = 'height: 1.1em; width: auto; vertical-align: -0.55em;'
  else
    style = 'height: 1.15em; width: auto; vertical-align: -0.35em;'
  end

  return pandoc.RawInline(
    'html',
    '<span class="typst-inline' .. extra_classes .. '">'
    .. '<img src="' .. img_path .. '"'
    .. ' alt="typst inline expression"'
    .. ' style="' .. style .. '"'
    .. '></span>'
  )
end

--- Process a {typst} inline Code element.
--- Compiles inline Typst expressions to tightly-cropped images.
--- @param el pandoc.Code
--- @return pandoc.Inline|pandoc.List|nil
local function process_inline_code(el)
  if not cell.is_inline_code(el) then
    return nil
  end

  if quarto.format.is_powerpoint_output() then
    if not pptx_inline_warned then
      pptx_inline_warned = true
      utils.log_warning(
        EXTENSION_NAME,
        'Inline Typst is not supported for PowerPoint output; '
          .. 'inline code will be kept as-is.'
      )
    end
    return nil
  end

  local code = cell.inline_code_text(el)
  if not code or code:match('^%s*$') then
    return nil
  end

  local opts = cell.merge_options({}, global_config, DEFAULTS)
  opts.width = 'auto'
  opts.height = 'auto'
  opts.margin = '(x: 0.5pt, top: 0.5pt, bottom: 0.25em)'
  opts._inline = true

  local output_mode = cell.resolve_output_mode(opts)

  if output_mode == 'false' then
    return {}
  end

  if output_mode == 'asis' then
    return pandoc.RawInline('typst', code)
  end

  local img_format = opts.format
  if img_format and not VALID_FORMAT_SET[img_format] then
    utils.log_warning(EXTENSION_NAME, 'Invalid inline format "' .. img_format .. '"; auto-detecting.')
    img_format = nil
  end
  if not img_format then
    img_format = get_image_format_for_output()
  end
  if img_format == 'pdf' and quarto.format.is_html_output() then
    img_format = 'png'
  end

  local full_source = build_typst_source(code, opts)
  local pages = compile_typst(full_source, opts, img_format)

  if not pages or #pages == 0 then
    utils.log_warning(EXTENSION_NAME, 'Inline Typst compilation failed.')
    return el
  end

  return create_inline_image_element(pages[1], opts)
end

--- Remove stale cache files after all blocks have been processed.
--- Only runs when global `cache` is `'clean'`. Only removes files whose
--- extension matches a format produced during the current render, so an HTML
--- render (producing `.svg`) will not wipe `.png` files from a previous PDF render.
--- @param doc pandoc.Pandoc
--- @return nil
local function cleanup_cache(doc) -- luacheck: ignore 212
  if global_config.cache ~= 'clean' then
    return nil
  end
  local abs_cache = pandoc.path.join({ quarto.project.directory, cache_subdir })
  local ok, entries = pcall(pandoc.system.list_directory, abs_cache)
  if not ok then
    return nil
  end

  local removed = 0
  for _, filename in ipairs(entries) do
    if filename:match('^typst%-') and not used_cache_files[filename] then
      local ext = filename:match('%.(%w+)$')
      if ext and used_cache_formats[ext] then
        local filepath = pandoc.path.join({ abs_cache, filename })
        local rm_ok, rm_err = os.remove(filepath)
        if rm_ok then
          removed = removed + 1
          utils.log_output(EXTENSION_NAME, 'Removed stale cache file: ' .. filename)
        else
          utils.log_warning(
            EXTENSION_NAME,
            'Could not remove cache file: ' .. filename .. ' (' .. tostring(rm_err) .. ')'
          )
        end
      end
    end
  end

  if removed > 0 then
    utils.log_output(
      EXTENSION_NAME,
      'Cache cleanup: removed ' .. removed .. ' stale file(s).'
    )
  end

  return nil
end

-- ============================================================================
-- FILTER EXPORT
-- ============================================================================

return {
  { Meta = get_configuration },
  { CodeBlock = process_codeblock, Code = process_inline_code },
  { Pandoc = cleanup_cache },
}
