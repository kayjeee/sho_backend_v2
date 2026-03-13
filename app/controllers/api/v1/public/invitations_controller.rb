# frozen_string_literal: true

module Api
  module V1
    module Public
      class InvitationsController < ApplicationController
        # POST /api/v1/public/invitations/learner/:token/accept
        def accept_learner_invitation
          token = params[:token]
          invitation = LearnerInvitation.where(token: token, status: 'pending').first

          if invitation
            # Forwarding logic or direct implementation
            # For simplicity, we'll reuse the logic from the main controller if possible
            # or implement a standard acceptance flow
            invitation.update(status: 'accepted', accepted_at: Time.current)
            render_success(message: 'Invitation accepted', data: { invitation: invitation.to_api_hash })
          else
            render_error('Invitation not found or already accepted', [], status: :not_found)
          end
        end

        # POST /api/v1/public/invitations/teacher/:token/accept
        def accept_teacher_invitation
          token = params[:token]
          invitation = TeacherInvitation.find_by_token(token)

          if invitation && invitation.status == 'pending'
            invitation.accept!
            render_success(message: 'Invitation accepted', data: { invitation: invitation.to_api_hash })
          else
            render_error('Invitation not found or already accepted', [], status: :not_found)
          end
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
