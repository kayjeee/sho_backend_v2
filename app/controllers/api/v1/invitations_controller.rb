# app/controllers/api/v1/invitations_controller.rb
class Api::V1::InvitationsController < ApplicationController
  include Secured

  before_action :validate_params, only: [:create]

  def create
    Rails.logger.info "🔹 [InvitationsController#create] Starting invitation creation"
    Rails.logger.info "🔹 [InvitationsController#create] Params: #{params.inspect}"
    Rails.logger.info "🔹 [InvitationsController#create] Current user: #{current_user&.id}"

    begin
      invitation_service = UserServices::InvitationService.new(
        sender: current_user,
        recipient_phone_number: params[:phone_number],
        school_id: params[:school_id],
        role: params[:role]
      )
      
      invitation = invitation_service.call

      if invitation.persisted?
        Rails.logger.info "✅ [InvitationsController#create] Invitation created successfully: #{invitation.id}"
        render json: { 
          success: true, 
          message: 'Invitation sent successfully.',
          invitation: {
            id: invitation.id.to_s,
            token: invitation.token,
            recipient_phone_number: invitation.recipient_phone_number,
            status: invitation.status
          }
        }, status: :created
      else
        Rails.logger.error "❌ [InvitationsController#create] Invitation failed: #{invitation.errors.full_messages}"
        render json: { 
          success: false, 
          errors: invitation.errors.full_messages 
        }, status: :unprocessable_entity
      end

    rescue => e
      Rails.logger.error "💥 [InvitationsController#create] Unexpected error: #{e.message}"
      Rails.logger.error "💥 [InvitationsController#create] Backtrace: #{e.backtrace.first(10).join("\n")}"
      
      render json: { 
        success: false, 
        errors: ["Internal server error: #{e.message}"] 
      }, status: :internal_server_error
    end
  end

  private

  def validate_params
    Rails.logger.info "🔹 [InvitationsController#validate_params] Validating parameters"
    
    required_params = [:phone_number, :school_id, :role]
    missing_params = required_params.select { |param| params[param].blank? }

    if missing_params.any?
      error_message = "Missing parameters: #{missing_params.join(', ')}"
      Rails.logger.error "❌ [InvitationsController#validate_params] #{error_message}"
      render json: { success: false, errors: error_message }, status: :unprocessable_entity
    else
      Rails.logger.info "✅ [InvitationsController#validate_params] All required parameters present"
    end
  end
end