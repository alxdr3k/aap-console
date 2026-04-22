# Sets required environment variables for external service clients in test environment.
# All HTTP calls are blocked by WebMock, so these are dummy values.
ENV["KEYCLOAK_URL"] ||= "http://keycloak.test"
ENV["KEYCLOAK_REALM"] ||= "aap"
ENV["KEYCLOAK_CLIENT_ID"] ||= "aap-console"
ENV["KEYCLOAK_CLIENT_SECRET"] ||= "test-client-secret"
ENV["LANGFUSE_URL"] ||= "http://langfuse.test"
ENV["LANGFUSE_SERVICE_EMAIL"] ||= "service@console.test"
ENV["LANGFUSE_SERVICE_PASSWORD"] ||= "test-password"
ENV["CONFIG_SERVER_URL"] ||= "http://config-server.test"
ENV["CONFIG_SERVER_API_KEY"] ||= "test-config-api-key"
ENV["CONSOLE_INBOUND_API_KEY"] ||= "test-inbound-api-key"
