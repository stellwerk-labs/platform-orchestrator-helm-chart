# Unreleased chart changes

The API gateway CORS request-header allowlist includes `DecryptKey` for
compatible caller-owned log-key clients. The header is not forwarded to external
authentication or exposed in responses. Installations with a custom
`global.gatewayApi.backend.cors.allowHeaders` list can add this header if they
need browser clients that submit their own key.

The upcoming Console Logs tab uses automatic server-managed decryption and does
not send a `DecryptKey` header. It requires matching IAM, Data Plane and Control
Plane components with the dedicated `deployment_logs_read` permission. Existing
Viewer, Deployer and metadata-read grants do not grant decrypted log contents.
This permission and key-custody change is implemented by those components, not
by a CORS setting.
