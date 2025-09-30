local _M = {}

function _M.configure(conf)
  if conf.session_secret then
    local decoded_session_secret = ngx.decode_base64(conf.session_secret)
    if not decoded_session_secret then
      return nil, "invalid OIDC plugin configuration, session secret could not be decoded"
    end
    ngx.var.session_secret = decoded_session_secret
  end

  return true
end

return _M
