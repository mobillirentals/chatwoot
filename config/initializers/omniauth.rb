# OmniAuth configuration
# Sets the full host URL for callbacks and proper redirect handling
OmniAuth.config.full_host = ENV.fetch('FRONTEND_URL', 'http://localhost:3000')

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2, ENV.fetch('GOOGLE_OAUTH_CLIENT_ID', nil), ENV.fetch('GOOGLE_OAUTH_CLIENT_SECRET', nil), {
    provider_ignores_state: true
  }

  azure_client_id = InstallationConfig.find_by(name: 'AZURE_CLIENT_ID')&.value.presence
  azure_client_secret = InstallationConfig.find_by(name: 'AZURE_CLIENT_SECRET')&.value.presence
  if azure_client_id && azure_client_secret
    provider :entra_id,
             client_id: azure_client_id,
             client_secret: azure_client_secret,
             tenant_id: InstallationConfig.find_by(name: 'AZURE_TENANT_ID')&.value.presence || 'common',
             provider_ignores_state: true
  end
end
