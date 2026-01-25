# app/services/user_services/create_user_service.rb
# frozen_string_literal: true

module UserServices
  class CreateUserService
    PROVIDERS = %w[google-oauth2 auth0 facebook twitter].freeze

    # ----------------------------
    # Entry point
    # ----------------------------
    def self.call(user_params:)
      new(user_params).call
    end

    # ----------------------------
    # Initialize with normalized params
    # ----------------------------
    def initialize(user_params)
      @params = normalize_params(user_params)
      validate_params!
      freeze # Ensure immutability after initialization
    end

    # ----------------------------
    # Main call
    # ----------------------------
    def call
      user = find_user
      return update_user(user) if user

      create_user
    rescue => e
      Rails.logger.error "💥 CreateUserService failed: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      Result.failure(e.message)
    end

    private

    attr_reader :params

    # ----------------------------
    # Normalize and sanitize input
    # ----------------------------
    def normalize_params(raw_params)
      allowed_fields = %i[name email auth0_id roles]

      # Convert to Hash if ActionController::Parameters
      hash = raw_params.is_a?(ActionController::Parameters) ? raw_params.to_h : raw_params
      # Deep symbolize all keys and slice only allowed fields
      hash.deep_symbolize_keys.slice(*allowed_fields).freeze
    end

    # ----------------------------
    # Validate required params
    # ----------------------------
    def validate_params!
      Rails.logger.debug "Validating params: #{params.inspect}"

      errors = []
      errors << "auth0_id is required" if params[:auth0_id].blank?
      errors << "email is required" if params[:email].blank?

      raise ArgumentError, errors.join(", ") if errors.any?
    end

    # ----------------------------
    # Find existing user
    # ----------------------------
    def find_user
      # First try by exact auth0_id
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

    # ----------------------------
    # Update existing user
    # ----------------------------
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

    # Only allow updating safe fields
    def updatable_attributes
      # auth0_id and email are immutable after creation
      params.except(:auth0_id, :email).freeze
    end

    # ----------------------------
    # Create new user
    # ----------------------------
    def create_user
      user = User.new(params)
      if user.save
        Result.success(user, new_record: true)
      else
        Result.failure(user.errors.full_messages)
      end
    end
  end
end

# ----------------------------
# Simple Result object for success/failure
# ----------------------------
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
