# app/services/user_services/create_user_service.rb
module UserServices
  class CreateUserService
    PROVIDERS = %w[google-oauth2 auth0 facebook twitter].freeze

    # Entry point
    def self.call(user_params:)
      new(user_params: user_params).call
    end

    def initialize(user_params)
      # Gracefully handle both keyword args (user_params: ...) and raw params
      params_hash = user_params.is_a?(Hash) && user_params.key?(:user_params) ? user_params[:user_params] : user_params
      @params = normalize_params(params_hash)
      validate_params!
      freeze
    end

    def call
      user = find_user
      return update_user(user) if user

      create_user
    rescue BSON::Error::InvalidObjectId, Mongoid::Errors::DocumentNotFound, Mongoid::Errors::InvalidFind => e
      Rails.logger.warn "⚠️ CreateUserService: Mongoid/BSON error during lookup: #{e.message}"
      Result.failure(e.message)
    rescue => e
      Rails.logger.error "💥 CreateUserService failed: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      Result.failure(e.message)
    end

    private

    attr_reader :params

    def normalize_params(raw_params)
      allowed_fields = %i[name email auth0_id roles]
      hash = raw_params.is_a?(ActionController::Parameters) ? raw_params.to_h : raw_params
      hash.deep_symbolize_keys.slice(*allowed_fields).freeze
    end

    def validate_params!
      errors = []
      errors << "auth0_id is required" if params[:auth0_id].blank?
      errors << "email is required" if params[:email].blank?
      raise ArgumentError, errors.join(", ") if errors.any?
    end

    def find_user
      find_by_auth0_id || find_by_prefixed_auth0_id || find_by_email
    end

    def find_by_auth0_id
      return nil if params[:auth0_id].blank?
      User.where(auth0_id: params[:auth0_id]).first
    end

    def find_by_prefixed_auth0_id
      return nil if params[:auth0_id].blank? || params[:auth0_id].include?('|')

      PROVIDERS.each do |provider|
        user = User.where(auth0_id: "#{provider}|#{params[:auth0_id]}").first
        return user if user
      end
      nil
    end

    def find_by_email
      return nil if params[:email].blank?
      User.where(email: params[:email]).first
    end

    def update_user(user)
      attributes = updatable_attributes
      return Result.success(user, new_record: false) if attributes.empty?

      user.assign_attributes(attributes)
      if user.save
        Result.success(user, new_record: false)
      else
        Result.failure(user.errors.full_messages)
      end
    end

    def updatable_attributes
      params.except(:auth0_id, :email).freeze
    end

    def create_user
      user = User.new(params)
      if user.save
        Result.success(user, new_record: true)
      else
        Result.failure(user.errors.full_messages)
      end
    end
  end

  # Standard Result Object returning success?/failure? and target payloads
  class Result
    attr_reader :user, :errors, :new_record

    def initialize(success:, user: nil, errors: [], new_record: false)
      @success = success
      @user = user
      @errors = errors
      @new_record = new_record
    end

    def self.success(user, new_record: false)
      new(success: true, user: user, new_record: new_record)
    end

    def self.failure(errors)
      new(success: false, errors: Array.wrap(errors))
    end

    def success?
      @success
    end

    def failure?
      !@success
    end
  end
end
