# Unreleased chart changes

The API gateway CORS request-header allowlist includes `DecryptKey`, enabling
the Console's deployment Logs tab to use the existing authenticated log API.
The header is not forwarded to external authentication or exposed in responses.
Installations that override `global.gatewayApi.backend.cors.allowHeaders` must
add `DecryptKey` to their existing list. Authorization and log encryption are
unchanged.
