# Vendored OpenID Connect Kong Plugin

This directory vendors a lightly adapted version of the Nokia "kong-oidc" plugin so the build no longer needs to clone the upstream repository at image build time.  The code has been updated to:

* run without the deprecated `BasePlugin` helper (compatible with modern Kong versions),
* expose the plugin under the `openid-connect` name, and
* support mapping configured claims onto upstream headers used by the stack.

The original project is available at https://github.com/nokia/kong-oidc and is distributed under the Apache 2.0 License (see `LICENSE`).
