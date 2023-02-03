# frozen_string_literal: true

module Gitlab
  class OmniauthInitializer
    OAUTH2_TIMEOUT_SECONDS = 10
    ConfigurationError = Class.new(StandardError)

    def initialize(devise_config)
      @devise_config = devise_config
    end

    def execute(providers)
      providers.each do |provider|
        name = provider['name'].to_sym

        add_provider_to_devise(name, *arguments_for(provider))
        setup_provider(name)
      end
    end

    class << self
      def default_arguments_for(provider_name)
        case provider_name
        when 'cas3'
          { on_single_sign_out: cas3_signout_handler }
        when 'authentiq'
          { remote_sign_out_handler: authentiq_signout_handler }
        when 'shibboleth'
          { fail_with_empty_uid: true }
        when 'google_oauth2'
          { client_options: { connection_opts: { request: { timeout: OAUTH2_TIMEOUT_SECONDS } } } }
        when 'gitlab'
          {
            authorize_params: { gl_auth_type: 'login' }
          }
        else
          {}
        end
      end

      def full_host
        proc { |_env| Settings.gitlab['base_url'] }
      end

      private

      def cas3_signout_handler
        lambda do |request|
          ticket = request.params[:session_index]
          raise "Service Ticket not found." unless Gitlab::Auth::OAuth::Session.valid?(:cas3, ticket)

          Gitlab::Auth::OAuth::Session.destroy(:cas3, ticket)
          true
        end
      end

      def authentiq_signout_handler
        lambda do |request|
          authentiq_session = request.params['sid']
          if Gitlab::Auth::OAuth::Session.valid?(:authentiq, authentiq_session)
            Gitlab::Auth::OAuth::Session.destroy(:authentiq, authentiq_session)
            true
          else
            false
          end
        end
      end
    end

    private

    def add_provider_to_devise(...)
      @devise_config.omniauth(...)
    end

    def arguments_for(provider)
      provider_arguments = []

      %w[app_id app_secret].each do |argument|
        provider_arguments << provider[argument] if provider[argument]
      end

      arguments = provider.fetch('args', {})
      defaults = provider_defaults(provider)

      case arguments
      when Array
        # An Array from the configuration will be expanded
        provider_arguments.concat arguments
        provider_arguments << defaults unless defaults.empty?
      when Hash
        hash_arguments = arguments.deep_symbolize_keys.deep_merge(defaults)
        normalized = normalize_hash_arguments(hash_arguments)

        # A Hash from the configuration will be passed as is.
        provider_arguments << normalized unless normalized.empty?
      else
        # this will prevent the application from starting in development mode.
        # we still set defaults, and let the application start in prod.
        Gitlab::ErrorTracking.track_and_raise_for_dev_exception(
          ConfigurationError.new("Arguments were provided for #{provider['name']}, but not as an array or a hash"),
          provider_name: provider['name'],
          arguments_type: arguments.class.name
        )
        provider_arguments << defaults unless defaults.empty?
      end

      provider_arguments
    end

    def normalize_hash_arguments(args)
      args.deep_symbolize_keys!

      # Rails 5.1 deprecated the use of string names in the middleware
      # (https://github.com/rails/rails/commit/83b767ce), so we need to
      # pass in the actual class to Devise.
      if args[:strategy_class].is_a?(String)
        args[:strategy_class] = args[:strategy_class].constantize
      end

      args
    end

    def provider_defaults(provider)
      self.class.default_arguments_for(provider['name'])
    end

    def omniauth_customized_providers
      @omniauth_customized_providers ||= build_omniauth_customized_providers
    end

    # We override this in EE
    def build_omniauth_customized_providers
      %i[bitbucket jwt]
    end

    def setup_provider(provider)
      case provider
      when *omniauth_customized_providers
        require_dependency "omni_auth/strategies/#{provider}"
      end
    end
  end
end

Gitlab::OmniauthInitializer.prepend_mod_with('Gitlab::OmniauthInitializer')
