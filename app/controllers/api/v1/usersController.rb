# =============================================================================
# API::V1::USERS CONTROLLER
# =============================================================================
# This controller handles all user-related API operations for version 1 of the API.
# It provides endpoints for creating users, viewing user details, managing user roles,
# and retrieving schools associated with a user.
#
# Routes handled:
# - POST   /api/v1/users          -> create
# - GET    /api/v1/users/:id      -> show  
# - GET    /api/v1/users/:id/schools -> schools
# - PATCH  /api/v1/users/:id/roles -> update_roles
# =============================================================================

class Api::V1::UsersController < ApplicationController
  
  # =============================================================================
  # BEFORE ACTIONS
  # =============================================================================
  # This callback runs before specific actions to set up common data.
  # It finds the user based on the auth0_id from the URL parameter.
  before_action :set_user, only: [:show, :update_roles, :schools]

  # =============================================================================
  # CREATE USER ACTION
  # =============================================================================
  # Purpose: Creates a new user in the system
  # HTTP Method: POST
  # Endpoint: /api/v1/users
  # 
  # Expected Parameters:
  # - user[name]: String - User's full name
  # - user[email]: String - User's email address  
  # - user[auth0_id]: String - Unique identifier from Auth0 service
  # - user[roles]: Array - Array of role strings (optional)
  #
  # Response Format:
  # Success (201): { success: true, data: { user_object } }
  # Failure (422): { success: false, errors: ["error messages"] }
  def create
    # Create a new User instance with the permitted parameters
    user = User.new(user_params)

    # Attempt to save the user to the database
    if user.save
      # Success: Return the created user with 201 Created status
      render json: { success: true, data: user }, status: :created
    else
      # Failure: Return validation errors with 422 Unprocessable Entity status
      # .full_messages provides human-readable error descriptions
      render json: { success: false, errors: user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # =============================================================================
  # GET USER SCHOOLS ACTION  
  # =============================================================================
  # Purpose: Retrieves all schools associated with a specific user
  # HTTP Method: GET
  # Endpoint: /api/v1/users/:id/schools
  # 
  # URL Parameter:
  # - :id - The auth0_id of the user (not the database ID)
  #
  # Response Format:
  # Success (200): { success: true, data: { schools: [school_objects] } }
  # Not Found (404): { success: false, error: "No schools found for this user." }
  def schools
    # Extract the auth0_id from the user found by the before_action
    user_id = @user.auth0_id
    
    # Query the School model to find all schools belonging to this user
    # This assumes the School model has a user_id field that references auth0_id
    schools = School.where(user_id: user_id)

    # Check if any schools were found
    if schools.any?
      # Success: Return the schools array wrapped in a data object
      render json: { success: true, data: { schools: schools } }, status: :ok
    else
      # No schools found: Return error message with 404 status
      render json: { success: false, error: "No schools found for this user." }, status: :not_found
    end
  end  

  # =============================================================================
  # SHOW USER ACTION
  # =============================================================================
  # Purpose: Retrieves and displays a specific user's information
  # HTTP Method: GET  
  # Endpoint: /api/v1/users/:id
  #
  # URL Parameter:
  # - :id - The auth0_id of the user (set by before_action)
  #
  # Response Format:
  # Success (200): { success: true, data: { user_object } }
  # Not Found (404): Handled by set_user before_action
  def show
    # Simply return the user that was found and set by the before_action
    # @user is guaranteed to exist here because set_user would have returned early if not found
    render json: { success: true, data: @user }, status: :ok
  end

  # =============================================================================
  # UPDATE USER ROLES ACTION
  # =============================================================================
  # Purpose: Adds new roles to a user's existing roles (additive, not replacement)
  # HTTP Method: PATCH
  # Endpoint: /api/v1/users/:id/roles
  #
  # Expected Parameters:
  # - roles: Array - Array of role strings to add to the user
  #
  # Response Format:
  # Success (200): { success: true, data: { user_object } }
  # Failure (422): { success: false, errors: ["error messages"] }
  def update_roles
    # Get the new roles from parameters, defaulting to empty array if not provided
    new_roles = params[:roles] || []
    
    # Merge existing roles with new roles and remove duplicates using .uniq
    # This is ADDITIVE - it doesn't replace existing roles, just adds new ones
    @user.roles = (@user.roles + new_roles).uniq
  
    # Attempt to save the updated user
    if @user.save
      # Success: Return the updated user data
      render json: { success: true, data: @user }, status: :ok
    else
      # Failure: Return validation errors (e.g., if roles contain invalid values)
      render json: { success: false, errors: @user.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  # =============================================================================
  # PRIVATE METHODS
  # =============================================================================
  # These methods are only accessible within this controller class

  private

  # =============================================================================
  # STRONG PARAMETERS METHOD
  # =============================================================================
  # Purpose: Defines which parameters are allowed for user creation/updates
  # This is a security feature in Rails that prevents mass assignment vulnerabilities
  #
  # Permitted Parameters:
  # - name: String field
  # - email: String field  
  # - auth0_id: String field (unique identifier from Auth0)
  # - roles: Array field (can contain multiple role strings)
  def user_params
    # Require the 'user' key to be present, then permit specific nested attributes
    # The 'roles: []' syntax permits an array parameter named 'roles'
    params.require(:user).permit(:name, :email, :auth0_id, roles: [])
  end

  # =============================================================================
  # SET USER BEFORE ACTION METHOD
  # =============================================================================
  # Purpose: Finds a user by their auth0_id and sets it as an instance variable
  # This runs before the show, update_roles, and schools actions
  #
  # Key Points:
  # - Uses auth0_id (not database ID) as the lookup parameter
  # - Sets @user instance variable for use in the action methods
  # - Returns early with 404 error if user is not found
  # - Logs a warning when user lookup fails
  def set_user
    # Find user by auth0_id using the :id parameter from the URL
    # find_by returns nil if no user is found (doesn't raise an exception)
    @user = User.find_by(auth0_id: params[:id])
    
    # Check if user was found
    unless @user
      # Log the failed lookup attempt for debugging/monitoring
      Rails.logger.warn("User with auth0_id: #{params[:id]} not found")
      
      # Return 404 error and stop further processing
      # This prevents the main action from running when user doesn't exist
      render json: { success: false, error: "User not found" }, status: :not_found
    end
  end
end