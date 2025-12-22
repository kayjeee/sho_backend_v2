# app/controllers/api/v1/my_learners_controller.rb
module Api::V1
  class MyLearnersController < ApplicationController
    skip_before_action :authenticate_user!, raise: false

    before_action :set_user
    before_action :find_learners

    def index
      render json: { learners: @learners.map(&:to_api_hash), learner_count: @learners.count }, status: :ok
    end

    def profile
      render json: { parent: @user.to_api_hash, learner_count: @learners.count }, status: :ok
    end

    private

    def set_user
      @user = User.find_by(auth0_id: params[:auth0_id])
      render json: { error: 'Parent not found' }, status: :not_found and return unless @user
    end

    def find_learners
      return unless @user

      # Convert ObjectIds to strings (critical fix!)
      school_id_strings = @user.school_ids.map(&:to_s)

      # CORRECT QUERY: Only use parent_auth0_ids for parent-child relationship
      # This returns 11 learners, not 89+
      @learners = Learner.active.where(
        :parent_auth0_ids.in => [@user.auth0_id],
        :school_id.in => school_id_strings
      )

      # Debug info
      Rails.logger.info "=== MyLearners Query ==="
      Rails.logger.info "Parent: #{@user.auth0_id}"
      Rails.logger.info "Schools: #{school_id_strings}"
      Rails.logger.info "Found: #{@learners.count} learners"

      # Log each learner found
      @learners.each do |learner|
        Rails.logger.info "  - #{learner.firstName} #{learner.lastName}"
        Rails.logger.info "    parent_auth0_ids: #{learner.parent_auth0_ids.inspect}"
        Rails.logger.info "    school_id: #{learner.school_id}"
      end
    end
  end
end
