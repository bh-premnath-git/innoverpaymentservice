local cjson = require("cjson")
local kong = kong

local _M = {}

local function join_scope(scopes)
  if type(scopes) ~= "table" then
    return scopes or "openid"
  end

  if #scopes == 0 then
    return "openid"
  end

  return table.concat(scopes, " ")
end

local function ensure_discovery(conf)
  if conf.discovery and conf.discovery ~= "" then
    return conf.discovery
  end

  local issuer = conf.issuer or ""
  if issuer == "" then
    return nil
  end

  if issuer:sub(-1) == "/" then
    return issuer .. ".well-known/openid-configuration"
  end

  return issuer .. "/.well-known/openid-configuration"
end

function _M.get_redirect_uri_path()
  local function drop_query()
    local uri = ngx.var.request_uri
    local x = uri and uri:find("?")
    if x then
      return uri:sub(1, x - 1)
    else
      return uri
    end
  end

  local function tackle_slash(path)
    local args = ngx.req.get_uri_args()
    if args and args.code then
      return path
    elseif path == "/" then
      return "/cb"
    elseif path:sub(-1) == "/" then
      return path:sub(1, -2)
    else
      return path .. "/"
    end
  end

  return tackle_slash(drop_query())
end

function _M.get_options(conf)
  local discovery = ensure_discovery(conf)

  local opts = {
    client_id = conf.client_id,
    client_secret = conf.client_secret,
    discovery = discovery,
    introspection_endpoint = conf.introspection_endpoint,
    timeout = conf.timeout,
    introspection_endpoint_auth_method = conf.introspection_endpoint_auth_method,
    bearer_only = conf.bearer_only and "yes" or "no",
    realm = conf.realm,
    redirect_uri_path = conf.redirect_uri_path or _M.get_redirect_uri_path(),
    scope = join_scope(conf.scopes),
    response_type = conf.response_type,
    ssl_verify = conf.ssl_verify and "yes" or "no",
    token_endpoint_auth_method = conf.token_endpoint_auth_method,
    recovery_page_path = conf.recovery_page_path,
    filters = conf.filters or {},
    logout_path = conf.logout_path,
    redirect_after_logout_uri = conf.redirect_after_logout_uri,
  }

  if conf.audience then
    opts.audience = conf.audience
  end

  return opts
end

function _M.exit(http_status_code, message, kong_status_code)
  kong.response.set_header("Content-Type", "application/json")
  return kong.response.exit(kong_status_code or http_status_code, { message = message })
end

local function normalize_claim_value(value)
  if value == nil then
    return nil
  end

  if type(value) == "table" then
    return table.concat(value, ",")
  end

  return tostring(value)
end

function _M.inject_access_token(access_token)
  if not access_token then
    return
  end

  kong.service.request.set_header("X-Access-Token", access_token)
end

function _M.inject_id_token(id_token)
  if not id_token then
    return
  end

  local token_str = cjson.encode(id_token)
  kong.service.request.set_header("X-ID-Token", ngx.encode_base64(token_str))
end

local function set_header(name, value)
  if not name or name == "" or value == nil then
    return
  end

  kong.service.request.set_header(name, value)
end

function _M.inject_user(user, conf)
  if not user then
    return
  end

  local tmp_user = {}
  for k, v in pairs(user) do
    tmp_user[k] = v
  end
  tmp_user.id = user.sub
  tmp_user.username = user.preferred_username or user.sub
  kong.ctx.shared.authenticated_credential = tmp_user

  local userinfo = cjson.encode(user)
  kong.service.request.set_header("X-Userinfo", ngx.encode_base64(userinfo))

  local claims = conf.upstream_headers_claims or {}
  local names = conf.upstream_headers_names or {}

  for idx, claim in ipairs(claims) do
    local header_name = names[idx]
    local value = normalize_claim_value(user[claim])
    if header_name and value then
      set_header(header_name, value)
    end
  end
end

function _M.has_bearer_access_token()
  local header = kong.request.get_header("Authorization")
  if header then
    local divider = header:find(" ")
    if divider then
      local prefix = header:sub(1, divider - 1)
      if prefix:lower() == "bearer" then
        return true
      end
    end
  end

  return false
end

return _M
