-- appendurl - Tsubajashi

local utils = require 'mp.utils'
local msg = require 'mp.msg'

local function get_os()
  local dir_sep = package.config:sub(1,1)

  -- Windows uses backslash as directory separator
  if dir_sep == "\\" then
      return "windows"
  end

  -- Check for macOS using uname
  local handle = io.popen("uname")
  local result = handle:read("*a")
  handle:close()

  result = result:lower()

  if result:find("darwin") then
      return "macos"
  else
      return "linux"
  end
end

local platform = get_os()

--main function
function append(primaryselect)
  local clipboard = get_clipboard(primaryselect or false)
  if clipboard then
    mp.commandv("loadfile", clipboard, "append-play")
    mp.osd_message("URL appended: "..clipboard)
    msg.info("URL appended: "..clipboard)
  end
end

--handles the subprocess response table and return clipboard if it was a success
function handleres(res, args, primary)
  if not res.error and res.status == 0 then
      return res.stdout
  else
    --if clipboard failed try primary selection
    if platform=='linux' and not primary then
      append(true)
      return nil
    end
    msg.error("There was an error getting "..platform.." clipboard: ")
    msg.error("  Status: "..(res.status or ""))
    msg.error("  Error: "..(res.error or ""))
    msg.error("  stdout: "..(res.stdout or ""))
    msg.error("args: "..utils.to_string(args))
    return nil
  end
end

function get_clipboard(primary)
  if platform == 'linux' then
    local args = { 'xclip', '-selection', primary and 'primary' or 'clipboard', '-out' }
    return handleres(utils.subprocess({ args = args }), args, primary)
  elseif platform == 'windows' then
    local args = {
      'powershell', '-NoProfile', '-Command', [[& {
        Trap {
          Write-Error -ErrorRecord $_
          Exit 1
        }

        $clip = ""
        if (Get-Command "Get-Clipboard" -errorAction SilentlyContinue) {
          $clip = Get-Clipboard -Raw -Format Text -TextFormatType UnicodeText
        } else {
          Add-Type -AssemblyName PresentationCore
          $clip = [Windows.Clipboard]::GetText()
        }

        $clip = $clip -Replace "`r",""
        $u8clip = [System.Text.Encoding]::UTF8.GetBytes($clip)
        [Console]::OpenStandardOutput().Write($u8clip, 0, $u8clip.Length)
      }]]
    }
    return handleres(utils.subprocess({ args =  args }), args)
  elseif platform == 'macos' then
    local args = { 'pbpaste' }
    return handleres(utils.subprocess({ args = args }), args)
  end
  return nil
end

mp.add_key_binding("ctrl+v", "appendURL", append)
