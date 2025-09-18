module Api
  module V1
    class InvitesController < ApplicationController
      before_action :set_invite, only: [:show, :update, :destroy]

      # POST /api/v1/invites
      def create
        current_user = User.find_by(auth0_id: params[:invite][:auth0_id]) rescue nil
        result = InviteServices::CreateInviteService.new(invite_params.except(:auth0_id), current_user).call

        if result[:success]
          render json: { success: true, invite: result[:invite] }, status: :created
        else
          render json: { success: false, errors: result[:errors] }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/invites/:id
      def show
        render json: @invite, status: :ok
      end

      # PUT /api/v1/invites/:id
      def update
        result = InviteServices::UpdateInviteService.new(@invite, invite_params).call

        if result[:success]
          render json: { success: true, invite: result[:invite] }, status: :ok
        else
          render json: { success: false, errors: result[:errors] }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/invites/:id
 def destroy
  result = InviteServices::DestroyInviteService.new(@invite).call

  if result[:success]
    render json: { success: true, message: "Invite deleted successfully" }, status: :ok
  else
    render json: { success: false, errors: result[:errors] }, status: :unprocessable_entity
  end
end


      private

      def set_invite
        @invite = Invite.find(params[:id])
      rescue Mongoid::Errors::DocumentNotFound
        render json: { success: false, message: "Invite not found" }, status: :not_found
      end

      def invite_params
        params.require(:invite).permit(
          :recipient_type,
          :recipient_name,
          :recipient_email,
          :recipient_phone,
          :custom_message,
          :expires_at,
          :school_id,
          :grade_id,
          :message,
          :auth0_id,
          :status,
          :accepted_at,
          channels: [],
          metadata: {}
        )
      end
    end
  end
end
