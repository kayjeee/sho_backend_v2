# app/controllers/api/v1/my_learners_controller.rb
class Api::V1::MyLearnersController < ApplicationController
  include Secured
  before_action :authorize

  # GET /api/v1/my_learners
  #
  # Returns a list of learners explicitly linked to the current user.
  # This is the primary, secure endpoint for a user to fetch their learners.
  def index
    # 1. The `before_action :authorize` ensures the user is authenticated.
    #    The `authorize` method from the `Secured` concern decodes the token
    #    and stores the payload in the `@decoded_token` instance variable.

    # 2. Get the current user's auth0_id from the 'sub' (subject) claim of the token.
    current_user_auth0_id = @decoded_token.token['sub']

    # 3. Find all learners that have this user's auth0_id in their `parent_auth0_ids` array.
    #    - This query is secure because it ONLY looks for learners who have been explicitly linked.
    #    - It cannot leak data from other learners in the same school.
    @learners = Learner.where(:parent_auth0_ids.in => [current_user_auth0_id]).active

    # 4. Render the learners as JSON.
    #    - The `to_api_hash` method is assumed to exist on the Learner model for serialization.
    render json: {
      learners: @learners.map(&:to_api_hash),
      count: @learners.count
    }, status: :ok
  end
end
