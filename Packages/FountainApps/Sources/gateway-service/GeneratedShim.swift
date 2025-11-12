// Minimal shim to ensure SPM builds the gateway-service target even when
// only OpenAPI generation is present. The actual API protocol/types are
// provided by the Swift OpenAPI generator at build time.
public enum GatewayServiceShim {}

