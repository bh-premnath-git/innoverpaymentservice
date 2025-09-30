local kong = kong
local resty_openidc = require("resty.openidc")
local utils = require("kong.plugins.openid-connect.utils")
local filter = require("kong.plugins.openid-connect.filter")
local session = require("kong.plugins.openid-connect.session")

local OpenIDConnectHandler = {
  PRIORITY = 1000,
  VERSION = "1.0.0",
}

local function handle_authentication(conf, oidc_opts)
  if oidc_opts.introspection_endpoint then
    local introspection_res, introspection_err = resty_openidc.introspect(oidc_opts)
    if introspection_err then
      kong.log.err("OIDC introspection error: ", introspection_err)
      if conf.bearer_only then
        return utils.exit(401, introspection_err, 401)
      end
    elseif introspection_res then
      utils.inject_user(introspection_res, conf)
      return
    end
  end

  local res, err = resty_openidc.authenticate(oidc_opts)
  if err then
    if oidc_opts.recovery_page_path then
      kong.log.debug("OIDC redirecting to recovery page", oidc_opts.recovery_page_path)
      return ngx.redirect(oidc_opts.recovery_page_path)
    end

    kong.log.err("OIDC authentication error: ", err)
    return utils.exit(500, err, 500)
  end

  if not res then
    return
  end

  if res.user then
    utils.inject_user(res.user, conf)
  end

  if res.access_token then
    utils.inject_access_token(res.access_token)
  end

  if res.id_token then
    utils.inject_id_token(res.id_token)
  end
end

function OpenIDConnectHandler:access(conf)
  local _, err = session.configure(conf)
  if err then
    kong.log.err(err)
    return utils.exit(500, err, 500)
  end

  local oidc_opts = utils.get_options(conf)

  if not filter.shouldProcessRequest(oidc_opts) then
    kong.log.debug("OIDC plugin ignoring request: ", ngx.var.request_uri)
    return
  end

  handle_authentication(conf, oidc_opts)
end

return OpenIDConnectHandler
