# app/controllers/api/v1/learner_links_controller.rb
module Api::V1
  class LearnerLinksController < ApplicationController
    include Secured
    before_action :authorize

    # POST /api/v1/learner_links
    # Assigns a learner to the currently authenticated user.
    def create
      if params[:accession_number].blank? || params[:school_id].blank?
        return render json: { error: 'accession_number and school_id are required' }, status: :unprocessable_entity
      end

      learner = Learner.find_by(
        accession_number: params[:accession_number],
        school_id: BSON::ObjectId.from_string(params[:school_id])
      )

      return render json: { error: 'Learner not found' }, status: :not_found unless learner

      current_user_auth0_id = @decoded_token.token['sub']

      # Check if the learner is already linked to this parent (checking both legacy fields).
      if [learner.try(:auth0Id), learner.try(:userAuth0Id)].include?(current_user_auth0_id)
        return render json: { message: 'Learner already linked to your account' }, status: :ok
      end

      # Check if the learner is already assigned to a different parent.
      if learner.try(:auth0Id).present? || learner.try(:userAuth0Id).present?
        return render json: { error: 'Learner is already assigned to another parent' }, status: :conflict
      end

      # Correctly assign the learner to the current user by updating the `auth0Id` field.
      if learner.update(auth0Id: current_user_auth0_id)
        render json: { message: 'Learner linked successfully' }, status: :created
      else
        render json: { error: 'Failed to link learner', details: learner.errors.full_messages }, status: :unprocessable_entity
      end
    end
  end
end
