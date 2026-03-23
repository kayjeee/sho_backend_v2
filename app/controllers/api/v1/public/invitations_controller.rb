# frozen_string_literal: true

module Api
  module V1
    module Public
      class InvitationsController < ApplicationController
        # POST /api/v1/public/invitations/learner/:token/accept
        def accept_learner_invitation
          accept_invitation
        end

        # POST /api/v1/public/invitations/teacher/:token/accept
        def accept_teacher_invitation
          accept_invitation
        end

        private

        def accept_invitation
          result = UserServices::VerifyInvitationService.new(
            token: params[:token],
            auth0_id: params[:auth0_id]
          ).call

          if result[:success]
            render_success(
              message: 'Invitation accepted successfully',
              data: {
                user: result[:user].to_api_hash,
                invitation: result[:invitation].to_api_hash
              }
            )
          else
            render_error(result[:message], [], status: :unprocessable_entity)
          end
        rescue StandardError => e
          handle_exception(e, "Failed to accept invitation")
        end

        # GET /api/v1/public/invitations/learner/:token
        def show_learner_invitation
          token = params[:token]
          invitation = LearnerInvitation.where(token: token).first

          if invitation
            render_success(data: { invitation: invitation.to_api_hash })
          else
            render_error('Invitation not found', [], status: :not_found)
          end
        end

        # GET /api/v1/public/invitations/teacher/:token
        def show_teacher_invitation
          token = params[:token]
          invitation = TeacherInvitation.find_by_token(token)

          if invitation
            render_success(data: { invitation: invitation.to_api_hash })
          else
            render_error('Invitation not found', [], status: :not_found)
          end
        end
      end
    end
  end
end
