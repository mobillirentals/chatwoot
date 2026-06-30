# Be sure to restart your server when you modify this file.
# Sessions are used for super_admin dashboard (flash/CSRF) and OAuth flows (OmniAuth state/PKCE).
# Redis session store avoids cookie size limits caused by large OAuth tokens (e.g. Microsoft Entra ID).

secure_cookies = ActiveModel::Type::Boolean.new.cast(ENV.fetch('FORCE_SSL', false))
redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379')

Rails.application.config.session_store :redis_session_store,
                                       key: '_chatwoot_session',
                                       same_site: :lax,
                                       secure: secure_cookies,
                                       httponly: true,
                                       redis: {
                                         expire_after: 1.day,
                                         key_prefix: 'chatwoot:session:',
                                         url: redis_url
                                       }
