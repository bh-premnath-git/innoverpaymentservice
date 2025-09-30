local typedefs = require "kong.db.schema.typedefs"

local function validate_header_mappings(entity)
  local claims = entity.upstream_headers_claims or {}
  local names = entity.upstream_headers_names or {}

  if #claims ~= #names then
    return nil, "config.upstream_headers_claims and config.upstream_headers_names must contain the same number of values"
  end

  return true
end

return {
  name = "openid-connect",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { issuer = { type = "string", required = true } },
          { discovery = { type = "string" } },
          { client_id = { type = "string", required = true } },
          { client_secret = { type = "string", required = true } },
          { scopes = { type = "array", required = false, default = { "openid" }, elements = { type = "string" } } },
          { audience = { type = "string" } },
          { response_type = { type = "string", required = false, default = "code" } },
          { bearer_only = { type = "boolean", required = false, default = false } },
          { realm = { type = "string", required = false, default = "kong" } },
          { timeout = { type = "integer" } },
          { introspection_endpoint = { type = "string" } },
          { introspection_endpoint_auth_method = { type = "string" } },
          { redirect_uri_path = { type = "string" } },
          { ssl_verify = { type = "boolean", required = false, default = false } },
          { token_endpoint_auth_method = { type = "string", required = false, default = "client_secret_post" } },
          { session_secret = { type = "string" } },
          { recovery_page_path = { type = "string" } },
          { logout_path = { type = "string", required = false, default = "/logout" } },
          { redirect_after_logout_uri = { type = "string", required = false, default = "/" } },
          { filters = { type = "array", required = false, default = {}, elements = { type = "string" } } },
          { upstream_headers_claims = { type = "array", required = false, default = {}, elements = { type = "string" } } },
          { upstream_headers_names = { type = "array", required = false, default = {}, elements = { type = "string" } } },
        },
        entity_checks = {
          { custom_entity_check = {
              field_sources = { "upstream_headers_claims", "upstream_headers_names" },
              fn = validate_header_mappings,
            },
          },
        },
      },
    },
  },
}
