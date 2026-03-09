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
local validation = require(quarto.utils.resolve_path('_modules/validation.lua'):gsub('%.lua$', ''))

-- ============================================================================
-- CONSTANTS
-- ============================================================================

--- Valid image formats
local VALID_FORMATS = { 'png', 'svg', 'pdf' }

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
  echo = false,
  eval = true,
  label = nil,
}

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

--- Parse comment+pipe options from Typst code block text.
--- comment+pipe lines use `//| key: value` syntax.
--- @param text string The raw code block text
--- @return table Options table
--- @return string Cleaned code with comment+pipe lines removed
--- @return table Raw comment+pipe lines for fenced echo output
local function parse_block_options(text)
  local opts = {}
  local code_lines = {}
  local option_lines = {}
  local in_commentpipe = true

  for line in text:gmatch('[^\r\n]*') do
    if in_commentpipe then
      local key, value = line:match('^%s*//|%s*([%w%-]+):%s*(.+)%s*$')
      if key then
        value = utils.trim(value)
        if value == 'true' then
          opts[key] = true
        elseif value == 'false' then
          opts[key] = false
        else
          -- Strip surrounding quotes from string values
          local unquoted = value:match('^"(.*)"$') or value:match("^'(.*)'$")
          opts[key] = unquoted or value
        end
        option_lines[#option_lines + 1] = line
      else
        in_commentpipe = false
        code_lines[#code_lines + 1] = line
      end
    else
      code_lines[#code_lines + 1] = line
    end
  end

  return opts, table.concat(code_lines, '\n'), option_lines
end

--- Merge options with priority: block comment+pipe > global YAML > defaults.
--- @param block_opts table Per-block comment+pipe options
--- @return table Merged options
local function merge_options(block_opts)
  local merged = {}
  for k, v in pairs(DEFAULTS) do
    merged[k] = v
  end
  for k, v in pairs(global_config) do
    merged[k] = v
  end
  for k, v in pairs(block_opts) do
    merged[k] = v
  end
  return merged
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
    local file_path = value
    if quarto.project and quarto.project.directory then
      local abs_check = io.open(file_path, 'r')
      if not abs_check then
        file_path = pandoc.path.join({ quarto.project.directory, file_path })
      else
        abs_check:close()
      end
    end
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
  if label and label ~= '' then
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
  local use_cache = opts.cache ~= false
  local stem = compute_cache_stem(source, img_format, dpi, opts.label)
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

  local abs_input = pandoc.path.join({ abs_cache, stem .. '.typ' })
  local f = io.open(abs_input, 'w')
  if not f then
    utils.log_error(EXTENSION_NAME, 'Could not write temporary Typst file: ' .. abs_input)
    return nil
  end
  f:write(source)
  f:close()

  local args = { 'compile', '--format', img_format, '--ppi', dpi, abs_input, abs_output }

  local ok, result = pcall(pandoc.pipe, bin, args, '')
  if not ok then
    utils.log_error(
      EXTENSION_NAME,
      'Typst compilation failed:\n' .. tostring(result)
    )
    os.remove(abs_input)
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
      os.remove(abs_input)
      return nil
    end
  else
    out_f:close()
  end

  os.remove(abs_input)

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

--- Extract the cross-reference type prefix from a label (e.g., "fig" from "fig-foo").
--- @param label string The label string
--- @return string|nil The prefix, or nil if no valid ref type
local function ref_type(label)
  return label:match('^(%a+)%-')
end

--- Resolve the caption text for a labelled block.
--- Looks for `<prefix>-cap` first (e.g., `fig-cap`, `tbl-cap`), then falls back
--- to a generic `cap` key.
--- @param opts table Merged options
--- @param prefix string|nil The cross-reference type prefix
--- @return string Caption text (may be empty)
local function resolve_caption(opts, prefix)
  if prefix and opts[prefix .. '-cap'] then
    return opts[prefix .. '-cap']
  end
  if opts['cap'] then
    return opts['cap']
  end
  return ''
end

--- Resolve the alt text for a labelled block.
--- Looks for `<prefix>-alt` first, then falls back to generic `alt`, then to
--- the provided fallback (typically the caption).
--- @param opts table Merged options
--- @param prefix string|nil The cross-reference type prefix
--- @param fallback string Fallback text if no alt is found
--- @return string Alt text
local function resolve_alt(opts, prefix, fallback)
  if prefix and opts[prefix .. '-alt'] then
    return opts[prefix .. '-alt']
  end
  if opts['alt'] then
    return opts['alt']
  end
  return fallback
end

--- Wrap a content block in a quarto.FloatRefTarget if a cross-ref label is present.
--- Supports any Quarto cross-reference type (fig-, tbl-, lst-, etc.).
--- @param content pandoc.Block The content block (Para with image, RawBlock, etc.)
--- @param opts table Merged options
--- @return pandoc.Block FloatRefTarget or the original content block
local function wrap_crossref(content, opts)
  local label = opts.label or ''
  local prefix = ref_type(label)

  if prefix == nil then
    return content
  end

  local caption_text = resolve_caption(opts, prefix)
  local caption_inlines = {}
  if caption_text ~= '' then
    caption_inlines = quarto.utils.string_to_inlines(caption_text)
  end

  local ref_type_name = REF_TYPE_NAMES[prefix] or (prefix:sub(1, 1):upper() .. prefix:sub(2))

  return quarto.FloatRefTarget({
    identifier = label,
    type = ref_type_name,
    content = pandoc.Blocks({ content }),
    caption_long = pandoc.Blocks({ pandoc.Plain(caption_inlines) }),
  })
end

--- Create a Pandoc Image element from a compiled image.
--- @param img_path string Path to the image file
--- @param opts table Merged options
--- @return pandoc.Para Para containing the image
local function create_image_element(img_path, opts)
  local label = opts.label or ''
  local prefix = ref_type(label)
  local caption_text = resolve_caption(opts, prefix)
  local alt_text = resolve_alt(opts, prefix, caption_text)

  local img = pandoc.Image(
    { pandoc.Str(alt_text) },
    img_path,
    '',
    pandoc.Attr('', {}, {})
  )

  return pandoc.Para({ img })
end

--- Read an external `.typ` file, resolving relative to the project directory.
--- @param file_opt string Path from the `file` option
--- @return string|nil File contents, or nil on failure
local function read_external_file(file_opt)
  local file_path = file_opt
  if quarto.project and quarto.project.directory then
    local abs_check = io.open(file_path, 'r')
    if not abs_check then
      file_path = pandoc.path.join({ quarto.project.directory, file_path })
    else
      abs_check:close()
    end
  end
  local f = io.open(file_path, 'r')
  if f then
    local content = f:read('*a')
    f:close()
    return content
  end
  utils.log_error(EXTENSION_NAME, 'Could not read file: ' .. file_opt)
  return nil
end

--- Check if a CodeBlock is a {typst} block.
--- Handles both `typst` (standard Pandoc class) and `{typst}` (Quarto markdown engine literal).
--- @param el pandoc.CodeBlock
--- @return boolean
local function is_typst_block(el)
  return el.classes:includes('typst') or el.classes:includes('{typst}')
end

--- Create a source code listing block.
--- When fenced is true, wraps the code with ` ```{typst} ` markers and
--- comment+pipe options to mimic Quarto's `echo: fenced` presentation.
--- @param code string The Typst source code
--- @param fenced boolean Whether to show fenced code block markers
--- @param option_lines table|nil Raw comment+pipe lines to include in fenced output
--- @return pandoc.CodeBlock A code block for syntax highlighting
local function create_echo_block(code, fenced, option_lines)
  if fenced then
    local lines = { '```{typst}' }
    if option_lines then
      for _, line in ipairs(option_lines) do
        if not line:match('^%s*//|%s*echo:%s*') then
          lines[#lines + 1] = line
        end
      end
    end
    lines[#lines + 1] = code
    lines[#lines + 1] = '```'
    return pandoc.CodeBlock(table.concat(lines, '\n'), pandoc.Attr('', { 'markdown' }, {}))
  end
  return pandoc.CodeBlock(code, pandoc.Attr('', { 'typst' }, {}))
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
    local key = entry['key'] and utils.stringify(entry['key'])
    local name = entry['reference-prefix'] and utils.stringify(entry['reference-prefix'])
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
      'preamble', 'cache', 'echo', 'eval',
    }
    for _, k in ipairs(config_keys) do
      local default_val = DEFAULTS[k]
      if ext_config[k] ~= nil then
        local val = ext_config[k]
        if k == 'echo' then
          if type(val) == 'boolean' then
            global_config[k] = val
          else
            local str = utils.stringify(val)
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
            local str = utils.stringify(val)
            global_config[k] = str == 'true'
          end
        else
          global_config[k] = utils.stringify(val)
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
  if not is_typst_block(el) then
    return nil
  end

  local block_opts, clean_code, option_lines = parse_block_options(el.text)
  local opts = merge_options(block_opts)

  local do_eval = opts.eval ~= false
  local do_echo = opts.echo == true or opts.echo == 'fenced'
  local is_fenced = opts.echo == 'fenced'

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
    return create_echo_block(code, is_fenced, option_lines)
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
    local result = wrap_crossref(pandoc.RawBlock('typst', scoped_code), opts)
    if do_echo then
      local echo_block = create_echo_block(code, is_fenced, option_lines)
      return pandoc.Blocks({ echo_block, result })
    end
    return result
  end

  -- Determine image format
  local img_format = opts.format
  if not img_format or not validation.in_array(img_format, VALID_FORMATS) then
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

  local result = wrap_crossref(create_image_element(img_path, opts), opts)

  if do_echo then
    local echo_block = create_echo_block(code, is_fenced, option_lines)
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
