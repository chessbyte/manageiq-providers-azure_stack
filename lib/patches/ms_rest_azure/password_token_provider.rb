# encoding: utf-8
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See License.txt in the project root for license information.

module MsRestAzure
  #
  # Class that provides access to authentication token based on username & password.
  # You probably want to use this against Azure Stack.
  #
  class PasswordTokenProvider < MsRest::TokenProvider

    private

    TOKEN_ACQUIRE_URL = '{authentication_endpoint}{tenant_id}/oauth2/token'
    REQUEST_BODY_PATTERN = 'resource={resource_uri}&client_id={client_id}&username={username}&password={password}&grant_type=password'
    DEFAULT_SCHEME = 'Bearer'

    # @return [ActiveDirectoryServiceSettings] settings.
    attr_accessor :settings

    # @return [String] tenant id (also known as domain).
    attr_accessor :tenant_id

    # @return [String] application id.
    attr_accessor :client_id

    # @return [String] username.
    attr_accessor :username

    # @return [String] password.
    attr_accessor :password

    # @return [String] auth token.
    attr_accessor :token

    # @return [Time] the date when the current token expires.
    attr_accessor :token_expires_on

    # @return [Integer] the amount of time we refresh token before it expires.
    attr_reader :expiration_threshold

    # @return [String] the type of token.
    attr_reader :token_type

    public

    #
    # Creates and initialize new instance of the PasswordTokenProvider class.
    # @param tenant_id [String] tenant id (also known as domain).
    # @param client_id [String] client id.
    # @param username [String] user's username.
    # @param password [String] user's password.
    # @param settings [ActiveDirectoryServiceSettings] active directory setting.
    def initialize(tenant_id, client_id, username, password, settings = ActiveDirectoryServiceSettings.get_azure_settings)
      fail ArgumentError, 'Tenant id cannot be nil' if tenant_id.nil?
      fail ArgumentError, 'Client id cannot be nil' if client_id.nil?
      fail ArgumentError, 'Username cannot be nil' if username.nil?
      fail ArgumentError, 'Password cannot be nil' if password.nil?
      fail ArgumentError, 'Azure AD settings cannot be nil' if settings.nil?

      @tenant_id = tenant_id
      @client_id = client_id
      @username = username
      @password = password
      @settings = settings

      @expiration_threshold = 5 * 60
    end

    #
    # Returns the string value which needs to be attached
    # to HTTP request header in order to be authorized.
    #
    # @return [String] authentication headers.
    def get_authentication_header
      acquire_token if token_expired
      "#{token_type} #{token}"
    end

    private

    #
    # Checks whether token is about to expire.
    #
    # @return [Bool] True if token is about to expire, false otherwise.
    def token_expired
      @token.nil? || Time.now >= @token_expires_on + expiration_threshold
    end

    #
    # Retrieves a new authentication token.
    #
    # @return [String] new authentication token.
    def acquire_token
      token_acquire_url = TOKEN_ACQUIRE_URL.dup
      token_acquire_url['{authentication_endpoint}'] = @settings.authentication_endpoint
      token_acquire_url['{tenant_id}'] = @tenant_id

      url = URI.parse(token_acquire_url)

      connection = Faraday.new(:url => url, :ssl => MsRest.ssl_options) do |builder|
        builder.adapter Faraday.default_adapter
      end

      request_body = REQUEST_BODY_PATTERN.dup
      request_body['{resource_uri}'] = ERB::Util.url_encode(@settings.token_audience)
      request_body['{client_id}'] = ERB::Util.url_encode(@client_id)
      request_body['{username}'] = ERB::Util.url_encode(@username)
      request_body['{password}'] = ERB::Util.url_encode(@password)

      response = connection.get do |request|
        request.headers['content-type'] = 'application/x-www-form-urlencoded'
        request.body = request_body
      end

      fail AzureOperationError,
        'Couldn\'t login to Azure, please verify your tenant id, client id and username/password' unless response.status == 200

      response_body = JSON.load(response.body)
      @token = response_body['access_token']
      @token_expires_on = Time.at(Integer(response_body['expires_on']))
      @token_type = response_body['token_type']
    end
  end
end
